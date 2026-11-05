import XCTest
@testable import ShowreadyCore

final class CoreTests: XCTestCase {
    let gpt2 = ModelCatalog.defaults.first { $0.id == "gpt-image-2" }!
    let mini = ModelCatalog.defaults.first { $0.id == "gpt-image-1-mini" }!

    func testCustomSizeKeepsAspectAndRules() {
        for (w, h) in [(6000, 4000), (4032, 3024), (3024, 4032), (8000, 2000), (1000, 1000)] {
            for edge in [1024, 2048, 2560, 3840] {
                let s = OutputSizer.size(for: PixelSize(width: w, height: h), longEdge: edge, model: gpt2)
                XCTAssertEqual(s.width % 16, 0); XCTAssertEqual(s.height % 16, 0)
                XCTAssertLessThanOrEqual(s.pixels, OutputSizer.maxPixels)
                XCTAssertGreaterThanOrEqual(s.pixels, OutputSizer.minPixels)
                XCTAssertLessThanOrEqual(max(s.width, s.height), 3840)
                XCTAssertEqual(s.aspect, min(max(Double(w) / Double(h), 1/3), 3), accuracy: 0.08)
                XCTAssertLessThanOrEqual(max(s.aspect, 1 / s.aspect), 3)
            }
        }
    }

    func testFixedSizes() {
        XCTAssertEqual(OutputSizer.size(for: PixelSize(width: 6000, height: 4000), longEdge: 3840, model: mini).apiString, "1536x1024")
        XCTAssertEqual(OutputSizer.size(for: PixelSize(width: 3000, height: 4000), longEdge: 3840, model: mini).apiString, "1024x1536")
    }

    func testPublishedEstimateMatchesOpenAIExample() {
        // OpenAI lists gpt-image-2 high 1024x1024 at about $0.211 output.
        let e = CostEstimator.estimate(model: gpt2, quality: .high, inputSize: PixelSize(width: 1024, height: 1024),
                                       outputSize: PixelSize(width: 1024, height: 1024), prompt: "")
        let outputDollars = Double(e.outputTokens) * 30 / 1e6
        XCTAssertEqual(outputDollars, 0.211, accuracy: 0.001)
        XCTAssertEqual(e.basis, .published)
    }

    func testCalibrationWins() {
        var c = Calibration()
        let out = PixelSize(width: 2048, height: 1360)
        c.record(model: gpt2.id, quality: .medium,
                 usage: ImageUsage(input_tokens: 1500, output_tokens: 5000, input_tokens_details: .init(text_tokens: 500, image_tokens: 1000)),
                 outputSize: out, imageCount: 1, inputSize: PixelSize(width: 2048, height: 1365))
        let e = CostEstimator.estimate(model: gpt2, quality: .medium, inputSize: PixelSize(width: 2048, height: 1365),
                                       outputSize: out, prompt: "x", calibration: c)
        XCTAssertEqual(e.outputTokens, 5000)
        XCTAssertEqual(e.imageInputTokens, 1000)
        XCTAssertEqual(e.basis, .calibrated(1))
    }

    func testActualCost() {
        let u = ImageUsage(input_tokens: 1200, output_tokens: 10_000, input_tokens_details: .init(text_tokens: 200, image_tokens: 1000))
        let text: Double = 200 * 5 / 1e6
        let image: Double = 1000 * 8 / 1e6
        let output: Double = 10_000 * 30 / 1e6
        XCTAssertEqual(CostEstimator.actualCost(model: gpt2, usage: u), text + image + output, accuracy: 1e-9)
    }

    func testPromptContainsGuardrailsAndChoices() {
        var o = EditOptions.defaults(for: .exterior)
        o.twilight = true
        o.customInstructions = "Remove the basketball hoop"
        let p = PromptBuilder.prompt(for: o)
        XCTAssertTrue(p.contains("STRICT RULES"))
        XCTAssertTrue(p.contains("twilight"))
        XCTAssertTrue(p.contains("lighting change ONLY"))
        XCTAssertTrue(p.contains("skip that edit"))
        XCTAssertTrue(p.contains("same number of doors, windows, steps"))
        XCTAssertTrue(p.contains("soft white clouds"))
        XCTAssertTrue(p.contains("watermarks"))
        XCTAssertTrue(p.contains("basketball hoop"))
        XCTAssertFalse(p.contains("Window pull"))
        XCTAssertTrue(o.isMaterialAlteration)
    }

    func testStructureCheck() {
        let w = 64, h = 64
        func rect(_ img: inout [Float], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: Float) {
            for y in y0..<y1 { for x in x0..<x1 { img[y * w + x] = v } }
        }
        // A synthetic house: body, window, door.
        var a = [Float](repeating: 0.2, count: w * h)
        rect(&a, 8, 20, 56, 56, 0.6)
        rect(&a, 14, 28, 24, 40, 0.9)
        rect(&a, 36, 30, 44, 56, 0.35)

        // Identical image: perfect score.
        XCTAssertEqual(StructureCheck.score(a, a, width: w, height: h), 1.0, accuracy: 0.001)

        // Relight (gain and offset, like a twilight dim): structure unchanged, high score.
        let relit = a.map { $0 * 0.4 + 0.05 }
        let relitScore = StructureCheck.score(a, relit, width: w, height: h)
        XCTAssertGreaterThan(relitScore, 0.9)

        // One-pixel resampling shift: still comfortably above the warning line.
        var shifted = a
        for y in 0..<h { for x in 1..<w { shifted[y * w + x] = a[y * w + x - 1] } }
        XCTAssertGreaterThan(StructureCheck.score(a, shifted, width: w, height: h), StructureCheck.warnBelow)

        // Repaint: same kind of scene, but the house was redrawn — different
        // footprint, window and door elsewhere (like the real twilight failure).
        var b = [Float](repeating: 0.2, count: w * h)
        rect(&b, 4, 14, 48, 56, 0.6)
        rect(&b, 32, 20, 44, 34, 0.9)
        rect(&b, 10, 28, 20, 56, 0.35)
        let repaintScore = StructureCheck.score(a, b, width: w, height: h)
        XCTAssertLessThan(repaintScore, relitScore)
        XCTAssertLessThan(repaintScore, StructureCheck.warnBelow)
    }

    func testRequestAndParse() throws {
        let client = OpenAIImageClient(apiKey: "sk-test")
        let r = EditRequest(model: gpt2, prompt: "hi", image: Data([1, 2, 3]),
                            size: PixelSize(width: 1536, height: 1024), quality: .high)
        let req = client.makeRequest(r)
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        let body = String(decoding: req.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"size\"\r\n\r\n1536x1024"))
        XCTAssertFalse(body.contains("input_fidelity"))

        let json = #"{"data":[{"b64_json":"AQID"}],"usage":{"input_tokens":10,"output_tokens":20,"total_tokens":30,"input_tokens_details":{"text_tokens":4,"image_tokens":6}}}"#
        let res = try OpenAIImageClient.parse(data: Data(json.utf8), status: 200)
        XCTAssertEqual(res.images.first, Data([1, 2, 3]))
        XCTAssertEqual(res.usage?.imageInputTokens, 6)

        XCTAssertThrowsError(try OpenAIImageClient.parse(data: Data(#"{"error":{"message":"bad key"}}"#.utf8), status: 401))
    }
}
