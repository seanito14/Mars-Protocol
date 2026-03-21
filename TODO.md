# Mars Protocol — Master To-Do List
> **Goal**: Make the game visually and functionally match the Monument Valley reference image, with a polished open-world survival experience.

---

## 1. TERRAIN, WORLD COMPOSITION & MAP UNIFICATION

### 1.1 Canonical Reference
- [x] Import `res://assets/reference/STRICT-COPY.jpg` and use it as the single source of truth for all exterior world art decisions.
- [x] The image is not “inspiration”; it is the exact composition target for the first controllable landing frame and the macro look for the unified exterior world.
- [x] `landing_valley` becomes the only canonical exterior map. `hero_demo` and `world` no longer define separate macro compositions; they only donate useful subregions, gameplay motifs, or material ideas.
- [x] `clone_iteration` may vary micro detail only: prop scatter, salvage state, POI activation, erosion noise, and minor set dressing. It must never reshape the macro landmarks or opening shot.

### 1.2 Exact Frame Composition
- [x] Lock the first controllable frame to measured screen-space targets from `STRICT-COPY.jpg`: horizon line at `48% +/- 2%` of frame height, rover centroid at `60% +/- 2%` width and `61% +/- 2%` height, left mega-mesa silhouette spanning roughly `4%-31%` of frame width, central broad mesa centered near `46%` width, right hero butte occupying roughly `83%-97%` width.
- [x] Camera height, yaw, pitch, and FOV are part of the environment spec and must remain deterministic across intro completion, intro skip, Continue, and clone redeploy.
- [x] The open dune corridor between the left foreground mesa and the right buttes must remain readable enough that the rover sits in the same mid-ground pocket as the reference.

### 1.3 Authored Macro Terrain
- [x] Replace noise-led hero landmark placement with authored macro masks or SDF-style terrain primitives for every major visible formation: left mega-mesa, left attached spire, center broad mesa, center narrow stack, right mid butte, far-right hero butte, and distant ridge walls.
- [x] Build each major formation from realistic components: pedestal mass, cliff wall zone, terrace bands, caprock, attached spires, slump shelves, and talus fans. Avoid single radial “blob” mesas.
- [x] Shape dunes as wind-directed corridor forms that wrap around mesa bases and collect in saddles; do not use a uniform ripple field across the whole map.
- [x] Hide the spawn stabilization patch inside the dune field so there is no visible flat shelf, seam, or platform in the reference frame.

### 1.4 Unified Exploration Layout
- [x] Extend the exact reference shot into one explorable basin with three readable routes: left shadow route, central rover corridor, and right butte route, all reconnecting behind the mid-ground landmarks.
- [x] Migrate old `hero_demo` / `world` gameplay beats into side basins within the same world instead of sending the player to visually different exterior maps.
- [x] Hide map closure with ridgelines, haze, and rising terrain. No underside seal, subfloor cap, void, or abrupt world lip may be visible from normal gameplay.

### 1.5 Terrain Material Realism
- [x] Keep the terrain visually darker than the sky at the horizon. The ground must read as rust-orange regolith and rock, never as the same value band as the sky.
- [x] Separate material zones are required for dune dust, compacted valley floor, talus, vertical cliff wall, and caprock.
- [x] Sedimentary layering must come from height, slope, curvature-style breakup, and erosion masks, not decorative striping or exaggerated shader bands.

### 1.6 Terrain Mastery (Research-Led Phase) [DONE 2026-03-22]
- [x] **Geologic Primitives**: Refactor `_mesa_height` from radial blobs to a composite formula: `BasePedestal + CliffWall + CaprockPlateau`. Each component must have its own noise frequency and erosion multiplier.
- [x] **Sedimentary Strata**: Implement height-based quantization in the terrain generation logic (not just the shader). Use `floor(height * strata_count) / strata_count` mixed with a "softness" noise to create varied, realistic horizontal rock layers.
- [x] **Talus Slope Simulation**: Add a post-processing pass to the height calculation that identifies steep cliff zones and "accumulates" height at their base (y-offset of the mesa foot) to create 45-degree debris ramps seen in the reference.
- [x] **Wind-Shadow Dunes**: Create a "mesa proximity mask". Invert it and multiply with dune noise to simulate sand "drifting" and accumulating in the wind-shadows of the large formations rather than being uniform.
- [x] **Silhouette Screen-Space Parity**: Perform a final pass on mesa transforms to ensure their silhouettes cover the exact 2D screen-space pixel coordinates derived from `STRICT-COPY.jpg`.

