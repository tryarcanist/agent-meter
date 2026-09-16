import Foundation

public enum ProviderID: String, CaseIterable, Sendable {
    case claude, codex, grok, devin

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .devin: "Devin"
        }
    }
}

public struct UsageWindow: Sendable, Equatable {
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }
}

public enum ProviderStatus: String, Sendable {
    case loading, ok, signedOut, error
}

public struct ProviderSnapshot: Sendable {
    public var id: ProviderID
    public var status: ProviderStatus
    public var windows: [UsageWindow]
    public var message: String?

    public init(id: ProviderID, status: ProviderStatus, windows: [UsageWindow] = [], message: String? = nil) {
        self.id = id
        self.status = status
        self.windows = windows
        self.message = message
    }

    public static func loading(_ id: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(id: id, status: .loading, message: "…")
    }

    public static func ok(_ id: ProviderID, windows: [UsageWindow], message: String? = nil) -> ProviderSnapshot {
        ProviderSnapshot(id: id, status: .ok, windows: windows, message: message)
    }

    public static func signedOut(_ id: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(id: id, status: .signedOut, message: "signed out")
    }

    public static func error(_ id: ProviderID, _ message: String) -> ProviderSnapshot {
        ProviderSnapshot(id: id, status: .error, message: message)
    }
}

public enum WindowMath {
    public static func fromUsedPercent(label: String, used: Double?, resetsAt: Date?) -> UsageWindow? {
        guard let used, used.isFinite else { return nil }
        return UsageWindow(label: label, usedPercent: used, resetsAt: resetsAt)
    }

    public static func label(seconds: Double) -> String {
        if abs(seconds - 5 * 3600) <= 5 * 60 { return "5h" }
        if abs(seconds - 24 * 3600) <= 30 * 60 { return "1d" }
        if abs(seconds - 7 * 24 * 3600) <= 3 * 3600 { return "7d" }
        if abs(seconds - 30 * 24 * 3600) <= 2 * 24 * 3600 { return "30d" }
        if seconds.truncatingRemainder(dividingBy: 24 * 3600) == 0 {
            return "\(Int(seconds / (24 * 3600)))d"
        }
        if seconds.truncatingRemainder(dividingBy: 3600) == 0 {
            return "\(Int(seconds / 3600))h"
        }
        return "\(Int((seconds / 60).rounded()))m"
    }

    public static func remainingToUsed(_ remaining: Double) -> Double? {
        guard remaining.isFinite, (0...100).contains(remaining) else { return nil }
        return 100 - remaining
    }
}
