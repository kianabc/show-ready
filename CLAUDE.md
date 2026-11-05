# Showready (product name: "Rocco Show Ready")

macOS SwiftUI app (Swift package, macOS 14+) that turns owner-shot real estate photos into MLS-ready images using OpenAI image models via `POST /v1/images/edits`.

The user-facing name is **Rocco Show Ready** (CFBundleName/DisplayName, window title, updater copy, download page). The bundle filename (`Showready.app`), executable, bundle id (`com.showready.app`), repo, and code names stay `Showready` — the self-updater verifies and replaces `/Applications/Showready.app` by that name, and macOS permission grants are keyed to the bundle id, so renaming those would orphan installs.

## Layout
- `Sources/ShowreadyCore`: pure Swift, no AppKit. Model catalog and prices (`ImageModel.swift`), output sizing (`OutputSize.swift`), edit options (`EditOptions.swift`), prompt text and truthfulness guardrails (`PromptBuilder.swift`), cost estimate and calibration (`CostEstimator.swift`), OpenAI client (`OpenAIImageClient.swift`), spend ledger.
- `Sources/Showready`: SwiftUI app. `AppStore.swift` (state, processing queue, export), `Services/ImageTools.swift` (Core Image, Vision, mask rendering), `Services/Keychain.swift`, `Services/DemoRunner.swift` (unattended CI demo), `Views/`.
- `Tests/ShowreadyCoreTests`: unit tests for the core.

## Commands
- Tests: `swift test`
- Run from source: `swift run Showready` or open `Package.swift` in Xcode.
- Build the .app: `./scripts/build-app.sh` then `open build/Showready.app`. Signs with the Developer ID when present, ad-hoc otherwise (CI).
- Release: `./scripts/release.sh <version>` (needs a `## [version]` CHANGELOG.md entry; tags), then `git push && git push --tags`, `./scripts/notarize.sh` (builds, notarises, staples a DMG into build/dist), then `gh release create v<version> <dmg> --title "v<version>" --notes "..."`. Release notes are short markdown bullets — they render inside the in-app update alert.
- The API key lives in the Keychain (Settings in the app). An `OPENAI_API_KEY` env var is used if the Keychain is empty.
- Versioning/updates: `VERSION` is the single source of truth (semver; patch for fixes, minor for features); `CHANGELOG.md` has one section per release. The pipeline is ported from Murmur — see `~/code/murmur/docs/SELF-UPDATE.md` for the full design. The app checks GitHub releases daily/weekly (`UpdateChecker`/`UpdatePreference` in ShowreadyCore), and one-click installs after verifying signature, Team ID 7CMPG6N65Y, notarisation, and no downgrade (`Updater`/`UpdateController` in the app, offered via an alert; also in Settings → Updates). The notarytool keychain profile is named "murmur" (account-level, shared across apps). Download page: `docs/index.html` on GitHub Pages.

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
- Workflow features (2026-11-05): saved default edit presets per photo kind (persisted in AppSettings; "Save as my default" / "Apply to every X photo" in the edit panel), listings (sidebar picker chooses where imports go, sections group photos, exports split into one subfolder per listing), and approval (Approve button / A key on the chosen version, cleared when the version changes; "Save Approved" in the toolbar exports all approved photos; edit-log.csv gained an `approved` column). Import dialog deadlock fixed (NSOpenPanel must be created outside SwiftUI's action dispatch); import and quick-enhance concurrency capped.
- Releases/updates (2026-11-05): v0.1.0 cut with the Murmur-style pipeline (see Commands). The listing picker now filters the library to the chosen listing ("All photos" shows every section); it previously only chose where imports went, which read as a bug.
- Library persistence + recovery (2026-11-05): the library snapshots to `Application Support/Showready/library.json`. Before persistence existed the library was lost on quit; it was rebuilt by importing the originals (local copy in `~/Pictures/Rocco Show Ready/Photos/Originals`, Finder-copied from Google Drive because TCC silently blocks non-user-initiated reads of `~/Library/CloudStorage` — both for shells and for the app itself) and merging the orphaned AI results back in by matching spend-ledger timestamps to Results/ file birth times. Unattended import: write `pendingImportDir`/`pendingImportListing` defaults (or SHOWREADY_IMPORT_DIR/_LISTING env) and launch; one-shot, cleared on read. Import is non-recursive — point it at the folder that directly contains the images.
- Known: ~60 Swift 6 Sendable warnings (NSImage crossing actors); harmless in Swift 5 mode.
- Interior/exterior auto-detection uses Vision classification and can be wrong; the user can switch it per photo.
- Pricing for gpt-image-2.5/2.6 has no published per-image token table; estimates are rough until calibrated from real usage.
