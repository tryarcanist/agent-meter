import Foundation

public enum Devin {
    static let defaultAPI = "https://server.codeium.com"
    static let statusPath = "/exa.seat_management_pb.SeatManagementService/GetUserStatus"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        let record = JSON.object(body) ?? [:]
        guard let planStatus = JSON.child(JSON.child(record, "userStatus") ?? [:], "planStatus")
        else { return .error(.devin, "no limits") }
        let windows = [
            ("dailyQuotaRemainingPercent", "1d", "dailyQuotaResetAtUnix"),
            ("weeklyQuotaRemainingPercent", "7d", "weeklyQuotaResetAtUnix"),
        ].compactMap { remainingKey, label, resetKey in
            JSON.number(planStatus[remainingKey])
                .flatMap(WindowMath.remainingToUsed)
                .flatMap {
                    WindowMath.fromUsedPercent(
                        label: label,
                        used: $0,
                        resetsAt: JSON.date(planStatus[resetKey])
                    )
                }
        }
        return windows.isEmpty ? .error(.devin, "no limits") : .ok(.devin, windows: windows)
    }

    public static func collect() async -> ProviderSnapshot {
        guard let cred = readCredentials() else { return .signedOut(.devin) }
        do {
            return parse(try await HTTP.json(url: cred.api + statusPath, method: "POST", body: [
                "metadata": [
                    "apiKey": cred.apiKey,
                    "ideName": "devin",
                    "ideVersion": "0.0.0",
                    "extensionName": "devin",
                    "extensionVersion": "0.0.0",
                    "locale": "en",
                ],
            ]))
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
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = Secrets.toml(text)
        guard let apiKey = fields["windsurf_api_key"], !apiKey.isEmpty else { return nil }
        let api = fields["api_server_url"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultAPI
        guard api.hasPrefix("https://") else { return nil }
        return Cred(apiKey: apiKey, api: api)
    }
}
