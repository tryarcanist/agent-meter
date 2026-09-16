import Foundation

public enum Claude {
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let record = JSON.object(body) else {
            return .error(.claude, "bad response")
        }
        var windows: [UsageWindow] = []
        if let five = JSON.child(record, "five_hour"),
           let window = WindowMath.fromUsedPercent(
            label: "5h",
            used: JSON.number(five["utilization"]),
            resetsAt: JSON.date(five["resets_at"])
           )
        {
            windows.append(window)
        }
        if let seven = JSON.child(record, "seven_day"),
           let window = WindowMath.fromUsedPercent(
            label: "7d",
            used: JSON.number(seven["utilization"]),
            resetsAt: JSON.date(seven["resets_at"])
           )
        {
            windows.append(window)
        }
        for item in JSON.array(record["limits"]) {
            guard let limit = JSON.object(item) else { continue }
            let kind = JSON.string(limit["kind"])
            if kind == "session" || kind == "weekly_all" { continue }
            guard let percent = JSON.number(limit["percent"]) else { continue }
            let model = JSON.child(JSON.child(limit, "scope") ?? [:], "model")
            let label = JSON.string(model?["display_name"])
                ?? JSON.string(model?["id"])
                ?? kind
                ?? "limit"
            if windows.contains(where: { $0.label == label }) { continue }
            if let window = WindowMath.fromUsedPercent(
                label: label,
                used: percent,
                resetsAt: JSON.date(limit["resets_at"])
            ) {
                windows.append(window)
            }
        }
        if windows.isEmpty {
            return .error(.claude, "no limits")
        }
        return .ok(.claude, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard var oauth = readOauth() else {
            return .signedOut(.claude)
        }
        if let expires = oauth.expiresAt, expires < Date().addingTimeInterval(60),
           let refresh = oauth.refreshToken,
           let next = await refreshAccess(refresh)
        {
            oauth.accessToken = next
        }
        do {
            let body = try await HTTP.json(
                url: usageURL,
                headers: [
                    "Authorization": "Bearer \(oauth.accessToken)",
                    "anthropic-beta": "oauth-2025-04-20",
                    "anthropic-version": "2023-06-01",
                    "x-app": "cli",
                    "User-Agent": "agent-meter/0.1",
                ]
            )
            return parse(body)
        } catch let error as HTTPError where error.status == 401 || error.status == 403 {
            return .signedOut(.claude)
        } catch {
            return .error(.claude, "request failed")
        }
    }

    private struct Oauth {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
    }

    private static func readOauth() -> Oauth? {
        let username = Secrets.currentUsername()
        let secret = Secrets.keychainPassword(
            service: "Claude Code-credentials",
            account: username
        ) ?? Secrets.keychainPassword(service: "Claude Code-credentials")
        if let secret, let data = secret.data(using: .utf8),
           let json = JSON.parse(data),
           let oauth = parseOauth(json)
        {
            return oauth
        }
        if let file = JSON.parseFile(Paths.home(".claude", ".credentials.json")) {
            return parseOauth(file)
        }
        return nil
    }

    private static func parseOauth(_ value: Any) -> Oauth? {
        guard let root = JSON.object(value) else { return nil }
        let oauth = JSON.child(root, "claudeAiOauth", "claude_ai_oauth") ?? root
        guard let access = JSON.string(JSON.field(oauth, "accessToken", "access_token")) else {
            return nil
        }
        let expires = JSON.number(JSON.field(oauth, "expiresAt", "expires_at"))
        return Oauth(
            accessToken: access,
            refreshToken: JSON.string(JSON.field(oauth, "refreshToken", "refresh_token")),
            expiresAt: expires.map { Date(timeIntervalSince1970: $0 > 1_000_000_000_000 ? $0 / 1000 : $0) }
        )
    }

    private static func refreshAccess(_ refreshToken: String) async -> String? {
        do {
            let body = try await HTTP.json(
                url: tokenURL,
                method: "POST",
                body: [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": clientID,
                ]
            )
            let record = JSON.object(body) ?? [:]
            return JSON.string(JSON.field(record, "access_token", "accessToken"))
        } catch {
            return nil
        }
    }
}
