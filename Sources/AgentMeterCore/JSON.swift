import Foundation

enum JSON {
    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            return n.doubleValue
        }
        if let s = string(value), let d = Double(s) {
            return d
        }
        return nil
    }

    static func field(_ object: [String: Any], _ keys: String...) -> Any? {
        for key in keys where object[key] != nil {
            return object[key]
        }
        return nil
    }

    static func child(_ object: [String: Any], _ keys: String...) -> [String: Any]? {
        for key in keys {
            if let child = object[key] as? [String: Any] {
                return child
            }
        }
        return nil
    }

    static func walkObjects(_ value: Any?) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func visit(_ node: Any?) {
            if let arr = node as? [Any] {
                arr.forEach { visit($0) }
                return
            }
            guard let obj = node as? [String: Any] else { return }
            found.append(obj)
            obj.values.forEach { visit($0) }
        }
        visit(value)
        return found
    }

    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func parseFile(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func date(_ value: Any?) -> Date? {
        if let n = number(value) {
            let seconds = n > 1_000_000_000_000 ? n / 1000 : n
            return Date(timeIntervalSince1970: seconds)
        }
        if let s = string(value) {
            if let n = Double(s), s.allSatisfy({ $0.isNumber || $0 == "." }) {
                return date(n)
            }
            return ISO8601DateFormatter.withFraction.date(from: s)
                ?? ISO8601DateFormatter.plain.date(from: s)
        }
        return nil
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
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func home(_ parts: String...) -> URL {
        parts.reduce(home) { $0.appendingPathComponent($1) }
    }
}
