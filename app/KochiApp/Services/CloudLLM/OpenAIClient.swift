import Foundation

/// Calls OpenAI's Chat Completions API with structured-JSON output.
struct OpenAIClient: CloudLLMClient {
    var session: URLSession = .shared

    /// Builds the POST request. Pure (no I/O) so it can be unit-checked.
    static func makeRequest(system: String, user: String, apiKey: String, model: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "meeting_analysis",
                    "strict": true,
                    "schema": AnalysisSchema.jsonSchema
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extracts the assistant's structured-JSON content from a response body.
    /// Throws `.refusal` if the model populated a `refusal`, `.badResponse` otherwise.
    static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw CloudLLMError.badResponse
        }
        if (choices.first?["finish_reason"] as? String) == "length" { throw CloudLLMError.truncated }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            throw CloudLLMError.refusal
        }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw CloudLLMError.badResponse
        }
        return content
    }

    /// Extracts (input, output) token counts from a response body, or nil if absent.
    static func parseUsage(_ data: Data) -> (input: Int, output: Int)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = obj["usage"] as? [String: Any] else { return nil }
        return ((usage["prompt_tokens"] as? Int) ?? 0, (usage["completion_tokens"] as? Int) ?? 0)
    }

    func complete(system: String, user: String, apiKey: String, model: String) async throws -> CloudLLMResult {
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
        let text = try Self.parseResponse(data)
        let usage = Self.parseUsage(data)
        return CloudLLMResult(text: text, inputTokens: usage?.input ?? 0, outputTokens: usage?.output ?? 0)
    }
}
