# Project Mars High Fidelity - Development Objectives
Game landing page link: https://the-mars-protocol.lovable.app
#IMPORTANT, always reference the game website link https://the-mars-protocol.lovable.app for features, pricing and any crucial information about the game. 
## 🚀 Vision
To create a high-fidelity, open-world 3D simulation of Mars specifically optimized for mobile (iOS/iPad), featuring immersive exploration and advanced interface mechanics.

## 🎯 Key Objectives

### 1. Voice-Controlled Command System (Priority)
- **Voice-to-Action:** Implement a robust bridge between local speech-to-text and the Godot `CommandServer`.
- **Natural Language Processing:** Allow "Commander" style inputs (e.g., "Deploy Rover at coordinates 50, -20", "Scan Gale Crater", "Return to Base").
- **Multimodal Interaction:** Combine touch gestures for movement with voice for complex base-management and deployment tasks.

### 2. High-Fidelity Mars Environment
- **Gale Crater Simulation:** Utilize 16-bit heightmaps and custom shaders to replicate actual NASA terrain data.
- **Mars Physics:** Calibrate gravity (~0.375g) and atmospheric effects (dust storms, lighting) for realistic immersion.
- **Dynamic HUD:** A minimal, high-resolution HUD (2360x1640) designed for iPad Pro displays.

### 3. Mobile Optimization (iOS/iPad)
- **Performance:** Target 60/120 FPS on Apple Silicon (A-series/M-series chips) by optimizing the rendering pipeline.
- **Input:** Implement sophisticated touch-screen virtual joysticks alongside Gamepad (Xbox/PS) support.
- **Thermal Management:** Ensure the "Forward Plus" renderer is balanced with "Mobile" compatibility for long-session stability.

### 4. Gameplay Mechanics
- **Rover Operations:** Switch between first-person exploration and third-person rover piloting.
- **Resource Management:** Terraforming progression system (Atmosphere, Temperature, Water).
- **Mission System:** Procedurally generated exploration missions based on real Martian geological features.

---
*Last Updated: March 21, 2026*

### 6. MVP Checklist & Monetization (Lauri's Final Update)
- **Core Gameplay (The "Supercell" Track):**
    - Environment: Small, atmospheric crater focus.
    - Resources: Oxygen (15 mins to deplete), Suit Power (30 mins), and Temperature Resistance (50 mins) bars (constantly ticking down).
	- Scavenge Mechanic: Collect 5-10 glowing 3D cubes (ship debris/samples) using 'E' key.
    - Death/Clone State: Fade to black on 0 Oxygen with "CLONE ITERATION FAILED" message.
- **The Jarvis Integration (The "ElevenLabs" Track):**
    - Smart Triggers: Trigger ElevenLabs voice alerts when HUD bars drop below 25%.
	- Premium Tease: 'T' for Telemetry triggers a "Scanning for high-tier debris..." voice and RevenueCat paywall.
- **The Paywall (The "RevenueCat" Track):**
    - UI: 2D pop-up menu with 3 tiers (Free: bash, Pro: $4.99, Mod: $19.99).
    - SDK: Integrate RevenueCat sandbox transaction logic.
- **The Meta-Loop (The "Player Joy" Track):**
    - Basecamp Menu: 2D terminal at spawn point for upgrades.
    - Upgrades: Spend glowing cubes to increase Oxygen capacity or Suit durability.
