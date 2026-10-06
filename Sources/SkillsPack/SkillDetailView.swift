import SkillsPackCore
import SwiftUI

struct SkillDetailView: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    @Binding var route: Route
    @State private var confirmDelete = false
    @State private var preview = ""
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { route = .list } label: { Label("Skills", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name).font(.title3.bold()).textSelection(.enabled)
                        if skill.userInvocableOnly {
                            Text("Only runs when you call it.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !skill.description.isEmpty {
                            Text(skill.description).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    usageSection
                    agentsSection
                    sourceSection
                    previewSection
                    if skill.isDeletable { deleteSection }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StatusBar()
        }
        .task(id: skill.name) {
            guard let file = skill.installations.first?.skillFile else { return }
            preview = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
    }

    var usageSection: some View {
        let usage = store.usage(of: skill)
        return Section("Usage") {
            HStack(spacing: 18) {
                stat("\(usage.byUser)", "by you")
                stat("\(usage.byAgent)", "by the agent")
                stat(usage.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "never", "last used")
            }
        }
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    var agentsSection: some View {
        Section("Agents") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Agent.allCases, id: \.self) { agent in
                    HStack(alignment: .top, spacing: 10) {
                        AgentChip(skill: skill, agent: agent)
                        VStack(alignment: .leading, spacing: 2) {
                            let installations = skill.installations(for: agent)
                            if installations.isEmpty {
                                Text("Not installed").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(installations) { installation in
                                PathLine(installation: installation)
                            }
                        }
                    }
                }
            }
        }
    }

    var sourceSection: some View {
        Section("Source") {
            VStack(alignment: .leading, spacing: 6) {
                if let plugin = pluginInfo {
                    Text("Claude plugin \(plugin.id), version \(plugin.version)").font(.callout)
                    Button("Update plugin") { act { await store.update(skill) } }.disabled(working)
                } else if let record = store.sources[skill.name] {
                    Text(record.source.display).font(.callout).textSelection(.enabled)
                    HStack(spacing: 8) {
                        if let ref = record.source.ref { Text("ref \(ref)") }
                        if let commit = record.commit { Text("commit \(commit.prefix(7))") }
                        if let date = record.installedAt { Text("installed \(date.formatted(date: .abbreviated, time: .omitted))") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(store.updates.contains(skill.name) ? "Install update" : "Update now") {
                        act { await store.update(skill) }
                    }
                    .disabled(working || !skill.isDeletable)
                } else if skill.installations.allSatisfy({ $0.root.kind == .system }) {
                    Text("Ships with Codex.").font(.callout).foregroundStyle(.secondary)
                } else if skill.installations.allSatisfy(\.isSymlink) {
                    Text("Linked from another folder. Update it there.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Unknown. Install it again from its URL to track updates.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    var pluginInfo: (id: String, version: String)? {
        for installation in skill.installations {
            if case .plugin(let id, let version) = installation.root.kind { return (id, version) }
        }
        return nil
    }

    var previewSection: some View {
        Section("SKILL.md") {
            ScrollView {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 220)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    var deleteSection: some View {
        HStack {
            if confirmDelete {
                Text("Delete every writable copy?").font(.callout)
                Spacer()
                Button("Cancel") { confirmDelete = false }
                Button("Delete", role: .destructive) {
                    act {
                        await store.delete(skill)
                        route = .list
                    }
                }
                .disabled(working)
            } else {
                Button("Delete skill", role: .destructive) { confirmDelete = true }
                Spacer()
            }
        }
    }

    func act(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content
        }
    }
}

private struct PathLine: View {
    let installation: Installation

    var body: some View {
        HStack(spacing: 4) {
            Text(display(installation.dir))
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help(installation.dir.path)
            if installation.isSymlink {
                Text("→ \(display(installation.resolvedDir))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([installation.skillFile])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
    }

    func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