---

## 2. ENVIRONMENT, LIGHTING & PHOTOREAL SHOT MATCH

### 2.1 Shared Exterior Visual Profile
- [x] Add one shared reference-driven visual profile/resource for exterior scenes so sky colors, fog, sun direction, terrain palette, and camera framing do not drift between scenes or code paths.
- [x] Any remaining exterior scene kept for testing or fallback must inherit this profile rather than inventing a separate sky/terrain palette.

### 2.2 Sky & Atmosphere
- [x] Match `STRICT-COPY.jpg` with a pale dusty gradient: brighter peach-beige at the horizon, lighter tan-grey overhead, no clouds, no saturated sci-fi orange sky.
- [x] If `PhysicalSkyMaterial` cannot reproduce the gradient cleanly, replace it with a custom sky shader/material instead of accepting a near miss.
- [x] Use atmospheric haze to separate depth planes only: near dunes remain readable, mid-ground mesas stay warm and detailed, distant mesas soften and desaturate without washing the ground into the sky.

### 2.3 Lighting Calibration
- [x] Calibrate the dominant directional light from the reference shadow geometry, not from taste. In the first playable frame, the left foreground mesa shadow must project diagonally into the valley with a footprint matching the still image.
- [x] Fill light is only allowed to preserve silhouette readability; it must not flatten shadows or erase the deep rust-brown separation on shaded cliff faces.
- [x] Ambient light must stay warm and low-value so shaded rock reads as dark brown/maroon, not bright orange-grey.

### 2.4 Terrain Shading & Color Separation
- [x] Cliff faces need realistic layered warm browns, sienna mids, and lighter dusty tops, but the blending must stay geologic and subtle.
- [x] Valley floor shading must favor broad wind-shaped tonal variation, embedded rock occlusion, and dust accumulation over repetitive procedural wave patterns.
- [x] Distant formations must lose contrast with depth while still remaining darker and more solid than the sky behind them.

### 2.5 Reference-Locked Handoff
- [x] `opening_intro -> landing_valley`, intro skip, Continue, and clone redeploy must all land on the same macro composition and camera framing.
- [x] HUD fade-in and any post-processing overlays may not alter the raw first world frame before it is composition-matched to the reference.
- [x] Any lighting or material change that improves realism but breaks the reference shot is a regression.

---

## 3. PROPS & ENVIRONMENTAL OBJECTS

### 3.1 Rocks (Ground Clutter)
- [ ] The foreground of the reference image has **sharply angular, chunky rocks** of various sizes, not smooth spheres. The pebble mesh is currently `SphereMesh`. **Switch to `BoxMesh` with non-uniform scale** or better yet, use a custom `.tres` angular rock mesh for more visual fidelity.
- [ ] Rock colors in the reference vary between dark rust, deep brown, and orange highlights. The current single `albedo_color` creates monotony. **Introduce 3-4 color variations** by randomizing the albedo per-instance with `MultiMesh.use_colors = true` and `set_instance_color()`.
- [ ] The image shows some small **dark bushes/tumbleweed-like clumps** near rocks. **Add a `DECORATIVE_BRUSH_COUNT`** using low flat cylinder meshes with very dark brown/black color to simulate dried vegetation patches.
- [ ] Larger rocks in the reference cast visible shadows. **Ensure `cast_shadow` on boulder MultiMesh is enabled** (currently set to `SHADOW_CASTING_SETTING_OFF` for pebbles — acceptable, but boulders should cast shadows).

### 3.2 Rover
- [ ] The rover in the reference image is small, detailed, and white/grey — matching a NASA rover. **Verify `rover.gd` procedural geometry** is producing appropriately scaled and colored meshes that read as "white rover" against the orange terrain.
- [ ] The rover should leave **wheel tracks** in the terrain if possible. This is a stretch goal but would significantly increase immersion.

