import Foundation

public enum Collect {
    public static func one(_ id: ProviderID) async -> ProviderSnapshot {
        switch id {
        case .claude: await timed(.claude) { await Claude.collect() }
        case .codex: await timed(.codex) { await Codex.collect() }
        case .grok: await timed(.grok) { await Grok.collect() }
        case .muse: await timed(.muse) { await Muse.collect() }
        case .devin: await timed(.devin) { await Devin.collect() }
        }
    }

    public static func all() async -> [ProviderSnapshot] {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for id in ProviderID.allCases {
                group.addTask { await one(id) }
            }
            var byID: [ProviderID: ProviderSnapshot] = [:]
            for await snapshot in group {
                byID[snapshot.id] = snapshot
            }
            return ProviderID.allCases.map { byID[$0] ?? .error($0, "missing") }
        }
    }

    private static func timed(
        _ id: ProviderID,
        _ work: @escaping @Sendable () async -> ProviderSnapshot
    ) async -> ProviderSnapshot {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            group.addTask(operation: work)
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                return .error(id, "timeout")
            }
            defer { group.cancelAll() }
            return await group.next() ?? .error(id, "timeout")
        }
    }

    public static func hottest(_ providers: [ProviderSnapshot]) -> UsageWindow? {
        providers
            .filter { $0.status == .ok }
            .flatMap(\.windows)
            .max { $0.usedPercent < $1.usedPercent }
    }

    public static func json(_ providers: [ProviderSnapshot]) throws -> Data {
        let payload: [[String: Any]] = providers.map { provider in
            var row: [String: Any] = [
                "id": provider.id.rawValue,
                "name": provider.id.title,
                "status": provider.status.rawValue,
                "windows": provider.windows.map { window in
                    var item: [String: Any] = [
                        "label": window.label,
                        "usedPercent": window.usedPercent,
                    ]
                    if let resets = window.resetsAt {
                        item["resetsAt"] = ISO8601DateFormatter.plain.string(from: resets)
                    }
                    return item
                },
            ]
            if let message = provider.message {
                row["message"] = message
            }
            return row
        }
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
