import SkillsPackCore
import SwiftUI

enum SkillFilter: String, CaseIterable, Identifiable {
    case all = "All skills"
    case claude = "Claude"
    case codex = "Codex"
    case pi = "pi"
    case off = "Turned off"
    case unused = "Never used"
    case updates = "Updates"

    var id: String { rawValue }
}

enum SkillSort: String, CaseIterable, Identifiable {
    case usage = "Most used"
    case recent = "Recently used"
    case name = "Name"

    var id: String { rawValue }
}

struct SkillListView: View {
    @Environment(SkillStore.self) private var store
    @Binding var route: Route
    @State private var query = ""
    @State private var filter = SkillFilter.all
    @State private var sort = SkillSort.usage

    var visible: [Skill] {
        let words = query.lowercased().split(separator: " ")
        let filtered = store.skills.filter { skill in
            let text = (skill.name + " " + skill.description).lowercased()
            guard words.allSatisfy({ text.contains($0) }) else { return false }
            switch filter {
            case .all: return true
            case .claude: return !skill.installations(for: .claude).isEmpty
            case .codex: return !skill.installations(for: .codex).isEmpty
            case .pi: return !skill.installations(for: .pi).isEmpty
            case .off: return Agent.allCases.contains { store.state(skill, $0) == .off }
            case .unused: return store.usage(of: skill).total == 0
            case .updates: return store.updates.contains(skill.name)
            }
        }
        switch sort {
        case .usage:
            return filtered.sorted { (store.usage(of: $0).total, $1.name) > (store.usage(of: $1).total, $0.name) }
        case .recent:
            return filtered.sorted { (store.usage(of: $0).lastUsed ?? .distantPast) > (store.usage(of: $1).lastUsed ?? .distantPast) }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            let skills = visible
            if skills.isEmpty {
                ContentUnavailableView(store.skills.isEmpty ? "Loading skills" : "No matching skills", systemImage: "shippingbox")
                    .frame(maxHeight: .infinity)
            } else {
                List(skills) { skill in
                    SkillRow(skill: skill)
                        .contentShape(Rectangle())
                        .onTapGesture { route = .detail(skill.name) }
                }
                .listStyle(.plain)
            }
            StatusBar()
            Divider()
            footer
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            TextField("Search \(store.skills.count) skills", text: $query)
                .textFieldStyle(.roundedBorder)
            Picker("Filter", selection: $filter) {
                ForEach(SkillFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SkillSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort")
            Button {
                Task { await store.checkUpdates() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .disabled(store.isCheckingUpdates)
            .help("Check for updates")
            Button {
                route = .install
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Install from URL")
        }
        .padding(10)
    }

    var footer: some View {
        HStack(spacing: 8) {
            if store.isCheckingUpdates {
                ProgressView().controlSize(.small)
                Text("Checking sources for updates…")
            } else if store.isCountingUsage {
                ProgressView().controlSize(.small)
                Text("Counting usage in session logs…")
            } else {
                Text("Usage: called by you + by the agent")
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct SkillRow: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill

    var body: some View {
        let usage = store.usage(of: skill)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(skill.name).fontWeight(.medium).lineLimit(1)
                    if store.updates.contains(skill.name) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue).help("Update available")
                    }
                }
                Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(usage.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(usage.total == 0 ? .tertiary : .secondary)
                .frame(minWidth: 22, alignment: .trailing)
                .help("Used \(usage.total) times: \(usage.byUser) by you, \(usage.byAgent) by the agent")
            HStack(spacing: 3) {
                ForEach(Agent.allCases, id: \.self) { AgentChip(skill: skill, agent: $0) }
            }
        }
        .padding(.vertical, 2)
    }
}
