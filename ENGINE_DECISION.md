# Engine decision

## Selected open-source engine baseline: Xash3D FWGS

The final runtime baseline is **Xash3D FWGS**, pinned to commit `4857b389e6ba32ddaa68582aedcbc950c138f46a`, with SDL pinned to `b90ac95029d801c5abc59472ba8e2200dff31e1e`.

Selection reasons:

- native iOS build path exists and can be exercised from GitHub Actions;
- ARM64-oriented C/C++ runtime suitable for a standalone FPS;
- SDL input/window/controller layer is compatible with the project's touch/controller goals;
- BSP-style world/runtime architecture is closer to the requested tactical FPS than the temporary SceneKit bootstrap;
- the engine does not require Steam authentication or Valve commercial asset folders when used with original/project-generated game data;
- our PS3 converter remains engine-neutral through `GameDataIntermediate`.

## Verified status

GitHub Actions run #27 successfully compiled the pinned Xash3D FWGS dependency stack for an ARM64 iOS Simulator target, including a pinned SDL2 iOS framework.

This proves the open-source engine toolchain compiles for Simulator. It does **not** yet mean the shipping BO2IOSCS app is running its gameplay loop inside Xash3D. Runtime integration, project-original game DLL/game logic, converted map loading, and touch-HUD bridging remain separate milestones.

## Bootstrap runtime

The original Swift/SceneKit runtime remains temporarily in the repository as a deterministic integration test harness. It currently provides:

- project-original validation arena;
- collision and player spawn;
- four autonomous test bots;
- weapon activity;
- touch HUD initialization;
- round/objective simulation;
- iPhone 16 Plus Simulator AUTOTEST;
- unsigned ARM64 IPA packaging validation.

It will remain the regression harness until equivalent Xash-backed startup/map/player/bot checks are passing, then it can be retired or reduced to tooling/debug UI.

## Asset boundary

Xash3D FWGS is built from open-source code. Proprietary PS3 assets are never committed or required by CI. The converter consumes only user-provided local data and emits ignored/generated intermediate/runtime assets.