### 3.3 Wrecks & Debris
- [ ] The `HeroWreck` visual uses grey metallic `StandardMaterial3D`. Against the vibrant orange terrain, these should have **slight rust tinting** (`albedo_color: 0.25, 0.18, 0.14`) to feel like they've been on Mars for a while.
- [ ] `DebrisCube` instances glow orange/gold and hover. They're aesthetically consistent but need to be **scattered more densely** near wreck sites for visual storytelling.
- [ ] Add **debris trails** — small non-interactable chunks of metal placed linearly between the spawn point and the primary wreck to guide the player visually.

---

## 4. UI / UX

### 4.1 HUD (`hero_hud.gd`)
- [ ] The HUD frame is styled as a heavy brown sci-fi visor, but the `_draw_visor_frame()` polygon corners feel hard-coded. **Test at multiple viewport resolutions** (1080p, 1440p, 4K, mobile) to ensure the frame scales properly and doesn't clip.
- [ ] The reticle `_draw_reticle()` draws a `[ - . - ]` pattern. In the reference image provided earlier, this looks correct. **Ensure the reticle disappears when interacting** with terminals (basecamp, paywall) to avoid visual clutter over modal UIs.
- [ ] The bottom-left and bottom-right text panels (`560`, `Channel`, `Du resivlesennal gennesisir`, `713`) are placeholder content. **Replace with live data**: O2%, Suit Power%, Temp Resistance%, Heart Rate, Mission Clock, Storm ETA.
- [ ] **Add a minimap or compass bar** at the top of the visor showing heading degrees and waypoint direction. The `player.gd` already calculates `heading_degrees` and `heading_label` — just not displayed.
- [ ] **Add a subtle visor vignette** via the `hero_visor_overlay.gdshader` — the reference shows darkened corners typical of a space helmet visor.

### 4.2 Interaction Prompts
- [ ] Interaction prompts (*"Press E or tap INTERACT"*) appear only in the mission log. **Add a floating 3D label or HUD overlay** that shows "E — Inspect" near the reticle when `focused_interactable != null`.
- [ ] The interaction system has no visual indicator on the 3D object itself. **Add a subtle highlight outline or glow pulse** to the focused interactable.

### 4.3 Main Menu (`main_menu.tscn`)
- [ ] The current Main Menu is a bare `ColorRect` + `VBoxContainer` with default Godot buttons. **Style it with the same sci-fi brown/rust aesthetic** as the HUD visor frame.
- [ ] **Add a background scene**: render the Mars environment behind the menu (either a static screenshot or a looping camera flyover of the terrain).
- [ ] **Add title subtitle text**: "*Sol 247 — Clone Iteration 14*" under the main title to set mood.
- [ ] **Add a Settings button** with volume, mouse sensitivity, and FOV sliders.

### 4.4 Game Over Screen (`game_over.tscn`)
- [x] Currently shows basic text stats. **Add dramatic styling**: flickering red warning text, static noise overlay, and the clone iteration count displayed large.
- [x] **Show a summary panel** with: Sols survived, Cubes collected, Rocks surveyed, Drones deployed, Distance walked.
- [x] **Add a countdown timer** before "DEPLOY NEXT CLONE" becomes clickable (2-3 seconds) to build tension.

### 4.5 Pause Menu
- [x] There is currently **no pause menu**. Pressing Escape just releases the mouse. **Implement a pause overlay** with Resume, Settings, Main Menu, and Quit options.

### 4.6 Mission Log
- [x] `EventBus.push_mission_log()` fires events but the HUD doesn't display a visible log panel. **Add a scrollable text area** (bottom center or left) that fades messages in/out over 5-8 seconds.

---

## 5. OPEN WORLD GAMEPLAY

### 5.1 Discovery & Exploration
- [ ] The open world currently has 2 wrecks, 8 rocks, 1 rover, 1 drone, and scattered debris. **Add procedural points of interest (POIs)**: crashed satellite dishes, solar panel arrays, abandoned habitat modules, and equipment crates scattered around the mesas.
- [ ] **Add collectible data logs** (audio or text) that tell the backstory of the ARES mission. Each one found restores a small amount of oxygen/suit power as a reward.
- [ ] The world lacks visual landmarks to help the player navigate. **Paint distinct color marks or flags** on certain mesas (via unique shader parameters per mesa instance) so players can orient themselves: "I'll head toward the red mesa."

