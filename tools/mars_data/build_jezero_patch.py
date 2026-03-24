#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import json
import math
import os
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.enums import Resampling
from rasterio.windows import from_bounds

MARS_RADIUS_M = 3_396_190.0
JEZERO_STANDARD_PARALLEL_DEG = 18.4663
DEFAULT_CENTER_LAT = 18.4447
DEFAULT_CENTER_LON = 77.4508
DEFAULT_WORLD_SIZE_M = 1320.0
DEFAULT_HEIGHT_SIZE = 1320
DEFAULT_ALBEDO_SIZE = 2048

HIRES_DTM_URL = (
    "https://planetarymaps.usgs.gov/mosaic/mars2020_trn/HiRISE/"
    "JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif"
)
HIRES_ORTHO_URL = (
    "https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/HiRISE/"
    "JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif"
)
HIRES_ORTHO_BROWSE_CROP_URL = (
    "https://astrogeology.usgs.gov/ckan/dataset/cee23e0f-a7fb-4695-b1c8-f295f09a305f/"
    "resource/2784f141-e40a-4291-a67b-0c458077b6ab/download/"
    "jez_hirise_soc_006_orthomosaic_25cm_eqc_latts0_lon0_first_crop1024.jpg"
)
CTX_DEM_URL = (
    "https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/"
    "M20_JezeroCrater_CTXDEM_20m.tif"
)


@dataclass(frozen=True)
class SourceSpec:
    filename: str
    url: str


