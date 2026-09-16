import Foundation
import LocalAuthentication
import Security
import os

enum Secrets {
    private struct Cache {
        var hits: [String: String] = [:]
        var misses: Set<String> = []
    }

    private static let cache = OSAllocatedUnfairLock(initialState: Cache())

    static func resetCache() {
        cache.withLock { $0 = Cache() }
    }

    static func keychainPassword(service: String, account: String? = nil) -> String? {
        let key = "\(service)\u{0}\(account ?? "")"
        if let hit = cache.withLock({ $0.hits[key] }) { return hit }
        if cache.withLock({ $0.misses.contains(key) }) { return nil }
        let value = secItem(service: service, account: account, prompt: false)
            ?? securityCLI(service: service, account: account)
            ?? secItem(service: service, account: account, prompt: true)
        cache.withLock {
            if let value { $0.hits[key] = value } else { $0.misses.insert(key) }
        }
        return value
    }

    private static func secItem(service: String, account: String?, prompt: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        if !prompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8).flatMap(trimmed)
    }

    private static func securityCLI(service: String, account: String?) -> String? {
        var args = ["find-generic-password", "-s", service, "-w"]
        if let account { args.insert(contentsOf: ["-a", account], at: 3) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(60)
        while proc.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            .flatMap(trimmed)
    }

    static func toml(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("[") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            fields[line[..<eq].trimmingCharacters(in: .whitespaces)] = value
        }
        return fields
    }

    private static func trimmed(_ value: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
