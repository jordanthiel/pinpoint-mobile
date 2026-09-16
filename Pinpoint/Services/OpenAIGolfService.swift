import Foundation
#if !PINPOINT_STORE_SMOKE
import Supabase
#endif

struct OpenAIShotFields: Decodable {
    var evidence: String
    var club: String?
    var lie: String?
    var contact: String?
    var shape: String?
    var distanceYards: Double?
    var leftFeet: Double?
    var outcome: String?
    var breakDirection: String?
    var note: String?
    var finish: String?
    var lateralMiss: String?
    var depthMiss: String?
    var puttMissSide: String?
    var holed: Bool?
    var carryYards: Double?
    var startingDistanceFeet: Double?
    var quality: String?
}
struct OpenAIRecap: Decodable {
    var shots: [OpenAIShotFields]
    var puttsMentioned: Int?
    var scoreCall: String?
}

struct OpenAIRoundRecap: Decodable {
    var holes: [OpenAIHoleRecap]
    var warnings: [String]
}
struct OpenAIHoleRecap: Decodable {
    var holeNumber: Int
    var evidence: String
    var score: Int?
    var putts: Int?
    var penalties: Int?
    var fairwayHit: Bool?
    var scoreCall: String?
    var shots: [OpenAIShotFields]
    var notes: String
    var warnings: [String]
}

enum GolfAIError: LocalizedError {
    case notConfigured, signIn, server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "OpenAI isn't configured yet. You can still type and review a recap locally."
        case .signIn: return "Sign in to Pinpoint to use OpenAI. Your recording stays on this device until transcription succeeds."
        case .server(let message): return message
        case .invalidResponse: return "The AI response could not be verified. Please retry or use local parsing."
        }
    }
}

/// Provider credentials live only in the Edge Function. Requests use the golfer's session.
enum OpenAIGolfService {
    private struct TextResponse: Decodable { var text: String }
    private struct ServerError: Decodable { var error: String }

    private static func request() async throws -> URLRequest {
        #if PINPOINT_STORE_SMOKE
        throw GolfAIError.notConfigured
        #else
        guard let url = PinpointSupabase.configURL?.appendingPathComponent("functions/v1/golf-ai"),
              let client = PinpointSupabase.client else { throw GolfAIError.notConfigured }
        let session: Session
        do { session = try await client.auth.session } catch { throw GolfAIError.signIn }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(PinpointSupabase.configKey, forHTTPHeaderField: "apikey")
        return request
        #endif
    }

    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GolfAIError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 { throw GolfAIError.signIn }
            if let error = try? JSONDecoder().decode(ServerError.self, from: data) { throw GolfAIError.server(error.error) }
            throw GolfAIError.server("OpenAI is unavailable (\(response.statusCode)). Please try again later.")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GolfAIError.invalidResponse }
    }

    static func recap(_ transcript: String) async throws -> OpenAIRecap {
        var request = try await request()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operation": "recap", "transcript": transcript])
        return try await send(request, as: OpenAIRecap.self)
    }

    static func roundRecap(_ transcript: String, round: GolfRound, currentHole: Int) async throws -> OpenAIRoundRecap {
        var request = try await request()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operation": "round_recap", "transcript": transcript,
            "context": ["currentHole": currentHole, "holes": round.holesSnapshot.map { ["number": $0.number, "par": $0.par] }]
        ])
        return try await send(request, as: OpenAIRoundRecap.self)
    }

    static func coach(question: String, evidence: String, history: String) async throws -> String {
        var request = try await request()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operation": "coach", "question": String(question.prefix(2000)), "evidence": String(evidence.prefix(20000)), "history": String(history.suffix(4000))])
        return try await send(request, as: TextResponse.self).text
    }

    static func transcribe(file: URL) async throws -> String {
        var request = try await request()
        let audio = try Data(contentsOf: file)
        guard !audio.isEmpty, audio.count <= 8_000_000 else { throw GolfAIError.server("Recording is too large. Keep recaps under ten minutes.") }
        let boundary = "Pinpoint-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recap.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8)
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await send(request, as: TextResponse.self).text
    }
}