SOURCES = [
    SourceSpec("jezero_hirise_dtm_1m.tif", HIRES_DTM_URL),
    SourceSpec("jezero_hirise_ortho_25cm.tif", HIRES_ORTHO_URL),
    SourceSpec("jezero_ctx_dem_20m.tif", CTX_DEM_URL),
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build tracked Jezero terrain assets for Mars Protocol.")
    parser.add_argument(
        "--output-dir",
        default="assets/mars/jezero",
        help="Directory for tracked runtime assets.",
    )
    parser.add_argument(
        "--source-dir",
        default="build/mars_source/jezero",
        help="Directory for optional cached raw GeoTIFF sources.",
    )
    parser.add_argument(
        "--world-size-m",
        type=float,
        default=DEFAULT_WORLD_SIZE_M,
        help="Square crop size in meters.",
    )
    parser.add_argument(
        "--heightmap-size",
        type=int,
        default=DEFAULT_HEIGHT_SIZE,
        help="Output heightmap size in pixels.",
    )
    parser.add_argument(
        "--albedo-size",
        type=int,
        default=DEFAULT_ALBEDO_SIZE,
        help="Output albedo map size in pixels.",
    )
    parser.add_argument(
        "--center-lat",
        type=float,
        default=DEFAULT_CENTER_LAT,
        help="Patch center latitude, planetocentric degrees north.",
    )
    parser.add_argument(
        "--center-lon",
        type=float,
        default=DEFAULT_CENTER_LON,
        help="Patch center longitude, positive east degrees.",
    )
    parser.add_argument(
        "--download-raw",
        action="store_true",
        help="Download the full raw GeoTIFFs into source-dir before processing.",
    )
    return parser


def projected_meters_from_latlon(lat_deg: float, lon_deg: float) -> tuple[float, float]:
    lat_rad = math.radians(lat_deg)
    lon_rad = math.radians(lon_deg)
    lat_ts_rad = math.radians(JEZERO_STANDARD_PARALLEL_DEG)
    return (MARS_RADIUS_M * math.cos(lat_ts_rad) * lon_rad, MARS_RADIUS_M * lat_rad)


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    width = max(edge1 - edge0, 1e-6)
    t = np.clip((value - edge0) / width, 0.0, 1.0)
    return t * t * (3.0 - (2.0 * t))


def ensure_source_path(source_dir: Path, spec: SourceSpec, download_raw: bool) -> str:
    local_path = source_dir / spec.filename
    if local_path.exists():
        return str(local_path)
    if download_raw:
        source_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {spec.url} -> {local_path}")
        urllib.request.urlretrieve(spec.url, local_path)
        return str(local_path)
    return f"/vsicurl/{spec.url}"


def read_window(
    dataset_path: str,
    left: float,
    bottom: float,
    right: float,
    top: float,
    out_size: int,
    resampling: Resampling,
) -> np.ndarray:
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif"):
        with rasterio.open(dataset_path) as dataset:
            window = from_bounds(left, bottom, right, top, transform=dataset.transform)
            data = dataset.read(
                1,
                window=window,
                out_shape=(out_size, out_size),
                boundless=True,
                masked=True,
                resampling=resampling,
            )
            array = np.ma.filled(data, np.nan).astype(np.float32)
    return array


def read_rgb_window(
    dataset_path: str,
    left: float,
    bottom: float,
    right: float,
    top: float,
    out_size: int,
) -> np.ndarray:
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif"):
        with rasterio.open(dataset_path) as dataset:
            window = from_bounds(left, bottom, right, top, transform=dataset.transform)
            band_count = min(dataset.count, 3)
            data = dataset.read(
                list(range(1, band_count + 1)),
                window=window,
                out_shape=(band_count, out_size, out_size),
                boundless=True,
                masked=True,
                resampling=Resampling.bilinear,
            )
            array = np.ma.filled(data, np.nan).astype(np.float32)
    if array.shape[0] == 1:
        mono = array[0]
        array = np.stack([mono, mono, mono], axis=0)
    return np.transpose(array, (1, 2, 0))


def nanfill_nearest(array: np.ndarray) -> np.ndarray:
    result = np.array(array, copy=True)
    if not np.isnan(result).any():
        return result

    valid = np.isfinite(result)
    if not valid.any():
        raise RuntimeError("Encountered an all-NaN crop while extracting Jezero data.")

    finite_values = result[valid]
    fill_value = float(np.median(finite_values))
    result[~valid] = fill_value
    return result


def compute_slope(height_m: np.ndarray, pixel_size_m: float) -> np.ndarray:
    grad_y, grad_x = np.gradient(height_m, pixel_size_m, pixel_size_m)
    return np.sqrt((grad_x * grad_x) + (grad_y * grad_y))


def world_from_pixel(size: int, world_size_m: float, x_px: int, y_px: int) -> tuple[float, float]:
    denom = max(size - 1, 1)
    world_x = (float(x_px) / float(denom) - 0.5) * world_size_m
    world_z = (float(y_px) / float(denom) - 0.5) * world_size_m
    return world_x, world_z


def pixel_from_world(size: int, world_size_m: float, world_x: float, world_z: float) -> tuple[int, int]:
    denom = max(size - 1, 1)
    x_px = int(round(((world_x / world_size_m) + 0.5) * denom))
    y_px = int(round(((world_z / world_size_m) + 0.5) * denom))
    x_px = int(np.clip(x_px, 0, size - 1))
    y_px = int(np.clip(y_px, 0, size - 1))
    return x_px, y_px


def pick_spawn_pixel(height_m: np.ndarray, world_size_m: float) -> tuple[int, int]:
    size = height_m.shape[0]
    pixel_size_m = world_size_m / float(max(size - 1, 1))
    slope = compute_slope(height_m, pixel_size_m)
    center = size // 2
    search_radius_m = min(world_size_m * 0.18, 120.0)
    search_radius_px = int(math.ceil(search_radius_m / pixel_size_m))
    best_score = float("inf")
    best_xy = (center, center)

    for y_px in range(max(0, center - search_radius_px), min(size, center + search_radius_px + 1), 2):
        for x_px in range(max(0, center - search_radius_px), min(size, center + search_radius_px + 1), 2):
            dx_m = (x_px - center) * pixel_size_m
            dz_m = (y_px - center) * pixel_size_m
            dist_m = math.hypot(dx_m, dz_m)
            if dist_m > search_radius_m:
                continue
            y0 = max(0, y_px - 4)
            y1 = min(size, y_px + 5)
            x0 = max(0, x_px - 4)
            x1 = min(size, x_px + 5)
            local = height_m[y0:y1, x0:x1]
            roughness = float(np.std(local))
            score = (float(slope[y_px, x_px]) * 1.45) + (roughness * 0.85) + ((dist_m / max(search_radius_m, 1.0)) * 0.08)
            if score < best_score:
                best_score = score
                best_xy = (x_px, y_px)

    return best_xy


def pick_rover_pixel(height_m: np.ndarray, world_size_m: float, spawn_xy: tuple[int, int]) -> tuple[int, int]:
    size = height_m.shape[0]
    pixel_size_m = world_size_m / float(max(size - 1, 1))
    slope = compute_slope(height_m, pixel_size_m)
    spawn_x, spawn_y = spawn_xy
    best_score = float("inf")
    best_xy = (spawn_x, spawn_y)

    for y_px in range(0, size, 2):
        for x_px in range(0, size, 2):
            dx_m = (x_px - spawn_x) * pixel_size_m
            dz_m = (y_px - spawn_y) * pixel_size_m
            dist_m = math.hypot(dx_m, dz_m)
            if dist_m < 30.0 or dist_m > 45.0:
                continue
            y0 = max(0, y_px - 4)
            y1 = min(size, y_px + 5)
            x0 = max(0, x_px - 4)
            x1 = min(size, x_px + 5)
            local = height_m[y0:y1, x0:x1]
            roughness = float(np.std(local))
            east_preference = 0.0 if dx_m >= 0.0 else 0.55
            forward_preference = abs(dz_m + 10.0) * 0.012
            score = (float(slope[y_px, x_px]) * 1.6) + (roughness * 0.9) + east_preference + forward_preference
            if score < best_score:
                best_score = score
                best_xy = (x_px, y_px)

    return best_xy


def apply_flatten_patch(
    base_height_m: np.ndarray,
    delta_m: np.ndarray,
    world_size_m: float,
    center_xy: tuple[int, int],
    inner_radius_m: float,
    outer_radius_m: float,
    max_abs_delta_m: float,
) -> None:
    size = base_height_m.shape[0]
    pixel_size_m = world_size_m / float(max(size - 1, 1))
    cx, cy = center_xy
    radius_px = int(math.ceil(outer_radius_m / pixel_size_m))

    y0 = max(0, cy - 2)
    y1 = min(size, cy + 3)
    x0 = max(0, cx - 2)
    x1 = min(size, cx + 3)
    target_height_m = float(np.median(base_height_m[y0:y1, x0:x1]))

    for y_px in range(max(0, cy - radius_px), min(size, cy + radius_px + 1)):
        for x_px in range(max(0, cx - radius_px), min(size, cx + radius_px + 1)):
            dist_m = math.hypot((x_px - cx) * pixel_size_m, (y_px - cy) * pixel_size_m)
            if dist_m > outer_radius_m:
                continue
            if dist_m <= inner_radius_m:
                blend = 1.0
            else:
                blend = 1.0 - float(smoothstep(inner_radius_m, outer_radius_m, np.array([dist_m], dtype=np.float32))[0])
            desired_delta = (target_height_m - float(base_height_m[y_px, x_px])) * blend
            desired_delta = float(np.clip(desired_delta, -max_abs_delta_m, max_abs_delta_m))
            delta_m[y_px, x_px] += desired_delta


def uint16_png_from_normalized(normalized: np.ndarray, output_path: Path) -> None:
    clipped = np.clip(normalized, 0.0, 1.0)
    uint16 = np.round(clipped * 65535.0).astype(np.uint16)
    image = Image.fromarray(uint16, mode="I;16")
    image.save(output_path)


def uint16_png_from_signed(normalized_signed: np.ndarray, output_path: Path) -> None:
    clipped = np.clip((normalized_signed * 0.5) + 0.5, 0.0, 1.0)
    uint16_png_from_normalized(clipped, output_path)


def rgb_png_from_array(array: np.ndarray, output_path: Path) -> None:
    sanitized = np.nan_to_num(array, nan=np.nanmean(array))
    low = float(np.percentile(sanitized, 1))
    high = float(np.percentile(sanitized, 99))
    if high - low < 1e-6:
        high = low + 1.0
    normalized = np.clip((sanitized - low) / (high - low), 0.0, 1.0)
    image = Image.fromarray(np.round(normalized * 255.0).astype(np.uint8), mode="RGB")
    image.save(output_path)


def fetch_browse_rgb(url: str, output_size: int) -> np.ndarray:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            "Referer": "https://astrogeology.usgs.gov/",
        },
    )
    with urllib.request.urlopen(request) as response:
        payload = response.read()
    image = Image.open(io.BytesIO(payload)).convert("RGB")
    image = image.resize((output_size, output_size), Image.Resampling.LANCZOS)
    return np.asarray(image, dtype=np.float32)


