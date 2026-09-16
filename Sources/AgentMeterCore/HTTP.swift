import Foundation

struct HTTPError: Error {
    var status: Int
}

enum HTTP {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: nil, delegateQueue: OperationQueue())
    }()

    static func json(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Any? = nil,
        form: String? = nil
    ) async throws -> Any {
        guard let parsed = URL(string: url) else {
            throw HTTPError(status: 0)
        }
        var request = URLRequest(url: parsed, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let form {
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = form.data(using: .utf8)
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            throw HTTPError(status: status)
        }
        if data.isEmpty {
            return [String: Any]()
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}
