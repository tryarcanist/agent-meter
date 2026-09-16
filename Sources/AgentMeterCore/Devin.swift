import Foundation

public enum Devin {
    static let defaultAPI = "https://server.codeium.com"
    static let statusPath =
        "/exa.seat_management_pb.SeatManagementService/GetUserStatus"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        let record = JSON.object(body) ?? [:]
        guard let planStatus = JSON.child(JSON.child(record, "userStatus") ?? [:], "planStatus")
        else {
            return .error(.devin, "no limits")
        }
        var windows: [UsageWindow] = []
        if let remaining = JSON.number(planStatus["dailyQuotaRemainingPercent"]),
           let used = WindowMath.remainingToUsed(remaining),
           let window = WindowMath.fromUsedPercent(
            label: "1d",
            used: used,
            resetsAt: JSON.date(planStatus["dailyQuotaResetAtUnix"])
           )
        {
            windows.append(window)
        }
        if let remaining = JSON.number(planStatus["weeklyQuotaRemainingPercent"]),
           let used = WindowMath.remainingToUsed(remaining),
           let window = WindowMath.fromUsedPercent(
            label: "7d",
            used: used,
            resetsAt: JSON.date(planStatus["weeklyQuotaResetAtUnix"])
           )
        {
            windows.append(window)
        }
        if windows.isEmpty {
            return .error(.devin, "no limits")
        }
        return .ok(.devin, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let cred = readCredentials() else {
            return .signedOut(.devin)
        }
        do {
            let body = try await HTTP.json(
                url: cred.api + statusPath,
                method: "POST",
                body: [
                    "metadata": [
                        "apiKey": cred.apiKey,
                        "ideName": "devin",
                        "ideVersion": "0.0.0",
                        "extensionName": "devin",
                        "extensionVersion": "0.0.0",
                        "locale": "en",
                    ],
                ]
            )
            return parse(body)
        } catch let error as HTTPError where error.status == 401 || error.status == 403 {
            return .signedOut(.devin)
        } catch {
            return .error(.devin, "request failed")
        }
    }

    private struct Cred {
        var apiKey: String
        var api: String
    }

    private static func readCredentials() -> Cred? {
        let url = Paths.home(".local", "share", "devin", "credentials.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let fields = Secrets.toml(text)
        guard let apiKey = fields["windsurf_api_key"], !apiKey.isEmpty else {
            return nil
        }
        let api = fields["api_server_url"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultAPI
        guard api.hasPrefix("https://") else { return nil }
        return Cred(apiKey: apiKey, api: api)
    }
}
