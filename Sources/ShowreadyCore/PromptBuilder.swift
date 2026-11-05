import Foundation

/// Turns EditOptions into one clear instruction for the image model.
/// The guardrails section is always included: it is what keeps the edit
/// honest for a real estate listing.
public enum PromptBuilder {
    public static let guardrails = """
    STRICT RULES (this is a real estate listing photo and must stay truthful):
    - This is a retouch of the photograph provided, NOT a new picture. The result must be the same photo of the same property: flipping between the original and the edit, every edge of the building and landscaping must line up exactly.
    - Keep the exact same camera position, framing, field of view, crop and aspect ratio.
    - Do not change the architecture or anything permanent: walls, ceilings, floors, windows, doors, trim, cabinets, countertops, built-ins, fixtures, appliances, stairs, fireplaces, roof, siding, landscaping layout, fences, driveways, utility lines and the view.
    - The building must match the original exactly: the same number of doors, windows, steps, porch posts and railings, in the same positions, sizes and shapes. Do not move or redesign stairs, walkways, porches or planting beds. House and unit numbers stay exactly as photographed.
    - Do not make rooms or the lot look larger or smaller. Do not move, resize, add or remove walls, windows or doors.
    - If a requested edit cannot be done without breaking these rules, skip that edit and leave that part of the photo unchanged.
    - Do not add furniture, decor or objects unless explicitly asked below.
    - Keep materials, colors and finishes of permanent surfaces true to life. Do not hide damage or defects.
    - The result must look like a real, natural photograph taken by a professional real estate photographer. No illustration, no HDR halos, no oversaturation, no visible artifacts.
    - Keep fine detail sharp. Text on objects that remain should stay legible and unchanged.
    """

