import AgentMeterCore
import Foundation

var failed = 0

func expect(_ cond: Bool, _ name: String) {
    if cond {
        print("ok  \(name)")
    } else {
        print("FAIL \(name)")
        failed += 1
    }
}

func testClaude() {
    let body: [String: Any] = [
        "five_hour": ["utilization": 24, "resets_at": "2026-09-16T16:20:00Z"],
        "seven_day": ["utilization": 32, "resets_at": "2026-09-22T02:59:59Z"],
        "limits": [
            ["kind": "session", "percent": 24],
            [
                "kind": "weekly_scoped",
                "percent": 52,
                "resets_at": "2026-09-22T02:59:59Z",
                "scope": ["model": ["display_name": "Fable"]],
            ],
        ],
    ]
    let snapshot = Claude.parse(body)
    expect(snapshot.status == .ok, "claude status")
    expect(snapshot.windows.map(\.label) == ["5h", "7d", "Fable"], "claude labels")
    expect(snapshot.windows.map(\.usedPercent) == [24, 32, 52], "claude percents")
}

func testCodex() {
    let body: [String: Any] = [
        "rate_limit": [
            "primary_window": [
                "used_percent": 18,
                "limit_window_seconds": 604_800,
                "reset_at": 1_790_101_952,
            ],
        ],
        "additional_rate_limits": [
            [
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 11,
                        "limit_window_seconds": 18_000,
                        "reset_at": 1_789_580_447,
                    ],
                    "secondary_window": [
                        "used_percent": 3,
                        "limit_window_seconds": 604_800,
                        "reset_at": 1_790_167_247,
                    ],
                ],
            ],
        ],
    ]
    let snapshot = Codex.parse(body)
    expect(snapshot.windows.map(\.label) == ["7d", "5h"], "codex labels")
    expect(snapshot.windows.map(\.usedPercent) == [18, 11], "codex percents")
}

func testGrok() {
    let body: [String: Any] = [
        "config": [
            "currentPeriod": [
                "type": "USAGE_PERIOD_TYPE_WEEKLY",
                "end": "2026-09-22T15:42:00Z",
            ],
        ],
    ]
    let snapshot = Grok.parse(body)
    expect(snapshot.windows.first?.usedPercent == 0, "grok zero")
    expect(snapshot.windows.first?.label == "7d", "grok label")
}

func testMuse() {
    let empty = Muse.parse(["is_subs_active": true])
    expect(empty.windows.isEmpty, "muse empty windows")
    expect(empty.message == "no limits", "muse no limits")
    let body: [String: Any] = [
        "is_subs_active": true,
        "subs_usage": [
            "window": [
                "used_percent": 4,
                "window_duration_mins": 300,
                "resets_at": 1_789_068_250,
            ],
            "weekly": ["used_percent": 28, "resets_at": 1_789_344_000],
        ],
    ]
    let snapshot = Muse.parse(body)
    expect(snapshot.windows.map(\.label) == ["5h", "7d"], "muse labels")
    expect(snapshot.windows.last?.usedPercent == 28, "muse weekly")
}

func testDevin() {
    let body: [String: Any] = [
        "userStatus": [
            "planStatus": [
                "dailyQuotaRemainingPercent": 95,
                "weeklyQuotaRemainingPercent": 94,
                "dailyQuotaResetAtUnix": "1789632000",
                "weeklyQuotaResetAtUnix": "1789891200",
            ],
        ],
    ]
    let snapshot = Devin.parse(body)
    expect(snapshot.windows.map(\.label) == ["1d", "7d"], "devin labels")
    expect(snapshot.windows.map(\.usedPercent) == [5, 6], "devin percents")
}

testClaude()
testCodex()
testGrok()
testMuse()
testDevin()
if failed != 0 {
    print("\(failed) failed")
    exit(1)
}
print("all passed")
