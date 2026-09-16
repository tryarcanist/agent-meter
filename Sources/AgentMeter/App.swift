import AppKit
import AgentMeterCore

@main
enum AgentMeterMain {
    static func main() {
        if CommandLine.arguments.contains("--json") {
            dumpJSON()
            return
        }
        let app = NSApplication.shared
        let delegate = MenuBar()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private static func dumpJSON() {
        var data: Data?
        let lock = NSLock()
        var done = false
        Task.detached {
            let providers = await Collect.all()
            let payload = try? Collect.json(providers)
            lock.lock()
            data = payload
            done = true
            lock.unlock()
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            lock.lock()
            let finished = done
            lock.unlock()
            if finished { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if let data {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

final class MenuBar: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var providers: [ProviderSnapshot] = ProviderID.allCases.map { .loading($0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "agent-meter"
        render()
        fetchAll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
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
            Task.detached { [weak self] in
                let snapshot = await Collect.one(id)
                DispatchQueue.main.async {
                    self?.replace(snapshot)
                }
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
        if let hottest = Collect.hottest(providers) {
            let used = Int(hottest.usedPercent.rounded())
            item.button?.attributedTitle = barTitle("\(used)%", used: hottest.usedPercent)
        } else if providers.contains(where: { $0.status == .loading }) {
            item.button?.attributedTitle = barTitle("…", used: 0)
        } else {
            item.button?.attributedTitle = barTitle("—", used: 0)
        }
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
                    let used = Int(window.usedPercent.rounded())
                    let reset = resetText(window.resetsAt)
                    let label = window.label.padding(toLength: 6, withPad: " ", startingAt: 0)
                    let percent = String(format: "%3d%%", used)
                    let title = reset.isEmpty
                        ? "  \(label) \(percent)"
                        : "  \(label) \(percent)   \(reset)"
                    addLine(menu, title)
                }
            }
            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = true
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func addLine(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        menu.addItem(item)
    }

    private func barTitle(_ text: String, used: Double) -> NSAttributedString {
        let color: NSColor
        if used >= 90 {
            color = .systemRed
        } else if used >= 70 {
            color = .systemOrange
        } else {
            color = .labelColor
        }
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: color,
            ]
        )
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "now" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 48 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        if hours >= 1 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