def build_preview(
    albedo_rgb: np.ndarray,
    output_path: Path,
    spawn_xy: tuple[int, int],
    rover_xy: tuple[int, int],
) -> None:
    preview = np.clip(albedo_rgb, 0.0, 255.0).astype(np.uint8)
    image = Image.fromarray(preview, mode="RGB")
    draw = ImageDraw.Draw(image)
    sx, sy = spawn_xy
    rx, ry = rover_xy
    draw.ellipse((sx - 14, sy - 14, sx + 14, sy + 14), outline=(80, 255, 180), width=4)
    draw.ellipse((rx - 12, ry - 12, rx + 12, ry + 12), outline=(255, 220, 90), width=4)
    draw.line((sx, sy, rx, ry), fill=(255, 220, 90), width=2)
    image.save(output_path)


def main() -> None:
    args = build_parser().parse_args()
    output_dir = Path(args.output_dir)
    source_dir = Path(args.source_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    source_dir.mkdir(parents=True, exist_ok=True)

    center_x_m, center_y_m = projected_meters_from_latlon(args.center_lat, args.center_lon)
    half_world = args.world_size_m * 0.5
    left = center_x_m - half_world
    right = center_x_m + half_world
    bottom = center_y_m - half_world
    top = center_y_m + half_world

    source_paths = {
        spec.filename: ensure_source_path(source_dir, spec, args.download_raw)
        for spec in SOURCES
    }

    print("Reading CTX DEM crop...")
    height_m = read_window(
        source_paths["jezero_ctx_dem_20m.tif"],
        left,
        bottom,
        right,
        top,
        args.heightmap_size,
        Resampling.bilinear,
    )
    height_m = nanfill_nearest(height_m)

    print("Computing spawn/rover positions and delta mask...")
    spawn_xy = pick_spawn_pixel(height_m, args.world_size_m)
    rover_xy = pick_rover_pixel(height_m, args.world_size_m, spawn_xy)

    delta_m = np.zeros_like(height_m, dtype=np.float32)
    apply_flatten_patch(height_m, delta_m, args.world_size_m, spawn_xy, inner_radius_m=6.0, outer_radius_m=12.0, max_abs_delta_m=0.85)
    apply_flatten_patch(height_m, delta_m, args.world_size_m, rover_xy, inner_radius_m=4.0, outer_radius_m=9.0, max_abs_delta_m=0.55)

    min_height_m = float(np.min(height_m))
    max_height_m = float(np.max(height_m))
    if max_height_m - min_height_m < 1e-6:
        raise RuntimeError("Height crop is unexpectedly flat.")

    height_normalized = (height_m - min_height_m) / (max_height_m - min_height_m)
    delta_abs_m = max(abs(float(np.min(delta_m))), abs(float(np.max(delta_m))), 0.01)
    delta_normalized_signed = delta_m / delta_abs_m

    spawn_elevation_m = float(height_m[spawn_xy[1], spawn_xy[0]] + delta_m[spawn_xy[1], spawn_xy[0]])
    vertical_offset_m = spawn_elevation_m

    print("Fetching HiRISE orthomosaic browse crop...")
    albedo_rgb = fetch_browse_rgb(HIRES_ORTHO_BROWSE_CROP_URL, args.albedo_size)

    spawn_world_x, spawn_world_z = world_from_pixel(args.heightmap_size, args.world_size_m, *spawn_xy)
    rover_world_x, rover_world_z = world_from_pixel(args.heightmap_size, args.world_size_m, *rover_xy)

    height_path = output_dir / "height_16.png"
    delta_path = output_dir / "playability_delta_16.png"
    albedo_path = output_dir / "albedo_2048.png"
    preview_path = output_dir / "preview.png"
    metadata_path = output_dir / "metadata.json"

    print(f"Writing {height_path} ...")
    uint16_png_from_normalized(height_normalized, height_path)
    print(f"Writing {delta_path} ...")
    uint16_png_from_signed(delta_normalized_signed, delta_path)
    print(f"Writing {albedo_path} ...")
    rgb_png_from_array(albedo_rgb, albedo_path)

    preview_scale = 1024
    preview = np.array(Image.open(albedo_path).resize((preview_scale, preview_scale), Image.Resampling.LANCZOS))
    scale_x = preview_scale / float(args.albedo_size)
    scale_y = preview_scale / float(args.albedo_size)
    preview_spawn = (int(round((spawn_xy[0] / float(args.heightmap_size - 1)) * (preview_scale - 1))), int(round((spawn_xy[1] / float(args.heightmap_size - 1)) * (preview_scale - 1))))
    preview_rover = (int(round((rover_xy[0] / float(args.heightmap_size - 1)) * (preview_scale - 1))), int(round((rover_xy[1] / float(args.heightmap_size - 1)) * (preview_scale - 1))))
    build_preview(preview, preview_path, preview_spawn, preview_rover)

    metadata = {
        "dataset_name": "USGS Mars 2020 Jezero landing patch",
        "source_urls": {
            "hirise_dtm_1m": HIRES_DTM_URL,
            "hirise_ortho_25cm": HIRES_ORTHO_URL,
            "hirise_ortho_browse_crop_1024": HIRES_ORTHO_BROWSE_CROP_URL,
            "ctx_dem_20m": CTX_DEM_URL,
        },
        "elevation_source": "ctx_dem_20m",
        "center_lat": args.center_lat,
        "center_lon": args.center_lon,
        "world_size_m": args.world_size_m,
        "heightmap_size": args.heightmap_size,
        "min_elevation_m": min_height_m,
        "max_elevation_m": max_height_m,
        "vertical_offset_m": vertical_offset_m,
        "spawn_world_xz": [spawn_world_x, spawn_world_z],
        "rover_world_xz": [rover_world_x, rover_world_z],
        "playability_delta_path": "playability_delta_16.png",
        "playability_delta_abs_max_m": delta_abs_m,
        "surface_map_path": "albedo_2048.png",
        "surface_map_strength": 0.42,
        "surface_map_black_point": 0.04,
        "surface_map_white_point": 0.84,
        "generated_from_remote_window_reads": not args.download_raw,
    }
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {metadata_path}")


if __name__ == "__main__":
    main()
