import Foundation

enum JSON {
    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String? {
        (value as? String).flatMap { s in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return string(value).flatMap(Double.init)
    }

    static func field(_ object: [String: Any], _ keys: String...) -> Any? {
        keys.lazy.compactMap { object[$0] }.first
    }

    static func child(_ object: [String: Any], _ keys: String...) -> [String: Any]? {
        keys.lazy.compactMap { object[$0] as? [String: Any] }.first
    }

    static func walkObjects(_ value: Any?) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func visit(_ node: Any?) {
            if let arr = node as? [Any] {
                arr.forEach(visit)
            } else if let obj = node as? [String: Any] {
                found.append(obj)
                obj.values.forEach(visit)
            }
        }
        visit(value)
        return found
    }

    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func parseFile(_ url: URL) -> Any? {
        (try? Data(contentsOf: url)).flatMap(parse)
    }

    static func date(_ value: Any?) -> Date? {
        if let n = number(value) {
            return Date(timeIntervalSince1970: n > 1_000_000_000_000 ? n / 1000 : n)
        }
        guard let s = string(value) else { return nil }
        return ISO8601DateFormatter.withFraction.date(from: s)
            ?? ISO8601DateFormatter.plain.date(from: s)
    }
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum Paths {
    static func home(_ parts: String...) -> URL {
        parts.reduce(FileManager.default.homeDirectoryForCurrentUser) {
            $0.appendingPathComponent($1)
        }
    }
}
