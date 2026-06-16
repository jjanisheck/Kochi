import Foundation

/// Failure modes for a cloud-LLM analysis call.
enum CloudLLMError: Error, Equatable {
    case missingKey
    case auth
    case rateLimited
    case refusal
    case badResponse
    case http(Int)
    case network(String)
}

/// A provider client that returns the raw structured-JSON text for one completion.
protocol CloudLLMClient {
    func complete(system: String, user: String, apiKey: String, model: String) async throws -> String
}
