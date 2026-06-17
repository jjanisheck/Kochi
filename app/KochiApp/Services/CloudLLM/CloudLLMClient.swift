import Foundation

/// Failure modes for a cloud-LLM analysis call.
enum CloudLLMError: Error, Equatable {
    case missingKey
    case auth
    case rateLimited
    case refusal
    case truncated
    case badResponse
    case http(Int)
    case network(String)
}

/// The structured-JSON text plus token usage from one completion.
struct CloudLLMResult: Equatable {
    let text: String
    let inputTokens: Int
    let outputTokens: Int
}

/// A provider client that returns the structured-JSON text + token usage for one completion.
protocol CloudLLMClient {
    func complete(system: String, user: String, apiKey: String, model: String) async throws -> CloudLLMResult
}

/// Maps an HTTP status code to a `CloudLLMError`, or nil for 2xx success.
func cloudError(forStatus status: Int) -> CloudLLMError? {
    switch status {
    case 200...299: return nil
    case 401, 403:  return .auth
    case 429:       return .rateLimited
    default:        return .http(status)
    }
}