    public static func prompt(for o: EditOptions, hasMask: Bool = false) -> String {
        var lines: [String] = []
        lines.append("Edit this \(o.kind == .interior ? "interior" : "exterior") real estate photo so it looks professionally photographed and edited for an MLS listing.")
        lines.append("This is a retouching job on the exact photograph provided, never a redesign: the same property, from the same angle, with every permanent feature in the same place. Change only what the edits below ask for.")
        lines.append("")
        lines.append("EDITS TO MAKE:")

        if o.colorAndExposure {
            let whites = o.kind == .interior ? "white walls and ceilings should be clean neutral white" : "white trim and siding should be clean neutral white"
            lines.append("- Professional color and exposure: balanced bright exposure, recover blown highlights and dark shadows, neutral white balance (\(whites), no yellow or blue cast), natural contrast, light noise reduction and gentle sharpening.")
        }
        if o.lensCorrection {
            lines.append("- Correct lens problems only: remove fisheye and barrel or pincushion distortion so straight lines are straight, remove vignetting and chromatic aberration. Do not widen or narrow the view.")
        }
        if o.straightenVerticals {
            lines.append("- Make vertical lines (wall corners, door frames, window edges) perfectly vertical and level the horizon, the way a professional uses a tilt-shift or vertical correction. Do not otherwise change the perspective.")
        } else {
            lines.append("- Keep the original perspective. Only level a slightly tilted horizon if needed.")
        }
        if o.removeHarshShadows {
            lines.append("- Soften harsh, distracting shadows such as camera flash shadows and the photographer's shadow. Keep the natural shading that shows the shape of the \(o.kind == .interior ? "room" : "house and landscaping").")
        }

        switch o.kind {
        case .interior:
            switch o.declutter {
            case .none: break
            case .light:
                lines.append("- Light declutter: remove small loose items that make the space look messy, such as cords and cables, papers, mail, toiletries, dish racks, sponges, small countertop clutter, fridge magnets and papers, shoes, laundry, toys, pet bowls and beds, trash bins and bags. Keep all furniture, rugs, lamps, artwork and decor.")
            case .thorough:
                lines.append("- Thorough declutter: remove all personal and loose items (everything listed for a light declutter plus countertop appliances, bottles, clothing, bedding piles, bathroom products, and items on shelves and tables). Keep furniture, rugs, lamps and simple decor. Fill revealed areas with the matching surface behind them.")
            }
            if o.removePersonalPhotos {
                lines.append("- Remove or replace personal and identifying items: family photos become neutral artwork, and remove names, documents, calendars, diplomas, and religious or political items.")
            }
            if o.removeWindowGlare {
                lines.append("- Remove glare and hot spots on windows, glass, mirrors and glossy surfaces.")
            }
            if o.windowPull {
                lines.append("- Window pull: balance the exposure so the real outdoor view through the windows is visible and natural, not blown out white. Do not invent a different view.")
            }
            if o.removeReflections {
                lines.append("- Remove the photographer, camera, tripod and flash from mirrors and reflective surfaces.")
            }
            if o.lightsOn {
                lines.append("- Turn on the existing light fixtures (ceiling lights, pendants, lamps, under-cabinet lights) with a warm, realistic glow. Do not add new fixtures.")
            }
            if o.fireInFireplace {
                lines.append("- Add a realistic, modest, warm fire inside the existing fireplace firebox only.")
            }
            switch o.tvScreen {
            case .leave: break
            case .black: lines.append("- Make any TV or monitor screen a clean, glare-free black.")
            case .scenic: lines.append("- Put a calm, neutral landscape image on any TV screen, with no text or logos.")
            }
        case .exterior:
            switch o.sky {
            case .keep:
                lines.append("- Clean up the existing sky: remove haze, dust and color casts. Keep its general look.")
            case .cleanBlue:
                lines.append("- Replace a dull, white or gray sky with a clear, natural blue sky. Blend cleanly around the roofline, trees and wires with no halos.")
            case .blueWithClouds:
                lines.append("- Replace a dull, white or gray sky with a natural blue sky with a few soft white clouds. Blend cleanly around the roofline, trees and wires with no halos.")
            case .goldenHour:
                lines.append("- Relight the scene as late afternoon golden hour: warm, soft sunlight and a soft blue-to-warm sky. This changes light and sky only, nothing else. Keep it natural.")
            case .sunset:
                lines.append("- Replace the sky with a natural, tasteful sunset (soft orange, pink and blue tones) and match the light on the house to it. This changes light and sky only, nothing else. Do not overdo the colors.")
            }
            if o.twilight {
                lines.append("- Relight this exact photo as a professional twilight (dusk) shot: deepen the sky to early-evening blue with a soft glow at the horizon, make the existing windows glow with warm interior light, turn on existing exterior and landscape fixtures, and dim the overall exposure naturally. This is a lighting change ONLY: every brick, window, door, stair, railing, path, plant and house number stays exactly where it is in the original, at the same size and shape. Do not redraw, simplify or tidy any part of the house or yard.")
            }
            if o.greenLawn {
                lines.append("- Make existing lawn areas look healthy and evenly green and fill small bare patches. Do not add lawn where there is none, and do not change planting beds, trees or hardscape.")
            }
            if o.removeCarsAndBins {
                lines.append("- Remove temporary items: parked cars in the driveway or street in front, trash and recycling bins, hoses, toys, tools, and yard debris. Fill with the matching driveway, lawn or surface behind them.")
            }
            if o.removeSigns {
                lines.append("- Remove temporary signs (yard signs, for-sale signs, lockbox signs). Do not remove house numbers.")
            }
            lines.append("- Keep power lines, poles, neighboring houses, and street features. They are permanent and must not be removed.")
        }

        if hasMask {
            lines.append("- Remove the objects inside the transparent masked area and fill it with what would naturally be behind them, matching surrounding surfaces, lighting and texture exactly.")
        }

        let custom = o.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append("")
            lines.append("ADDITIONAL INSTRUCTIONS FROM THE AGENT:")
            lines.append(custom)
        }

        lines.append("")
        lines.append(guardrails)
        return lines.joined(separator: "\n")
    }
}