### 5.2 Traversal
- [ ] Walking is the only mode of transport. The rover (`rover.gd`) is parked at a static position and only acts as an oxygen refill station. **Make the rover drivable** — the player should be able to enter and drive it across the desert at increased speed.
- [ ] **Add stamina to sprinting** — currently the player can run indefinitely (just with increased drain). Consider tying sprint to suit power with a more noticeable speed penalty when low.
- [ ] The drone follows the player and can `scan_area`. **Give it a "Scout Mode"** where pressing a key sends it 100m ahead in the player's facing direction, revealing nearby POIs on the HUD.

### 5.3 Resource Loop
- [ ] The player spawns with full resources and slowly drains. **Add resource pickups in the open world**: oxygen canisters near crash sites, battery cells near solar panels, thermal blankets near equipment crates.
- [ ] The Basecamp Terminal allows upgrades but spawns at a fixed position (not defined in `hero_demo.gd`). **Place a visible Basecamp Terminal node** near the spawn area with a distinct visual beacon.
- [ ] **Add a Shelter mechanic**: when the storm arrives (ETA = 0), the player should be able to duck behind mesas or inside wreck structures to reduce temperature drain. Check proximity to large meshes and reduce the 15x storm multiplier.

### 5.4 Storm System
- [ ] The storm is currently only a `storm_column` visual (6 semi-transparent cylinders far from the player). **Add screen-space dust effects** when the storm arrives: particle overlay on the camera, reduced visibility distance, increased fog density.
- [ ] **Make the storm visually advance**: the `storm_center` should slowly move toward the player over time, creating visible dust clouds on the horizon that get closer.
- [ ] **Add wind SFX** (stretch goal): a howling ambient loop that fades in as `storm_eta_seconds` approaches 0.

---

## 6. PERSISTENCE & PROGRESSION

- [ ] `save_game()` currently saves `salvage_cubes`, `upgrade_levels`, `sol_day`, and `clone_iteration`. **Also persist**: `respawn_position`, `respawn_yaw`, total play time, and discovered POIs.
- [ ] **Auto-save every 60 seconds** during gameplay in addition to the explicit save triggers.
- [ ] **Add multiple save slots** (3 slots) so the player can maintain separate runs.

---

## 7. AUDIO /skipped for now

- [ ] There is **no ambient audio**. **Add a looping wind ambience** track that plays continuously during gameplay.
- [ ] **Add footstep SFX**: crunching sounds on the regolith, varying by walk vs. run speed.
- [ ] **Add interaction SFX**: a mechanical click/whir when inspecting wrecks, a chime when collecting debris cubes, a beep sequence when using the basecamp terminal.
- [ ] **Add a low heartbeat SFX** that fades in when oxygen drops below `LOW_RESOURCE_THRESHOLD` (25%).
- [ ] Superseded by **Section 10. SUDO AI VOICE / WAKE WORD** below. The old `F`-hold assumption is no longer the target design; spoken `"sudo"` is primary, with `F` and DualShock square kept only as fallback activators.

---

## 8. PERFORMANCE

- [ ] `TERRAIN_RESOLUTION: 350` generates `351 * 351 = ~123k vertices` plus normals. **Profile the frame time** on target hardware. If above 16ms, consider LOD chunks or reducing distant-terrain resolution.
- [ ] `DECORATIVE_PEBBLE_COUNT: 4500` and `DECORATIVE_BOULDER_COUNT: 800` use `MultiMesh`, which is GPU-instanced and efficient. **Verify draw call count** in the Godot profiler to ensure these aren't causing overhead.
- [ ] The `_populate_rock_multimesh()` function uses a `while` loop with `attempts < count * 30`. With `count = 4500`, that's 135,000 iterations at startup. **Profile `_ready()` time** and optimize if load time exceeds 2 seconds.
- [ ] `hero_hud.gd` calls `queue_redraw()` every single frame in `_process()`. This forces the `_draw()` function to re-execute 60+ times per second. **Cache the drawn frame** and only redraw when viewport size changes or player status updates materially.

---

## 9. POLISH & JUICE

