import Foundation

/// Calls Anthropic's Messages API with structured-JSON output.
struct AnthropicClient: CloudLLMClient {
    var session: URLSession = .shared

    /// Builds the POST request. Pure (no I/O) so it can be unit-checked.
    static func makeRequest(system: String, user: String, apiKey: String, model: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["format": ["type": "json_schema", "schema": AnalysisSchema.jsonSchema]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extracts the assistant's structured-JSON text from a response body.
    /// Throws `.refusal` on `stop_reason == "refusal"`, `.badResponse` otherwise.
    static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudLLMError.badResponse
        }
        if (obj["stop_reason"] as? String) == "refusal" { throw CloudLLMError.refusal }
        guard let content = obj["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              !text.isEmpty else {
            throw CloudLLMError.badResponse
        }
        return text
    }

    func complete(system: String, user: String, apiKey: String, model: String) async throws -> String {
        let req = Self.makeRequest(system: system, user: user, apiKey: apiKey, model: model)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CloudLLMError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, let err = cloudError(forStatus: http.statusCode) {
            throw err
        }
        return try Self.parseResponse(data)
    }
}
