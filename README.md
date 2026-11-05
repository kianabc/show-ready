# Listing Polish

A Mac app that turns owner-shot or amateur real estate photos into clean, MLS-ready images using OpenAI's GPT Image models.

## What it does

- **Import** photos or whole folders (JPEG, HEIC, PNG, TIFF, camera RAW) by drag and drop or ⌘O. Originals are never changed.
- **Auto-detects interior vs exterior** on the Mac and picks sensible default edits.
- **Every photo:** color, exposure and white balance, lens distortion (fisheye, barrel) fixes, shadow softening. Optional vertical-line straightening.
- **Interiors:** light or thorough declutter, personal-photo removal, window glare removal, window pull, photographer removed from mirrors, lights on, fire in the fireplace, TV screen black or scenic.
- **Exteriors:** sky cleanup or replacement (clear blue, soft clouds, golden hour, sunset), virtual twilight, greener lawn, removal of cars, bins and yard signs.
- **Mark objects:** paint over anything specific you want removed. The app sends it as a mask.
- **Truthfulness guardrails** are added to every request: same framing and perspective, no changes to walls, windows, fixtures, room size, power lines or views.
- **Before/after slider**, multiple versions per photo, and a free on-device "Quick enhance" that costs nothing.
- **Cost:** a per-photo and per-batch estimate before you run, actual cost from OpenAI's returned token usage after, and a spending history. Estimates learn from your real usage.
- **Models and prices** are editable in Settings, so you can add new OpenAI models or update prices without a new build.
- **Export** to MLS sizes as JPEG with GPS and camera metadata stripped, plus an `edit-log.csv` that flags which photos were materially altered, for MLS disclosure.

## Run it

Requires macOS 14 or later and Xcode 15 or later (or the Swift command line tools).

Open in Xcode:

```bash
open Package.swift
```

Then pick the **ListingPolish** scheme and press Run.

Or build a double-clickable app into `build/`:

```bash
./scripts/build-app.sh
```

Then add your OpenAI API key in **Listing Polish → Settings → API Key**. It is stored in the macOS Keychain.

## Costs

OpenAI bills image edits by tokens: the prompt text, the uploaded photo, and the generated image. Output size and quality drive most of the cost. Prices were taken from OpenAI's pricing page on 2026-11-05 and are editable in Settings.

| Model | Image in / 1M | Image out / 1M | Notes |
| --- | --- | --- | --- |
| gpt-image-2 (default) | $8 | $30 | High at 1024×1024 is about $0.21 |
| gpt-image-2.5 / 2.6 sunburst, flare | $8 | $30 | Up to 3840 px, more quality levels |
| gpt-image-1.5 | $8 | $32 | Max 1536 px |
| gpt-image-1-mini | $2.50 | $8 | Cheapest, max 1536 px |

For the newest models OpenAI has not published per-image token counts, so the first estimate is a rough guess. After your first few edits the app uses your real usage.

## Project layout

- `Sources/ListingPolishCore` holds the model catalog, pricing math, prompt builder and OpenAI client. It is plain Swift with unit tests.
- `Sources/ListingPolish` holds the SwiftUI app, image processing (Core Image, Vision) and Keychain storage.

Run the tests:

```bash
swift test
```

## Notes

- OpenAI may require **Organization Verification** before GPT Image models work. A 403 error usually means that step is missing.
- AI edits can occasionally change details. Always compare before and after, especially windows, fixtures and views.
- Sky replacement, twilight, virtual fire, lights on and lawn enhancement count as material changes in many MLSs. Check your MLS rules and use the edit log for disclosure.