- [ ] **Add a camera shake** on clone failure (small amplitude, 0.3s duration).
- [ ] **Add a subtle red flash overlay** when the player takes health damage from depleted suit power or temperature.
- [ ] **Add breath condensation particles** from the helmet visor position to reinforce the cold environment theme.
- [ ] **Add a smooth camera pan** on spawn — instead of instantly snapping to the play position, smoothly dolly the camera down from an overhead view during the first 2 seconds.
- [ ] The `opening_intro.gd` plays a video then transitions. **Add a brief loading screen** between the intro and `hero_demo.tscn` showing "INITIALIZING CLONE PROTOCOL..." text.

---

## FILE REFERENCE

| Script | Role |
|---|---|
| `hero_demo.gd` | Main world: terrain gen, mesa shapes, prop spawning, mission logic |
| `hero_demo_config.gd` | Spawn/wreck/rover positions, terrain size |
| `player.gd` / `hero_player.gd` | Movement, input, survival stats, interaction system |
| `hero_hud.gd` | Custom-drawn visor frame, reticle, text panels |
| `game_state.gd` | Singleton: salvage, upgrades, save/load, storm timer |
| `terrain.gdshader` | Terrain coloring: dust/rock blend, ripples, micro-pebbles |
| `hero_wreck.gd` | Wreck cluster: procedural visuals, beacon, interaction |
| `debris_cube.gd` | Collectible glowing cube: hover animation, salvage reward |
| `rock.gd` | Scannable rock sample: geology cataloging |
| `rover.gd` | Procedural NASA rover model, oxygen refill |
| `drone.gd` | Scout drone: follows player, area scan |
| `main_menu.gd` | Start screen: New Game / Continue / Quit |
| `game_over.gd` | Death screen: clone iteration stats, respawn |
| `opening_intro.gd` | Video intro: adaptive fill, skip, preload |
| `landing_valley.gd` | Alternate level with its own mesa profile |

---

## Section 1 & 2 Completion Log (Current Session)

### Section 1 — Terrain, World Composition & Map Unification ✓
- [x] Created `scripts/mars_exterior_profile.gd` — shared visual profile with all sky/fog/lighting/terrain shader constants derived from STRICT-COPY.jpg analysis.
- [x] `landing_valley` is now the canonical exterior map. Mesa placements retuned for exact STRICT-COPY composition:
  - Left mega-mesa at (-248, 108) with 256m height, attached spire and slump shelf.
  - Center broad mesa at (-22, -48) with center narrow stacks behind.
  - Right mid butte at (168, -28), companion spire, and far-right hero butte at (312, 32).
  - 7 distant ridge/stack formations for full horizon layering.
- [x] Camera spawn locked: pos (8, 0, 216), yaw -2.4°, pitch -1.8°, FOV 62°.
- [x] Rover repositioned to (66, 0, 82) for mid-ground pocket matching reference.
- [x] Wind-directed dune corridors added (saddle dune, adjusted foreground lane, berms).
- [x] Spawn pad reduced to 96m radius with micro-noise, hidden inside dune field.
- [x] `_configure_landing_visuals()` now calls `MarsExteriorProfile.apply_*()` methods.
- [x] `hero_demo.gd` seal material updated to use shared profile.
- [x] Distant ridge blocks added for fuller skyline coverage.

### Section 2 — Environment, Lighting & Photoreal Shot Match ✓
- [x] Shared profile applied to both `landing_valley.tscn` and `hero_demo.tscn`.
- [x] Sky: Desaturated pale peach (rayleigh 0.88/0.72/0.58, mie 0.96/0.84/0.68, turbidity 10.8).
- [x] Fog: Subtle warm haze (density 0.00038, aerial_perspective 0.26, sun_scatter 0.22).
- [x] Key light: warm white (1.0/0.88/0.74), energy 2.65, shadow_max_distance 1800.
- [x] Fill light: barely-there (0.78/0.58/0.42), energy 0.14, no shadows.
- [x] Ambient: low warm (0.2/0.13/0.08) — shadows read as dark brown/maroon.
- [x] `terrain.gdshader` reworked:
  - Broader 3-band geologic height blending (0.08→0.88).
  - Wind-directional floor tonal variation (two overlapping sin waves).
  - Curvature-aware cliff darkening instead of uniform slope multiply.
  - Depth-distance desaturation (distant formations lose contrast to 35% haze).
  - Ground brightness capped below sky (floor 0.74, peak 0.98).
