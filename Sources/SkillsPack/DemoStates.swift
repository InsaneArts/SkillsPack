#if DEBUG
import AppKit
import SkillsPackCore
import SwiftUI

/// Debug only: `SkillsPack --demo-states <out> <demo-home>` runs the demo film's story against a demo home
/// with real actions, and saves each UI state as a PNG (400×600 points at 2×) plus the menu bar strip.
@MainActor
enum DemoStates {
    static func run(out: URL, home: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--menubar-only") {
            await capture(MenuBarStrip(), name: "menubar", size: MenuBarStrip.size, wait: 0.3, to: out)
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(1))
        let store = SkillStore(paths: Paths(home: home), usagePaths: Paths(), checksDaily: false)
        await store.reload()
        await store.countUsage()

        func shot(_ name: String, _ view: some View, wait: Double = 0.8) async {
            await capture(view.environment(store), name: name, size: CGSize(width: 400, height: 600), wait: wait, to: out)
        }

        await shot("01-list", RootView(route: .list))
        await shot("03-detail-bro", RootView(route: .detail("bro")))
        if let bro = store.skills.first(where: { $0.name == "bro" }) { await store.toggle(bro, .codex) }
        await shot("04-detail-bro-off", RootView(route: .detail("bro")))
        if CommandLine.arguments.contains("--quick") { exit(0) }
        store.message = nil
        await shot("05-list-after-toggle", RootView(route: .list))
        await shot("06-health", RootView(route: .health))
        await store.fix(store.issues)
        await shot("07-health-fixed", RootView(route: .health))
        store.message = nil
        await shot("07b-list-after-fix", RootView(route: .list))

        // The user pastes a link to the skill's folder, as people share skills.
        let url = "https://github.com/tornikegomareli/Skills/tree/main/product-thinking"
        await shot("08-install-empty", InstallView(route: .constant(.install)), wait: 0.4)
        await shot("09-install-pasted", InstallView(route: .constant(.install), initialURL: url, autoFetch: false), wait: 0.4)
        await shot("10-install-finding", InstallView(route: .constant(.install), initialURL: url), wait: 0.3)
        await shot("11-install-found", InstallView(route: .constant(.install), initialURL: url), wait: 45)
        if let fetched = try? await store.fetch(url) {
            await store.install(fetched.skills, from: fetched, agents: Set(Agent.allCases))
            store.discard(fetched)
        }
        await shot("12-list-installed", RootView(route: .list))
        store.message = nil
        await shot("13-list-final", RootView(route: .list))

        await capture(MenuBarStrip(), name: "menubar", size: MenuBarStrip.size, wait: 0.3, to: out)
        print("Demo states written to \(out.path)")
        exit(0)
    }

    static func capture(_ view: some View, name: String, size: CGSize, wait: Double, to dir: URL) async {
        // Offscreen windows do not run animations, so draw every state in its final position.
        let host = NSHostingView(rootView: view.tint(.blue).frame(width: size.width, height: size.height)
            .transaction { $0.animation = nil })
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)
        let window = KeyWindow(contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.backgroundColor = .clear
        window.isOpaque = false
        // Controls draw in color only in the key window of the active app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appending(path: "\(name).png"))
    }
}

/// Draws controls as they look in the focused window.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

/// The right side of a macOS menu bar, white on transparent, for the film to place over its wallpaper.
/// Layout is fixed so the film knows where the SkillsPack icon is.
struct MenuBarStrip: View {
    static let size = CGSize(width: 1600, height: 24)
    /// Center of the SkillsPack icon, in points from the left.
    static let iconCenter: CGFloat = 1600 - 10 - 132 - 34 * 6.5

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 15))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            }
            .padding(.leading, 20)
            Spacer()
            HStack(spacing: 0) {
                ForEach(["shippingbox", "display", "speaker.wave.2.fill", "battery.75percent", "wifi", "magnifyingglass", "switch.2"], id: \.self) {
                    Image(systemName: $0).frame(width: 34)
                }
                Text("Thu 8 Oct  9:41").frame(width: 132, alignment: .trailing)
            }
            .padding(.trailing, 10)
        }
        .font(.system(size: 13.5, weight: .medium))
        // Black on white; the film turns it into white on transparent.
        .foregroundStyle(.black)
        .background(.white)
    }
}
#endif
