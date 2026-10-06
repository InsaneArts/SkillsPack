import SkillsPackCore
import SwiftUI

struct InstallView: View {
    @Environment(SkillStore.self) private var store
    @Binding var route: Route
    @State private var url = ""
    @State private var fetched: Fetched?
    @State private var selected = Set<String>()
    @State private var agents = Set(Agent.allCases)
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { close() } label: { Label("Skills", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Install from URL").font(.title3.bold())
                HStack {
                    TextField("https://github.com/owner/repo", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(fetch)
                    Button("Fetch", action: fetch)
                        .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || working)
                }
                Text("A GitHub repo, a folder link (…/tree/main/path), owner/repo, or any git URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if working {
                    HStack { ProgressView().controlSize(.small); Text("Working…").font(.caption) }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if let fetched { picker(fetched) }
                Spacer()
            }
            .padding(14)
        }
        .onDisappear { if let fetched { store.discard(fetched) } }
    }

    @ViewBuilder
    func picker(_ fetched: Fetched) -> some View {
        let installed = Set(store.skills.map(\.name))
        HStack {
            Text("\(fetched.skills.count) skills in \(fetched.source.display)").font(.headline)
            Spacer()
            if fetched.skills.count > 1 {
                Button(selected.count == fetched.skills.count ? "Select none" : "Select all") {
                    selected = selected.count == fetched.skills.count ? [] : Set(fetched.skills.map(\.id))
                }
                .buttonStyle(.borderless)
            }
        }
        List(fetched.skills) { skill in
            Toggle(isOn: Binding(
                get: { selected.contains(skill.id) },
                set: { if $0 { selected.insert(skill.id) } else { selected.remove(skill.id) } })
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(skill.name).fontWeight(.medium)
                        if installed.contains(skill.name) {
                            Text("replaces installed").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .toggleStyle(.checkbox)
        }
        .listStyle(.bordered)
        .frame(minHeight: 160)
        HStack(spacing: 12) {
            Text("Install for").font(.callout)
            ForEach(Agent.allCases, id: \.self) { agent in
                Toggle(agent.title, isOn: Binding(
                    get: { agents.contains(agent) },
                    set: { if $0 { agents.insert(agent) } else { agents.remove(agent) } }))
                .toggleStyle(.checkbox)
            }
        }
        Button("Install \(selected.count) \(selected.count == 1 ? "skill" : "skills")") { install(fetched) }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty || agents.isEmpty || working)
    }

    func fetch() {
        if let fetched { store.discard(fetched) }
        fetched = nil
        error = nil
        working = true
        Task {
            do {
                let result = try await store.fetch(url)
                fetched = result
                selected = result.skills.count == 1 ? [result.skills[0].id] : []
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    func install(_ fetched: Fetched) {
        working = true
        Task {
            await store.install(fetched.skills.filter { selected.contains($0.id) }, from: fetched, agents: agents)
            working = false
            if store.error == nil { close() }
        }
    }

    func close() {
        if let fetched { store.discard(fetched) }
        fetched = nil
        route = .list
    }
}
