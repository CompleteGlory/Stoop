import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Builds requests and turns responses into data or an `APIError`. Knows nothing about tokens.
struct HTTPClient: Sendable {
    let baseURL: @Sendable () -> URL
    let transport: any HTTPTransport

    func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        token: String? = nil
    ) throws -> URLRequest {
        var url = baseURL().appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder.api.decode(APIErrorEnvelope.self, from: data).error
            throw APIError(
                status: response.statusCode,
                code: body?.code ?? "unknown",
                message: body?.message ?? ""
            )
        }
        return data
    }
}
