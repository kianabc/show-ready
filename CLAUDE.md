# Showready

macOS SwiftUI app (Swift package, macOS 14+) that turns owner-shot real estate photos into MLS-ready images using OpenAI image models via `POST /v1/images/edits`.

## Layout
- `Sources/ShowreadyCore`: pure Swift, no AppKit. Model catalog and prices (`ImageModel.swift`), output sizing (`OutputSize.swift`), edit options (`EditOptions.swift`), prompt text and truthfulness guardrails (`PromptBuilder.swift`), cost estimate and calibration (`CostEstimator.swift`), OpenAI client (`OpenAIImageClient.swift`), spend ledger.
- `Sources/Showready`: SwiftUI app. `AppStore.swift` (state, processing queue, export), `Services/ImageTools.swift` (Core Image, Vision, mask rendering), `Services/Keychain.swift`, `Services/DemoRunner.swift` (unattended CI demo), `Views/`.
- `Tests/ShowreadyCoreTests`: unit tests for the core.

## Commands
- Tests: `swift test`
- Run from source: `swift run Showready` or open `Package.swift` in Xcode.
- Build the .app: `./scripts/build-app.sh` then `open build/Showready.app`.
- The API key lives in the Keychain (Settings in the app). An `OPENAI_API_KEY` env var is used if the Keychain is empty.

## Product rules (from the owner)
- Clean up glare, clutter, color, lens distortion (fisheye) and harsh shadows.
- Never change permanent structure, perspective, room size or the view. Power lines and neighboring houses stay.
- Optional: sky replacement (blue, clouds, golden hour, sunset), twilight, lights on, fire in fireplace, lawn.
- Show estimated cost per photo before running and actual cost after. Model and prices are user-editable.
- Keep owner-facing copy plain. Materially altered photos are flagged in `edit-log.csv` for MLS disclosure.

## Status (2026-11-05)
- Core tests pass. CI (`.github/workflows/build.yml`) builds on macOS and publishes `Showready.zip` to the `latest` release.
- `.github/workflows/demo.yml` runs the app unattended on a Mac runner: free local enhance by default; real AI edits when a pushed commit message contains `[demo-ai]` and the `OPENAI_API_KEY` repo secret exists (not set yet).
- Default model `gpt-image-2`, medium quality, 2048 px long edge (about $0.15 per photo).
- First live test (2026-11-05): a twilight edit redrew the house (moved stairs, new porch, invented windows). In response: prompts rewritten to frame twilight/golden hour/sunset as relight-only with hard structure lock-down, and a local structure check (`StructureCheck.swift`, Sobel-edge correlation) now scores every AI result against the original. Scores below 0.5 get a "structure changed" warning in the UI and a REVIEW flag in `edit-log.csv`. Calibrated on the real failure pair: repaint 0.14 vs honest relights 0.87–0.97. Note: `input_fidelity` must NOT be sent to gpt-image-2+ (400 error); only gpt-image-1.x accepts it.
- Next: re-test twilight on the owner's photos and check the warning fires/clears correctly.
- Known: ~60 Swift 6 Sendable warnings (NSImage crossing actors); harmless in Swift 5 mode.
- Interior/exterior auto-detection uses Vision classification and can be wrong; the user can switch it per photo.
- Pricing for gpt-image-2.5/2.6 has no published per-image token table; estimates are rough until calibrated from real usage.
