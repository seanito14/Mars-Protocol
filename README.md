# Mars Protocol
### Voice-Activated AI Simulation on Mars

A high-fidelity, open-world Mars exploration simulation built in **Godot 4.6.1**, combining **agentic AI**, **real-time voice interaction**, and **large-scale terrain systems** into a cinematic, playable experience.

The current Jezero landing build uses **real Mars terrain and imagery data** derived from public USGS Astrogeology / Mars 2020 map products, then converted into runtime assets for Godot.

---

## 💡 Core Vision

Mars Protocol is not just a game — it is a **voice-first AI operating system for simulation environments**, where players interact with intelligent agents, manage a Mars colony, and experience dynamic, reactive worlds.

---

## 💰 Pricing & Experience Tiers

The experience is structured as a tiered AI-powered simulation:

### 🧍 Lone Survivor (Free)
The complete core survival experience.

- Full scavenge-and-survive gameplay loop  
- Permadeath cloning system  
- Rover vehicle build & traversal  
- Standard robotic AI hazard alerts  

---

### 🧠 Sudo Activated ($4.99/month)
Unlock the living AI companion.

- Live conversational AI (Push-to-Talk)  
- Predictive dust storm telemetry  
- Thermal heat-map overlays  
- Base automation hub with drones  

---

### 🎬 Absolute Cinema ($19.99/month)
Full control and modification of AI systems.

- “Sudo Unchained” custom LLM personalities  
- Deep voice cloning for AI agents  
- Chat-to-voice spatial audio  
- Twitch & YouTube viewer interaction layer  

---

## 🛠 Hardware & Network Setup

### 🖥 Command Center (Mac Mini - Headless)
- Main compute + game engine host  
- Hotspot IP: `172.20.10.10`  
- Virtual displays via BetterDisplay  

### 💻 Primary View (ThinkPad - Arch Linux)
- Development console via VNC  
- Resolution: 1280x720 (native 16:9)  

### 📱 Tactical Map (iPad 10th Gen)
- Secondary display (low latency)  
- USB-C Ethernet direct link  
- IP: `169.254.10.216`  

---

## 🧠 System Architecture

### 🎮 Engine
- Godot 4.6.1  
- Jolt Physics (GDExtension)  

### 🤖 AI Layer
- Agent-based NPC architecture  
- Voice integration via ElevenLabs  
- Real-time conversational interface  

### 🌍 World Systems
- Large-scale terrain rendering  
- Atmospheric scattering + volumetric fog  
- Multi-agent simulation environment  

---

## 🛰 Real Mars Data

The Jezero landing zone in this branch is no longer just procedural terrain. The runtime pack in `assets/mars/jezero/` is generated from public Mars datasets with `tools/mars_data/build_jezero_patch.py`, then loaded in-game through the raster-backed landing scene.

### Current terrain source stack

- **USGS Astrogeology Science Center — Mars 2020 Terrain Relative Navigation HiRISE DTM Mosaic**  
  1 m/pixel elevation model used as the high-resolution Jezero terrain reference.  
  Product page: [USGS Astropedia](https://astrogeology.usgs.gov/search/map/Mars/Mars2020/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40)  
  DOI: [10.5066/P9REJ9JN](https://doi.org/10.5066/P9REJ9JN)

- **USGS Astrogeology Science Center — Mars 2020 Terrain Relative Navigation HiRISE Orthorectified Image Mosaic**  
  0.25 m/pixel orthorectified image mosaic used as the macro surface/albedo reference for the Jezero patch.  
  Product page: [USGS Astropedia](https://astrogeology.usgs.gov/search/map/mars_2020_terrain_relative_navigation_hirise_orthorectified_image_mosaic)  
  DOI: [10.5066/P9QJDP48](https://doi.org/10.5066/P9QJDP48)

- **USGS Astrogeology Science Center — Mars 2020 Science Investigation CTX DEM Mosaic**  
  20 m/pixel contextual DEM covering Jezero crater, used as the broader regional topographic reference for the current terrain workflow.  
  Product page: [USGS Astropedia](https://astrogeology.usgs.gov/search/map/mars_2020_science_investigation_ctx_dem_mosaic)  
  Referenced DOI on product page: [10.5066/P906QQT8](https://doi.org/10.5066/P906QQT8)

### Citation / attribution references

- Fergason, R. L., Hare, T. M., Mayer, D. P., Galuszka, D. M., Redding, B. L., Smith, E. D., Shinaman, J. R., Cheng, Y., and Otero, R. E. (2020). *Mars 2020 Terrain Relative Navigation Flight Product Generation: Digital Terrain Model and Orthorectified Image Mosaics.*  
  Abstract: [LPSC 2020 paper](https://www.hou.usra.edu/meetings/lpsc2020/pdf/2020.pdf)

- McEwen, A. S. et al. (2007). *Mars Reconnaissance Orbiter's High Resolution Imaging Science Experiment (HiRISE).*  
  DOI: [10.1029/2005JE002605](https://doi.org/10.1029/2005JE002605)

- Malin, M. C. et al. (2007). *Context Camera Investigation on board the Mars Reconnaissance Orbiter.*  
  DOI: [10.1029/2006JE002808](https://doi.org/10.1029/2006JE002808)

These source products are published by the **USGS Astrogeology Science Center** and are linked from their official Astropedia catalog pages above. When reusing the upstream data, cite the authors and source pages listed with each product.

---

## 📅 Development Roadmap

### ✅ Phase 1–2: Infrastructure & Visuals (Completed)
- High-density terrain (1024x1024 mesh)  
- Slope-aware rock/dust shaders  
- Physical atmosphere + volumetric fog  
- PS5 DualSense controller support  
- Tactical HUD ("Glass Cockpit")  

---

### 🚧 Phase 3: Agentic Intelligence (Current)

- XOSS Rover Protocol (EVA state machine)  
- ElevenLabs voice integration (CLI + runtime)  

#### In Progress:
- NPCs with distinct personalities  
- Companion AI system (“Sudo”)  
- Voice-driven interactions across all agents  

---

## 🌍 Open World Engineering Objectives

### 1. World Architecture
- Origin shifting to prevent physics jitter (>2km)  
- Seamless chunk streaming (`ResourceLoader.load_threaded_request`)  

### 2. Terrain System
- Terrain3D + GPU clipmaps (target: 65km × 65km)  
- Tri-planar micro-detail shaders  

### 3. Optimization
- HLOD (hierarchical LOD)  
- Occlusion culling via baked occluders  
- Physics scaling with Jolt  

### 4. Agent Scaling
- NavigationServer3D for 100+ concurrent agents  
- State-machine driven behaviors  
- AI scheduling + task orchestration  

---

## 🎯 Key Differentiators

- 🎤 **Voice-first gameplay** (not UI-first)  
- 🧠 **Persistent AI agents with personality**  
- 🌍 **Large-scale realistic Mars terrain**  
- 🎬 **Cinematic + streamable interaction layer**  
- ⚙️ **Hybrid simulation + AI operating system**  

---

## 🔮 Future Direction

- Fully autonomous colony simulation  
- Multi-user cooperative command systems  
- AI-driven narrative generation  
- Integration with real-world telemetry + datasets  

---

## 🧪 Status

**Actively in development (Hackathon + Prototype Stage)**  
Core systems operational, AI layer expanding.

---

## 🤝 Contributing

Currently focused on rapid prototyping.  
Contributions will open post-core milestone.

---

## 🛰 Final Note

Mars Protocol is designed to explore the boundary between:

> **Game × Simulation × AI Operating System**

Building toward a future where worlds are not just rendered —  
they are **alive, responsive, and conversational**.
