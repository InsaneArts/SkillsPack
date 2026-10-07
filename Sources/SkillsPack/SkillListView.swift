import SkillsPackCore
import SwiftUI

enum AgentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case claude = "Claude"
    case codex = "Codex"
    case pi = "pi"

    var id: String { rawValue }
    var agent: Agent? { Agent(rawValue: rawValue.lowercased()) }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case any = "All Skills"
    case off = "Turned Off"
    case unused = "Never Used"
    case updates = "Updates Available"

    var id: String { rawValue }
}

enum SkillSort: String, CaseIterable, Identifiable {
    case usage = "Most Used (90 Days)"
    case recent = "Recently Used"
    case name = "Name"

    var id: String { rawValue }
}

struct SkillListView: View {
    @Environment(SkillStore.self) private var store
    @Binding var route: Route
    @State private var query = ""
    @State private var agentFilter: AgentFilter
    @State private var status = StatusFilter.any
    @State private var sort = SkillSort.usage

    init(route: Binding<Route>, agentFilter: AgentFilter = .all) {
        _route = route
        _agentFilter = State(initialValue: agentFilter)
    }

    var visible: [Skill] {
        let words = query.lowercased().split(separator: " ")
        let filtered = store.skills.filter { skill in
            let text = (skill.name + " " + skill.description).lowercased()
            guard words.allSatisfy({ text.contains($0) }) else { return false }
            if let agent = agentFilter.agent, skill.installations(for: agent).isEmpty { return false }
            switch status {
            case .any: return true
            case .off: return Agent.allCases.contains { store.state(skill, $0) == .off }
            case .unused: return store.usage(of: skill).total == 0
            case .updates: return store.updates.contains(skill.name)
            }
        }
        switch sort {
        case .usage:
            // Most used in the last 90 days first, then all-time uses, then name.
            return filtered.sorted {
                let a = store.usage(of: $0), b = store.usage(of: $1)
                return (a.recent, a.total, $1.name) > (b.recent, b.total, $0.name)
            }
        case .recent:
            return filtered.sorted { (store.usage(of: $0).lastUsed ?? .distantPast) > (store.usage(of: $1).lastUsed ?? .distantPast) }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            let skills = visible
            if skills.isEmpty {
                ContentUnavailableView {
                    Label(store.skills.isEmpty ? "Loading Skills" : "No Skills", systemImage: "shippingbox")
                } description: {
                    if !store.skills.isEmpty { Text("Try another search or filter.") }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !store.issues.isEmpty, status == .any, query.isEmpty {
                            banner(icon: "exclamationmark.triangle.fill", color: .orange,
                                   title: "\(store.issues.count) \(store.issues.count == 1 ? "Problem" : "Problems") Found",
                                   detail: "Broken links, skills no agent loads, or copies that differ.") { route = .health }
                        }
                        if !store.updates.isEmpty, status == .any, query.isEmpty {
                            banner(icon: "arrow.down.circle.fill", color: .blue,
                                   title: "\(store.updates.count) \(store.updates.count == 1 ? "Update" : "Updates") Available",
                                   detail: "Show skills with a newer version at their source.") { status = .updates }
                        }
                        ForEach(skills) { skill in
                            SkillRow(skill: skill) { route = .detail(skill.name) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 56)
                }
                .scrollIndicators(.never)
            }
        }
    }

    var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skills").font(.system(size: 20, weight: .bold))
                    subtitle
                }
                Spacer()
                HStack(spacing: 6) {
                    CircleButton(systemImage: "stethoscope", help: "Health and context") { route = .health }
                    CircleButton(systemImage: "plus", help: "Add skills from a URL") { route = .install }
                    moreMenu
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Picker("Agent", selection: $agentFilter) {
                ForEach(AgentFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    var subtitle: some View {
        HStack(spacing: 5) {
            if store.isCheckingUpdates {
                ProgressView().controlSize(.mini)
                Text("Checking for updates…")
            } else if store.isCountingUsage {
                ProgressView().controlSize(.mini)
                Text("Counting usage…")
            } else {
                let off = store.skills.filter { skill in Agent.allCases.contains { store.state(skill, $0) == .off } }.count
                Text("\(store.skills.count) installed" + (off > 0 ? " · \(off) turned off" : ""))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    var moreMenu: some View {
        Menu {
            Picker("Show", selection: $status) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Sort By", selection: $sort) {
                ForEach(SkillSort.allCases) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Button("Health and Context") { route = .health }
            Button("Check for Updates") { Task { await store.checkUpdates() } }
                .disabled(store.isCheckingUpdates)
            Button("Recount Usage") { Task { await store.countUsage() } }
                .disabled(store.isCountingUsage)
            Divider()
            Button("Quit SkillsPack") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.fill.tertiary, in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    func banner(icon: String, color: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }
}

struct CircleButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.fill.tertiary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SkillRow: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let open: () -> Void

    var body: some View {
        let usage = store.usage(of: skill)
        Button(action: open) {
            HStack(spacing: 10) {
                SkillIcon(name: skill.name, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(skill.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if store.updates.contains(skill.name) {
                            Text("UPDATE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(.blue, in: Capsule())
                        }
                    }
                    Text(skill.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    AgentDots(skill: skill)
                    Text(usageLabel(usage))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help("\(usage.recent) uses in the last 90 days, \(usage.total) in total")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .contextMenu { contextMenu }
    }

    /// Recent uses, or when the skill was last used if that was more than 90 days ago.
    func usageLabel(_ usage: Usage) -> String {
        if usage.recent > 0 { return "\(usage.recent) \(usage.recent == 1 ? "use" : "uses")" }
        guard let last = usage.lastUsed else { return "Unused" }
        return "Last " + last.formatted(.dateTime.month(.abbreviated).year())
    }

    @ViewBuilder
    var contextMenu: some View {
        ForEach(Agent.allCases, id: \.self) { agent in
            switch store.state(skill, agent) {
            case .on: Button("Turn Off in \(agent.title)") { Task { await store.toggle(skill, agent) } }
            case .off: Button("Turn On in \(agent.title)") { Task { await store.toggle(skill, agent) } }
            case .notInstalled: Button("Install for \(agent.title)") { Task { await store.toggle(skill, agent) } }
            }
        }
        if let first = skill.installations.first {
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first.skillFile]) }
        }
    }
}
