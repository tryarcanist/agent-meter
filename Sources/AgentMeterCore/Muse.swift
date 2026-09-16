import Foundation

public enum Muse {
    static let keyURL = "https://api.meta.ai/muse-code/key"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let record = JSON.object(body) else {
            return .error(.muse, "bad response")
        }
        if JSON.bool(record["is_subs_active"]) == false {
            return .ok(.muse, windows: [], message: "no limits")
        }
        let usage = JSON.child(record, "subs_usage", "subsUsage") ?? [:]
        var windows: [UsageWindow] = []
        if let window = parseWindow(usage["window"], fallback: "5h") {
            windows.append(window)
        }
        if let weekly = parseWindow(usage["weekly"], fallback: "7d") {
            windows.append(weekly)
        }
        if windows.isEmpty {
            return .ok(.muse, windows: [], message: "no limits")
        }
        return .ok(.muse, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let token = readToken() else {
            return .signedOut(.muse)
        }
        do {
            let body = try await HTTP.json(
                url: keyURL,
                method: "POST",
                headers: [
                    "Authorization": "Bearer \(token)",
                    "x-api-version": "1.0.0",
                ],
                body: [String: Any]()
            )
            return parse(body)
        } catch let error as HTTPError where error.status == 401 || error.status == 403 {
            return .signedOut(.muse)
        } catch {
            return .error(.muse, "request failed")
        }
    }

    private static func parseWindow(_ value: Any?, fallback: String) -> UsageWindow? {
        guard let record = JSON.object(value),
              let used = JSON.number(JSON.field(record, "used_percent", "usedPercent"))
        else { return nil }
        var label = fallback
        if let minutes = JSON.number(JSON.field(record, "window_duration_mins", "windowDurationMins")),
           minutes > 0
        {
            label = minutes.truncatingRemainder(dividingBy: 60) == 0
                ? "\(Int(minutes / 60))h"
                : "\(Int(minutes))m"
        }
        return WindowMath.fromUsedPercent(
            label: label,
            used: used,
            resetsAt: JSON.date(JSON.field(record, "resets_at", "resetsAt"))
        )
    }

    private static func readToken() -> String? {
        if let file = JSON.object(JSON.parseFile(Paths.home(".config", "muse", "auth.json"))),
           let meta = JSON.child(JSON.child(file, "providers") ?? [:], "meta"),
           let token = JSON.string(JSON.field(meta, "access_token", "accessToken"))
        {
            return token
        }
        guard let secret = Secrets.keychainPassword(
            service: "ai.meta.dev.credentials",
            account: "meta"
        ), let data = secret.data(using: .utf8),
            let json = JSON.object(JSON.parse(data))
        else {
            return nil
        }
        return JSON.string(JSON.field(json, "access_token", "accessToken"))
    }
}
