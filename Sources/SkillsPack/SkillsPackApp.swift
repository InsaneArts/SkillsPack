import SkillsPackCore
import SwiftUI

@main
struct SkillsPackApp: App {
    @State private var store = SkillStore()

    init() {
        UpdaterService.shared.start()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            let dir = URL(filePath: CommandLine.arguments[index + 1])
            Task { @MainActor in await Snapshots.render(to: dir) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--demo-states"), index + 2 < CommandLine.arguments.count {
            let out = URL(filePath: CommandLine.arguments[index + 1])
            let home = URL(filePath: CommandLine.arguments[index + 2])
            Task { @MainActor in await DemoStates.run(out: out, home: home) }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(store)
                .frame(width: 400, height: 600)
        } label: {
            // The number of updates sits next to the icon, like a badge.
            HStack(spacing: 2) {
                Image(systemName: "shippingbox")
                if !store.updates.isEmpty { Text("\(store.updates.count)") }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

enum Route: Equatable {
    case list
    case detail(String)
    case install
    case health
}

struct RootView: View {
    @Environment(SkillStore.self) private var store
    @State private var route: Route
    private let agentFilter: AgentFilter

    init(route: Route = .list, agentFilter: AgentFilter = .all) {
        _route = State(initialValue: route)
        self.agentFilter = agentFilter
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch route {
                case .list:
                    SkillListView(route: $route, agentFilter: agentFilter)
                case .detail(let name):
                    if let skill = store.skills.first(where: { $0.name == name }) {
                        SkillDetailView(skill: skill, route: $route)
                    } else {
                        SkillListView(route: $route, agentFilter: agentFilter)
                    }
                case .install:
                    InstallView(route: $route)
                case .health:
                    HealthView(route: $route)
                }
            }
            .transition(.opacity)
            Toast()
        }
        .animation(.snappy(duration: 0.2), value: route)
        .animation(.snappy, value: store.message)
        .animation(.snappy, value: store.error)
        .onAppear {
            Task {
                await store.reload()
                await store.countUsage()
            }
        }
    }
}
