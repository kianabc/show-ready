import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct EditRequest: Sendable {
    public var model: ImageModel
    public var prompt: String
    public var image: Data            // JPEG or PNG bytes
    public var imageMime: String      // "image/jpeg" or "image/png"
    public var mask: Data?            // PNG with alpha, same size as image
    public var size: PixelSize
    public var quality: ImageQuality
    public var variations: Int

    public init(model: ImageModel, prompt: String, image: Data, imageMime: String = "image/jpeg",
                mask: Data? = nil, size: PixelSize, quality: ImageQuality, variations: Int = 1) {
        self.model = model; self.prompt = prompt; self.image = image; self.imageMime = imageMime
        self.mask = mask; self.size = size; self.quality = quality; self.variations = variations
    }
}

public struct EditResult: Sendable {
    public var images: [Data]
    public var usage: ImageUsage?
}

public enum OpenAIError: LocalizedError, Sendable {
    case missingKey
    case http(status: Int, message: String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings."
        case .http(let status, let message):
            switch status {
            case 401: return "OpenAI rejected the API key (401). Check it in Settings. \(message)"
            case 403: return "Access denied (403). Your OpenAI organization may need verification for image models. \(message)"
            case 429: return "Rate limited or out of credit (429). \(message)"
            default: return "OpenAI error \(status): \(message)"
            }
        case .badResponse(let s): return "Unexpected response from OpenAI: \(s)"
        }
    }

    var isRetryable: Bool {
        if case .http(let s, let m) = self {
            // A 429 for exhausted quota will not fix itself; a rate limit will.
            if s == 429 { return !m.lowercased().contains("quota") }
            return s >= 500
        }
        return false
    }
}

struct MultipartForm {
    let boundary = "Boundary-\(UUID().uuidString)"
    private(set) var body = Data()

    mutating func add(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mime: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finished() -> Data {
        var d = body
        d.append("--\(boundary)--\r\n")
        return d
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}

public struct OpenAIImageClient: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                session: URLSession = .shared) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.session = session
    }

    public func makeRequest(_ r: EditRequest) -> URLRequest {
        var form = MultipartForm()
        form.add("model", r.model.id)
        form.add("prompt", r.prompt)
        let ext = r.imageMime == "image/png" ? "png" : "jpg"
        form.addFile("image", filename: "photo.\(ext)", mime: r.imageMime, data: r.image)
        if let mask = r.mask {
            form.addFile("mask", filename: "mask.png", mime: "image/png", data: mask)
        }
        form.add("size", r.size.apiString)
        form.add("quality", r.quality.rawValue)
        form.add("n", String(max(1, r.variations)))
        form.add("output_format", "jpeg")
        form.add("output_compression", "95")
        if r.model.sendsInputFidelity { form.add("input_fidelity", "high") }

        var req = URLRequest(url: baseURL.appendingPathComponent("images/edits"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finished()
        return req
    }

    struct Response: Decodable {
        struct Item: Decodable { var b64_json: String? }
        var data: [Item]?
        var usage: ImageUsage?
    }

    struct ErrorEnvelope: Decodable {
        struct Inner: Decodable { var message: String? }
        var error: Inner?
    }

    public static func parse(data: Data, status: Int) throws -> EditResult {
        guard (200..<300).contains(status) else {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw OpenAIError.http(status: status, message: msg)
        }
        let r: Response
        do { r = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw OpenAIError.badResponse(error.localizedDescription) }
        let images = (r.data ?? []).compactMap { $0.b64_json }.compactMap { Data(base64Encoded: $0) }
        guard !images.isEmpty else { throw OpenAIError.badResponse("no image in response") }
        return EditResult(images: images, usage: r.usage)
    }

    /// Sends the edit, retrying rate limits and server errors with backoff.
    public func edit(_ r: EditRequest, maxAttempts: Int = 4) async throws -> EditResult {
        guard !apiKey.isEmpty else { throw OpenAIError.missingKey }
        let req = makeRequest(r)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, resp) = try await session.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return try Self.parse(data: data, status: status)
            } catch let e as OpenAIError where e.isRetryable && attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            } catch let e as URLError where attempt < maxAttempts && e.code != .cancelled {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            }
        }
    }

    /// Cheap call to confirm the key works.
    public func testKey() async throws {
        guard !apiKey.isEmpty else { throw OpenAIError.missingKey }
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message ?? ""
            throw OpenAIError.http(status: status, message: msg)
        }
    }
}
