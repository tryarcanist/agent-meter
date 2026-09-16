import Foundation

struct HTTPError: Error {
    var status: Int
}

enum HTTP {
    private static let session = URLSession(configuration: {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }())

    static func json(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Any? = nil,
        form: String? = nil
    ) async throws -> Any {
        guard let url = URL(string: url) else { throw HTTPError(status: 0) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(form.utf8)
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPError(status: status) }
        return data.isEmpty ? [String: Any]() : try JSONSerialization.jsonObject(with: data)
    }
}
