import SkillsPackCore
import SwiftUI

struct SkillDetailView: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    @Binding var route: Route
    @State private var confirmDelete = false
    @State private var preview = ""
    @State private var showPreview = false
    @State private var expanded = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            BackBar(action: { route = .list }) { moreMenu }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsStrip
                    agentsCard
                    infoCard
                    instructionsCard
                    if skill.isDeletable { deleteCard }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.never)
        }
        .task(id: skill.name) {
            guard let file = skill.installations.first?.skillFile else { return }
            preview = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                SkillIcon(name: skill.name, size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name).font(.system(size: 17, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    Text(sourceLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    primaryButton.padding(.top, 3)
                }
            }
            if !skill.description.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled)
                    if skill.description.count > 160 {
                        Button(expanded ? "Less" : "More") { withAnimation(.snappy) { expanded.toggle() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    var sourceLine: String {
        if let plugin = pluginInfo { return "Claude plugin · \(plugin.id.split(separator: "@").first ?? "")" }
        if let record = store.sources[skill.name] { return record.source.display }
        if skill.installations.allSatisfy({ $0.root.kind == .system }) { return "Built into Codex" }
        if skill.installations.allSatisfy(\.isSymlink) { return "Linked from another folder" }
        return "Local skill"
    }

    @ViewBuilder
    var primaryButton: some View {
        if pluginInfo != nil || store.sources[skill.name] != nil {
            let hasUpdate = store.updates.contains(skill.name)
            Button {
                act { await store.update(skill) }
            } label: {
                Group {
                    if working { ProgressView().controlSize(.small) } else { Text(hasUpdate ? "Update" : pluginInfo != nil ? "Update Plugin" : "Reinstall") }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(hasUpdate ? .blue : .secondary.opacity(0.35))
            .foregroundStyle(hasUpdate ? .white : .primary)
            .controlSize(.small)
            .disabled(working || (pluginInfo == nil && !skill.isDeletable))
        }
    }

    // MARK: Stats

    var statsStrip: some View {
        let usage = store.usage(of: skill)
        return HStack(spacing: 0) {
            stat("90 Days", "\(usage.recent)")
            Divider().frame(height: 30)
            stat("All Time", "\(usage.total)", caption: "\(usage.byUser) you · \(usage.byAgent) agent")
            Divider().frame(height: 30)
            stat("Last Used", usage.lastUsed.map { $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) } ?? "Never")
        }
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func stat(_ label: String, _ value: String, caption: String? = nil) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            if let caption { Text(caption).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Agents

    var agentsCard: some View {
        Card(title: "AGENTS") {
            ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                if index > 0 { CardDivider(inset: 48) }
                AgentRow(skill: skill, agent: agent)
            }
        }
    }

    // MARK: Information

    var infoCard: some View {
        Card(title: "INFORMATION") {
            if let plugin = pluginInfo {
                InfoRow(label: "Plugin", value: plugin.id)
                CardDivider()
                InfoRow(label: "Version", value: plugin.version)
            } else if let record = store.sources[skill.name] {
                InfoRow(label: "Source", value: record.source.display)
                if let ref = record.source.ref {
                    CardDivider()
                    InfoRow(label: "Branch", value: ref)
                }
                if let commit = record.commit {
                    CardDivider()
                    InfoRow(label: "Commit", value: String(commit.prefix(7)), monospaced: true)
                }
                if let date = record.installedAt {
                    CardDivider()
                    InfoRow(label: "Installed", value: date.formatted(date: .abbreviated, time: .omitted))
                }
            } else {
                InfoRow(label: "Source", value: "Unknown")
                CardDivider()
                Text("Add this skill again from its URL to get updates.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            CardDivider()
            InfoRow(label: "Invocation", value: skill.userInvocableOnly ? "Only when you call it" : "You or the agent")
            CardDivider()
            InfoRow(label: "Context cost", value: skill.userInvocableOnly ? "None" : "≈ \(ContextCost.tokens(for: skill)) tokens per session")
        }
    }

    var pluginInfo: (id: String, version: String)? {
        for installation in skill.installations {
            if case .plugin(let id, let version) = installation.root.kind { return (id, version) }
        }
        return nil
    }

    // MARK: Instructions

    var instructionsCard: some View {
        Card(title: "INSTRUCTIONS") {
            Button {
                withAnimation(.snappy) { showPreview.toggle() }
            } label: {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text("SKILL.md").font(.system(size: 13))
                    Spacer()
                    Text("\(preview.split(separator: "\n", omittingEmptySubsequences: false).count) lines").font(.system(size: 11)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showPreview ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showPreview {
                CardDivider(inset: 0)
                ScrollView {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: Delete

    var deleteCard: some View {
        Card {
            if confirmDelete {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete “\(skill.name)”?").font(.system(size: 13, weight: .semibold))
                    Text("Its folders move to the Trash. Symlinks are removed, and their targets stay.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel") { confirmDelete = false }.controlSize(.small)
                        Button("Delete", role: .destructive) {
                            act {
                                await store.delete(skill)
                                route = .list
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(working)
                    }
                }
                .padding(12)
            } else {
                Button {
                    withAnimation(.snappy) { confirmDelete = true }
                } label: {
                    Text("Delete Skill…")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var moreMenu: some View {
        Menu {
            if let first = skill.installations.first {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([first.skillFile]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(first.dir.path, forType: .string)
                }
            }
            if skill.isDeletable {
                Divider()
                Button("Delete Skill…", role: .destructive) { withAnimation(.snappy) { confirmDelete = true } }
            }
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

    func act(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
    }
}

/// One agent: an icon, where the skill lives, and a switch (or Install when it is missing).
private struct AgentRow: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let agent: Agent

    var body: some View {
        let state = store.state(skill, agent)
        let installations = skill.installations(for: agent)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(agent.color.gradient)
                .frame(width: 26, height: 26)
                .overlay { Image(systemName: agent.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title).font(.system(size: 13))
                Text(installations.first.map { location($0) } ?? "Not installed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(installations.map(\.dir.path).joined(separator: "\n"))
            }
            Spacer(minLength: 8)
            if state == .notInstalled {
                Button("Install") { Task { await store.toggle(skill, agent) } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { state == .on },
                    set: { _ in Task { await store.toggle(skill, agent) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(agent.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func location(_ installation: Installation) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = installation.dir.path.hasPrefix(home) ? "~" + installation.dir.path.dropFirst(home.count) : installation.dir.path
        return installation.isSymlink ? path + " (link)" : path
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
    }
}
