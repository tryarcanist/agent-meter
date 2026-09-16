import Foundation

public enum Codex {
    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let record = JSON.object(body) else { return .error(.codex, "bad response") }
        var windows: [UsageWindow] = []
        func push(_ window: UsageWindow?) {
            guard let window else { return }
            if let index = windows.firstIndex(where: { $0.label == window.label }) {
                if window.usedPercent > windows[index].usedPercent { windows[index] = window }
            } else {
                windows.append(window)
            }
        }
        let rate = JSON.child(record, "rate_limit", "rateLimit") ?? [:]
        var specs: [(Any?, String)] = [
            (rate["primary_window"] ?? rate["primaryWindow"], "7d"),
            (rate["secondary_window"] ?? rate["secondaryWindow"], "5h"),
        ]
        for extra in JSON.array(JSON.field(record, "additional_rate_limits", "additionalRateLimits")) {
            let nested = JSON.child(JSON.object(extra) ?? [:], "rate_limit", "rateLimit") ?? [:]
            specs += [
                (nested["primary_window"] ?? nested["primaryWindow"], "5h"),
                (nested["secondary_window"] ?? nested["secondaryWindow"], "7d"),
            ]
        }
        specs.forEach { push(parseWindow($0.0, fallback: $0.1)) }
        return windows.isEmpty ? .error(.codex, "no limits") : .ok(.codex, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let auth = readAuth() else { return .signedOut(.codex) }
        do {
            return parse(try await fetch(auth.accessToken, accountId: auth.accountId))
        } catch let error as HTTPError where error.status == 401 {
            guard let refresh = auth.refreshToken,
                  let next = await refreshAccess(refresh),
                  let body = try? await fetch(next, accountId: auth.accountId)
            else { return .signedOut(.codex) }
            return parse(body)
        } catch let error as HTTPError where error.status == 403 {
            return .signedOut(.codex)
        } catch {
            return .error(.codex, "request failed")
        }
    }

    private struct Auth {
        var accessToken: String
        var refreshToken: String?
        var accountId: String?
    }

    private static func parseWindow(_ value: Any?, fallback: String) -> UsageWindow? {
        guard let record = JSON.object(value),
              let used = JSON.number(JSON.field(record, "used_percent", "usedPercent"))
        else { return nil }
        let label = JSON.number(JSON.field(record, "limit_window_seconds", "limitWindowSeconds"))
            .map(WindowMath.label(seconds:)) ?? fallback
        return WindowMath.fromUsedPercent(
            label: label,
            used: used,
            resetsAt: JSON.date(JSON.field(record, "reset_at", "resetAt"))
        )
    }

    private static func readAuth() -> Auth? {
        guard let file = JSON.object(JSON.parseFile(Paths.home(".codex", "auth.json"))) else {
            return nil
        }
        let tokens = JSON.child(file, "tokens") ?? file
        guard let access = JSON.string(JSON.field(tokens, "access_token", "accessToken")) else {
            return nil
        }
        return Auth(
            accessToken: access,
            refreshToken: JSON.string(JSON.field(tokens, "refresh_token", "refreshToken")),
            accountId: JSON.string(
                JSON.field(tokens, "account_id", "chatgpt_account_id", "chatgptAccountId")
            )
        )
    }

    private static func fetch(_ token: String, accountId: String?) async throws -> Any {
        var headers = [
            "Authorization": "Bearer \(token)",
            "User-Agent": "agent-meter/0.1",
        ]
        if let accountId { headers["ChatGPT-Account-Id"] = accountId }
        return try await HTTP.json(url: usageURL, headers: headers)
    }

    private static func refreshAccess(_ refreshToken: String) async -> String? {
        let body = try? await HTTP.json(
            url: tokenURL,
            method: "POST",
            form: "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        )
        return JSON.string(JSON.object(body)?["access_token"])
    }
}