- [x] `hero_demo.gd` storm atmosphere baseline values aligned with new fog profile.
- [x] Terrain shader params in both `.tscn` files match profile values (no flash of wrong colors).
- [x] Validation: both scenes load clean under `godot --headless`, no parse/script errors.

---

**Section 4.1 HUD — done (2026-03-22).** Responsive visor frame via `_safe_layout()`, live O2/PWR/TMP/HR + mission clock & storm ETA, top compass (heading + WP bearing bar), reticle hidden when `GameState.is_modal_open()`, full-screen `hero_visor_overlay` vignette; `hero_player.gd` suit/temp/HR + rover restore hooks.

---

## Section 4.4-4.6 Completion Log (2026-03-22)
- [x] **Section 4.4 Game Over Screen** implemented in `scripts/game_over.gd`:
  - Dramatic styling with flickering red warning text and static noise shader overlay.
  - Large clone iteration number display ("CLONE #N TERMINATED").
  - Summary panel showing: Sols survived, Cubes collected, Rocks surveyed, Drones deployed, Distance walked.
  - 3-second countdown timer before "DEPLOY NEXT CLONE" becomes clickable.
  - Session stats tracking added to `game_state.gd`.
- [x] **Section 4.5 Pause Menu** implemented in `scripts/pause_menu.gd` and `scenes/pause_menu.tscn`:
  - Full pause overlay with darkened background.
  - Resume, Settings, Main Menu, and Quit buttons.
  - Settings panel with Volume, Mouse Sensitivity, and FOV sliders.
  - Integrated with `hero_hud.gd` via `toggle_pause_menu()` method.
  - Proper pause state management (`get_tree().paused`).
- [x] **Section 4.6 Mission Log** implemented in `scripts/hero_hud.gd`:
  - Mission log container at bottom center of screen.
  - Messages fade in and auto-fade out over 6 seconds.
  - Maximum 5 concurrent log entries.
  - Connected to `EventBus.mission_log_entry` signal.

---

## Section 3 Completion Log (2026-03-22)
- [x] Section 3.1 implemented in `scripts/hero_demo.gd`:
  - Decorative pebble clutter switched to angular `BoxMesh` with non-uniform scales.
  - Added 3-4 per-instance color variations for pebbles and boulders using `MultiMesh.use_colors` and `set_instance_color()`.
  - Added `DECORATIVE_BRUSH_COUNT` dark brush/tumbleweed clumps via low-profile `CylinderMesh` instances.
  - Kept pebble shadows off for performance and ensured boulder shadows are enabled.
- [x] Section 3.2 implemented across `scripts/hero_demo.gd` and `scripts/rover.gd`:
  - Added procedural rover wheel-track lanes (`RoverTracks`) extending from the rover toward the play space.
  - Retuned rover materials to read as a small white/grey NASA-style unit against orange terrain.
- [x] Section 3.3 implemented across `scripts/hero_demo.gd` and `scripts/hero_wreck.gd`:
  - Updated wreck body material rust tint to `Color(0.25, 0.18, 0.14, 1.0)`.
  - Increased debris density near both wreck sites with seeded cluster spawning.
  - Added a non-interactable debris trail from spawn toward the primary wreck for visual guidance.
- [x] Regression fixes included in Section 3:
  - Resolved `MultiMesh` color initialization/runtime errors by enabling colors before instance assignment.
  - Resolved debris trail transform errors by parenting chunks before setting global transforms.
- [x] Validation tests passed:
  - `godot --headless --path . --scene res://scenes/hero_demo.tscn --quit-after 30`
  - `godot --headless --path . --scene res://scenes/opening_intro.tscn --quit-after 30`
- [x] Visual validation passed:
  - Render capture succeeded: `godot --path . --scene res://scenes/hero_demo.tscn --quit-after 6 --write-movie /tmp/hero_demo_section3.avi`
  - Sampled frames (`/tmp/hero_demo_section3_frame_01.png`, `/tmp/hero_demo_section3_frame_02.png`) confirm denser clutter/debris, visible debris trail, and white/grey rover readability.

---

## 10. SUDO AI VOICE / WAKE WORD

