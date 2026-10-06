import SkillsPackCore
import SwiftUI

@main
struct SkillsPackApp: App {
    @State private var store = SkillStore()

    init() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            let dir = URL(filePath: CommandLine.arguments[index + 1])
            Task { @MainActor in await Snapshots.render(to: dir) }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra("SkillsPack", systemImage: "shippingbox") {
            RootView()
                .environment(store)
                .frame(width: 480, height: 640)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Route: Equatable {
    case list
    case detail(String)
    case install
}

struct RootView: View {
    @Environment(SkillStore.self) private var store
    @State private var route: Route

    init(route: Route = .list) {
        _route = State(initialValue: route)
    }

    var body: some View {
        Group {
            switch route {
            case .list:
                SkillListView(route: $route)
            case .detail(let name):
                if let skill = store.skills.first(where: { $0.name == name }) {
                    SkillDetailView(skill: skill, route: $route)
                } else {
                    SkillListView(route: $route)
                }
            case .install:
                InstallView(route: $route)
            }
        }
        .onAppear {
            Task {
                await store.reload()
                await store.countUsage()
            }
        }
    }
}

extension Agent {
    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.25, green: 0.45, blue: 0.95)
        case .pi: Color(red: 0.55, green: 0.36, blue: 0.85)
        }
    }
}

/// One agent's switch for a skill: filled when on, struck through when off, dashed when not installed.
struct AgentChip: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let agent: Agent

    var body: some View {
        let state = store.state(skill, agent)
        Button {
            Task { await store.toggle(skill, agent) }
        } label: {
            Text(agent.title)
                .font(.system(size: 10, weight: .semibold))
                .strikethrough(state == .off)
                .foregroundStyle(state == .on ? Color.white : Color.secondary.opacity(state == .off ? 1 : 0.6))
                .frame(width: 46, height: 19)
                .background(RoundedRectangle(cornerRadius: 5).fill(state == .on ? agent.color : Color.clear))
                .overlay {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(
                        Color.secondary.opacity(state == .on ? 0 : state == .off ? 0.7 : 0.35),
                        style: StrokeStyle(lineWidth: 1, dash: state == .notInstalled ? [2, 2] : []))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help(for: state))
    }

    func help(for state: AgentState) -> String {
        switch state {
        case .on: "On in \(agent.title). Click to turn off."
        case .off: "Off in \(agent.title). Click to turn on."
        case .notInstalled: "Not installed for \(agent.title). Click to install."
        }
    }
}

/// The last action's result, shown at the bottom of every screen.
struct StatusBar: View {
    @Environment(SkillStore.self) private var store

    var body: some View {
        if let error = store.error {
            line(error, systemImage: "exclamationmark.triangle.fill", color: .red) { store.error = nil }
        } else if let message = store.message {
            line(message, systemImage: "checkmark.circle.fill", color: .green) { store.message = nil }
        }
    }

    func line(_ text: String, systemImage: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
    }
}
