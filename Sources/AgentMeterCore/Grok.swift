import Foundation

public enum Grok {
    static let billingURL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"

    public static func parse(_ body: Any) -> ProviderSnapshot {
        guard let config = JSON.child(JSON.object(body) ?? [:], "config") ?? JSON.object(body)
        else { return .error(.grok, "bad response") }
        let used = JSON.number(config["creditUsagePercent"]) ?? 0
        let period = JSON.child(config, "currentPeriod", "current_period") ?? [:]
        let type = JSON.string(period["type"]) ?? ""
        let label: String
        if type.contains("MONTHLY") {
            label = "30d"
        } else if type.contains("WEEKLY") || type.isEmpty {
            label = "7d"
        } else {
            return .error(.grok, "unknown period")
        }
        guard let window = WindowMath.fromUsedPercent(
            label: label,
            used: used,
            resetsAt: JSON.date(period["end"] ?? config["billingPeriodEnd"])
        ) else { return .error(.grok, "no limits") }
        return .ok(.grok, windows: [window])
    }

    public static func collect() async -> ProviderSnapshot {
        guard let cred = readCredentials() else { return .signedOut(.grok) }
        var headers = [
            "Authorization": "Bearer \(cred.key)",
            "X-XAI-Token-Auth": "xai-grok-cli",
        ]
        if let userId = cred.userId { headers["x-userid"] = userId }
        do {
            return parse(try await HTTP.json(url: billingURL, headers: headers))
        } catch let error as HTTPError where error.status == 401 || error.status == 403 {
            return .signedOut(.grok)
        } catch {
            return .error(.grok, "request failed")
        }
    }

    private struct Cred {
        var key: String
        var userId: String?
        var createTime: String
    }

    private static func readCredentials() -> Cred? {
        guard let file = JSON.parseFile(Paths.home(".grok", "auth.json")) else { return nil }
        return JSON.walkObjects(file)
            .compactMap { obj in
                JSON.string(obj["key"]).map {
                    Cred(
                        key: $0,
                        userId: JSON.string(JSON.field(obj, "user_id", "userId")),
                        createTime: JSON.string(JSON.field(obj, "create_time", "createTime")) ?? ""
                    )
                }
            }
            .max { $0.createTime < $1.createTime }
    }
}
