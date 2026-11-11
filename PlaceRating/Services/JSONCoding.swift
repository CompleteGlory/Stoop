import Foundation

extension JSONDecoder {
    /// The API sends ISO-8601 with milliseconds, which the built-in `.iso8601` strategy rejects.
    static let api: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: string) ?? plain.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Bad date: \(string)"
            ))
        }
        return decoder
    }()
}