### 10.1 Canonical Voice Stack
- [ ] `SudoAIAgent` is the only canonical player-facing conversational AI path in gameplay scenes.
- [ ] `hero_voice_service.gd` is legacy/dev fallback only and must stay disconnected from the main `hero_demo` and `landing_valley` experience.
- [ ] `VoiceAlertService` remains separate for suit/system warnings and must not own wake-word or live conversation state.

### 10.2 Standby Wake Listening
- [ ] Run wake-word detection through the local Python voice companion, not through the cloud conversation socket.
- [ ] The companion must listen locally for `"sudo"` and emit localhost UDP wake events to Godot on a dedicated port separate from `CommandServer`.
- [ ] Standby mic audio must never be streamed to ElevenLabs before activation.
- [ ] HUD/mission log states must include `LISTENING FOR SUDO`, `STANDBY`, `MIC BLOCKED`, `CONNECTING`, `SPEAKING`, `TIMEOUT`, and `OFFLINE`.

### 10.3 Activation Flow
- [ ] Activation sources are spoken `"sudo"` plus manual fallback via `F` and DualShock square.
- [ ] Both wake and manual activation must use the same `SudoAIAgent` flow: request signed URL from the bridge, connect to ElevenLabs, then enter live conversation.
- [ ] The old hold-to-activate `F` behavior is retired. `F` is now a press-to-activate fallback only.
- [ ] The full greeting line plays only once per gameplay scene/session; later activations in the same scene go straight into listening.

### 10.4 Active Conversation Window
- [ ] After activation, only active-conversation mic audio is streamed to ElevenLabs through the signed WebSocket session.
- [ ] A short silence timeout must return SudoAI to local standby and re-enable the wake listener automatically.
- [ ] `"sudo"` must reactivate cleanly after timeout without scene reloads, manual reconnect hacks, or repeated greeting spam.

### 10.5 Safety, UX, and Anti-Loop Rules
- [ ] Wake detections must be debounced so repeated `"sudo"` utterances do not retrigger during greeting playback, agent speech, or an already-active session.
- [ ] The wake detector must be paused while the agent is greeting/speaking so the agent never wakes itself.
- [ ] Intro, menu, and pause/modal states must disable gameplay standby listening; only active gameplay scenes may listen for `"sudo"`.
- [ ] If the mic is blocked, wake dependencies are missing, or the wake model is unavailable, the game must stay playable and `F` / DualShock square must remain usable fallbacks.

### 10.6 Gameplay Routing
- [ ] Route SudoAI transcripts through the same scene `handle_voice_command()` contract used by the old local voice path when a gameplay scene exposes it.
- [ ] `hero_demo` and `landing_valley` must both provide the canonical SudoAI flow, overlay, scene context, and mission-log feedback.
- [ ] Mission log must show wake detection, player transcript, agent response, ElevenLabs connection state, and standby-timeout transitions.
- [ ] Scene context updates must flow through `SudoAIAgent`, not through a separate demo voice service.

### 10.7 ElevenLabs Integration
- [ ] Use signed URLs from the local voice companion as the only production ElevenLabs auth path for gameplay clients.
- [ ] The ElevenLabs API key must remain server-side in the companion process and never be exposed inside Godot client code.
- [ ] `/health` must report auth and wake readiness, and `/signed-url` must mint one fresh signed URL per activation session.
- [ ] Keep the current official ElevenLabs agent WebSocket message family (`conversation_initiation_client_data`, `user_audio_chunk`, `user_transcript`, `agent_response`, `audio`, `ping`) as the canonical realtime path.

### 10.8 Validation
- [ ] Saying `"sudo"` during gameplay activates SudoAI from standby without pressing `F`.
- [ ] `F` and DualShock square still activate SudoAI if wake detection is unavailable.
- [ ] Silence timeout returns the system to standby and the next `"sudo"` reactivates it reliably.
- [ ] SudoAI never re-triggers on its own greeting or spoken response.
- [ ] Pause/menu/intro do not accidentally activate the voice AI.
- [ ] Offline / mic-denied states leave the game playable and expose a readable HUD state.
- [ ] `hero_demo` and `landing_valley` both boot with the same SudoAI standby behavior, while menu/intro remain silent.
- [ ] The local companion returns valid `/health` data with and without ElevenLabs credentials, and `/signed-url` never exposes the API key to the game client.
