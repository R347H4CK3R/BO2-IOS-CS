# Build notes

## Verified milestone

GitHub Actions run 35485545921 on commit `a23088eb150f4516b538671cc9db18772017a55a` passed the complete bootstrap pipeline:

- source/proprietary-boundary validation: PASS
- converter unit tests: PASS
- iOS Simulator build: PASS
- actual iPhone 16 Plus Simulator AUTOTEST: PASS
- unsigned generic ARM64 iOS device build: PASS
- IPA packaging and structural validation: PASS

The simulator AUTOTEST ran the project-original validation arena for about 10 seconds with four bots, collision initialized, touch HUD initialized, simulated weapon activity, and objective ticks. Simulator performance is not treated as physical-device performance.

The device IPA is unsigned and was structurally validated only; it was not executed in Simulator and has not yet been installed on a physical iPhone.

## Asset boundary

User-owned BO2 PS3 data remains external in Google Drive. No proprietary PS3 bytes are committed or used by GitHub Actions. CI uses only project-original synthetic fixtures.

## Remaining major work

The current executable runtime is a temporary native Swift/SceneKit bootstrap. The project is not complete until an appropriate open-source engine/runtime is integrated and the real PS3 asset converter can produce usable map, texture, model, animation, and audio data from the user's local source files.
