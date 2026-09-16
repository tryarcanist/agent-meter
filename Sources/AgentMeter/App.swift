import AppKit
import AgentMeterCore

@main
enum AgentMeterMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--json") {
            dumpJSON()
            return
        }
        let app = NSApplication.shared
        let delegate = MenuBar()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func dumpJSON() {
        final class Box: @unchecked Sendable { var data: Data? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.data = try? Collect.json(await Collect.all())
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        if let data = box.data {
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
    }
}

@MainActor
final class MenuBar: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var providers = ProviderID.allCases.map { ProviderSnapshot.loading($0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "agent-meter"
        render()
        fetchAll()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func refresh() {
        providers = ProviderID.allCases.map { .loading($0) }
        render()
        fetchAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func fetchAll() {
        for id in ProviderID.allCases {
            Task { [weak self] in
                let snapshot = await Collect.one(id)
                self?.replace(snapshot)
            }
        }
    }

    private func replace(_ snapshot: ProviderSnapshot) {
        if let index = providers.firstIndex(where: { $0.id == snapshot.id }) {
            providers[index] = snapshot
        }
        render()
    }

    private func render() {
        let title: String
        let used: Double
        if let hottest = Collect.hottest(providers) {
            title = "\(Int(hottest.usedPercent.rounded()))%"
            used = hottest.usedPercent
        } else {
            title = providers.contains { $0.status == .loading } ? "…" : "—"
            used = 0
        }
        item.button?.attributedTitle = barTitle(title, used: used)
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for provider in providers {
            let header = NSMenuItem(title: provider.id.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            switch provider.status {
            case .loading:
                addLine(menu, "  …")
            case .signedOut:
                addLine(menu, "  signed out")
            case .error:
                addLine(menu, "  \(provider.message ?? "error")")
            case .ok where provider.windows.isEmpty:
                addLine(menu, "  \(provider.message ?? "no limits")")
            case .ok:
                for window in provider.windows {
                    let label = window.label.padding(toLength: 6, withPad: " ", startingAt: 0)
                    let percent = String(format: "%3d%%", Int(window.usedPercent.rounded()))
                    let reset = resetText(window.resetsAt)
                    addLine(menu, reset.isEmpty
                        ? "  \(label) \(percent)"
                        : "  \(label) \(percent)   \(reset)")
                }
            }
            menu.addItem(.separator())
        }
        for (title, action, key) in [
            ("Refresh", #selector(refresh), "r"),
            ("Quit", #selector(quit), "q"),
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
    }

    private func addLine(_ menu: NSMenu, _ title: String) {
        let line = NSMenuItem()
        line.isEnabled = false
        line.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        menu.addItem(line)
    }

    private func barTitle(_ text: String, used: Double) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: used >= 90 ? NSColor.systemRed
                : used >= 70 ? .systemOrange : .labelColor,
        ])
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "now" }
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 48 { return "\(hours / 24)d \(hours % 24)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
