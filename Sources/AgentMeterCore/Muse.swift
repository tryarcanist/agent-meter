import Foundation

public enum Muse {
    static let keyURL = "https://api.meta.ai/muse-code/key"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let record = JSON.object(body) else { return .error(.muse, "bad response") }
        if JSON.bool(record["is_subs_active"]) == false {
            return .ok(.muse, windows: [], message: "no limits")
        }
        let usage = JSON.child(record, "subs_usage", "subsUsage") ?? [:]
        let windows = [
            parseWindow(usage["window"], fallback: "5h"),
            parseWindow(usage["weekly"], fallback: "7d"),
        ].compactMap { $0 }
        return .ok(.muse, windows: windows, message: windows.isEmpty ? "no limits" : nil)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let token = readToken() else { return .signedOut(.muse) }
        do {
            return parse(try await HTTP.json(
                url: keyURL,
                method: "POST",
                headers: [
                    "Authorization": "Bearer \(token)",
                    "x-api-version": "1.0.0",
                ],
                body: [String: Any]()
            ))
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
        guard let secret = Secrets.keychainPassword(service: "ai.meta.dev.credentials", account: "meta"),
              let data = secret.data(using: .utf8)
        else { return nil }
        return JSON.string(JSON.field(JSON.object(JSON.parse(data)) ?? [:], "access_token", "accessToken"))
    }
}
