# Changelog

All notable changes to Showready. One section per release, newest first.
Versions follow semantic versioning: patch for fixes, minor for features.

## [0.6.1] — 2026-11-05

### Fixed
- Virtual staging could redraw the room (moved walls, blocked doors). Staging is now strictly add-only: the prompt locks down the room and requires every door and walkway to stay clear, and staged results get the structure check again so a redrawn room is flagged for review.

## [0.6.0] — 2026-11-05

### Added
- Delete a single edited version (trash button in the compare view), or remove photos from the library entirely (Delete key or right-click). Originals on disk are never touched.

## [0.5.0] — 2026-11-05

### Added
- Virtual staging: furnish an empty or sparse room in one of four styles. Staged photos are flagged for MLS disclosure.

### Improved
- AI model and quality moved out of the per-photo panel into Settings — they apply to every photo. The cost section still shows which model will run.

## [0.4.0] — 2026-11-05

### Added
- Scriptable import: a staged folder (and listing) can be imported unattended at launch.

### Improved
- The app is now called Rocco Show Ready.

## [0.3.0] — 2026-11-05

### Added
- Up and down arrow keys move through the photo list.

### Improved
- A photo's first (or only) version is selected for export automatically; once more versions exist, the choice is yours again.
- "Approve" is now "Select": a clearly pressable blue button that turns green once a version is chosen.

## [0.2.0] — 2026-11-05

### Added
- The photo library now survives quitting: photos, listings, edit versions and approvals are saved and restored at the next launch. Previously every quit silently emptied the app.

## [0.1.0] — 2026-11-05

First versioned release.

### Added
- Import owner-shot photos, auto-detect interior/exterior, and enhance them locally for free or with OpenAI image models.
- Optional AI edits: sky replacement, twilight, lights on, fire in fireplace, lawn repair — relight-only, with permanent structure locked down.
- A structure check scores every AI result against the original and flags redraws for review.
- Estimated cost before each edit and actual cost after, with a spend ledger and user-editable model prices.
- Saved default edit presets per photo kind, listings to group photos, and an approval flow with one-click export of approved photos.
- An edit-log.csv recording every edit for MLS disclosure.
- Automatic update checks against GitHub releases, with verified one-click install.
