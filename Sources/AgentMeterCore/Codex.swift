import Foundation

public enum Codex {
    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let record = JSON.object(body) else {
            return .error(.codex, "bad response")
        }
        var windows: [UsageWindow] = []
        func push(_ window: UsageWindow?) {
            guard let window else { return }
            if let index = windows.firstIndex(where: { $0.label == window.label }) {
                if window.usedPercent > windows[index].usedPercent {
                    windows[index] = window
                }
                return
            }
            windows.append(window)
        }
        let rate = JSON.child(record, "rate_limit", "rateLimit") ?? [:]
        push(parseWindow(rate["primary_window"] ?? rate["primaryWindow"], fallback: "7d"))
        push(parseWindow(rate["secondary_window"] ?? rate["secondaryWindow"], fallback: "5h"))
        for extra in JSON.array(JSON.field(record, "additional_rate_limits", "additionalRateLimits")) {
            guard let item = JSON.object(extra) else { continue }
            let nested = JSON.child(item, "rate_limit", "rateLimit") ?? [:]
            push(parseWindow(nested["primary_window"] ?? nested["primaryWindow"], fallback: "5h"))
            push(parseWindow(nested["secondary_window"] ?? nested["secondaryWindow"], fallback: "7d"))
        }
        if windows.isEmpty {
            return .error(.codex, "no limits")
        }
        return .ok(.codex, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let auth = readAuth() else {
            return .signedOut(.codex)
        }
        do {
            return parse(try await fetch(auth.accessToken, accountId: auth.accountId))
        } catch let error as HTTPError where error.status == 401 {
            if let refresh = auth.refreshToken,
               let next = await refreshAccess(refresh)
            {
                do {
                    return parse(try await fetch(next, accountId: auth.accountId))
                } catch {
                    return .signedOut(.codex)
                }
            }
            return .signedOut(.codex)
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
        let seconds = JSON.number(JSON.field(record, "limit_window_seconds", "limitWindowSeconds"))
        let label = seconds.map(WindowMath.label(seconds:)) ?? fallback
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
        if let accountId {
            headers["ChatGPT-Account-Id"] = accountId
        }
        return try await HTTP.json(url: usageURL, headers: headers)
    }

    private static func refreshAccess(_ refreshToken: String) async -> String? {
        let form =
            "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        do {
            let body = try await HTTP.json(url: tokenURL, method: "POST", form: form)
            return JSON.string(JSON.object(body)?["access_token"])
        } catch {
            return nil
        }
    }
}
