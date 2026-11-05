# Changelog

All notable changes to Showready. One section per release, newest first.
Versions follow semantic versioning: patch for fixes, minor for features.

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
