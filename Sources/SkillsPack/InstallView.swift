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
    /// Debug snapshots start with a URL and fetch it on appear.
    var initialURL = ""
    var autoFetch = true
    var initialSelection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            BackBar(action: close) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    urlField
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if let fetched { results(fetched) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            if let fetched { installBar(fetched) }
        }
        .onDisappear { if let fetched { store.discard(fetched) } }
        .onAppear {
            if !initialURL.isEmpty, url.isEmpty {
                url = initialURL
                if autoFetch { fetch() }
            }
        }
    }

    var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.blue.opacity(0.8), .blue], startPoint: .top, endPoint: .bottom))
                .frame(width: 60, height: 60)
                .overlay { Image(systemName: "arrow.down").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Add Skills").font(.system(size: 17, weight: .semibold))
                Text("Paste a GitHub link, owner/repo, or any git URL.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("github.com/owner/repo", text: $url)
                .textFieldStyle(.plain)
                .onSubmit(fetch)
            if working {
                ProgressView().controlSize(.small)
            } else {
                Button("Find", action: fetch)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(.system(size: 13))
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    func results(_ fetched: Fetched) -> some View {
        let installed = Set(store.skills.map(\.name))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(fetched.skills.count) IN \(fetched.source.display.uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if fetched.skills.count > 1 {
                    let all = selected.count == fetched.skills.count
                    Button(all ? "Select None" : "Select All") {
                        selected = all ? [] : Set(fetched.skills.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 4)
            Card {
                ForEach(Array(fetched.skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { CardDivider(inset: 72) }
                    Button {
                        if selected.contains(skill.id) { selected.remove(skill.id) } else { selected.insert(skill.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(skill.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(selected.contains(skill.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                            SkillIcon(name: skill.name, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(skill.name).font(.system(size: 13, weight: .medium))
                                    if installed.contains(skill.name) {
                                        Text("Installed").font(.system(size: 10)).foregroundStyle(.orange)
                                    }
                                }
                                Text(skill.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("INSTALL FOR")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 10)
            HStack(spacing: 8) {
                ForEach(Agent.allCases, id: \.self) { agent in
                    let on = agents.contains(agent)
                    Button {
                        if on { agents.remove(agent) } else { agents.insert(agent) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: on ? "checkmark" : agent.symbol).font(.system(size: 10, weight: .bold))
                            Text(agent.title).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(on ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(on ? AnyShapeStyle(agent.color.gradient) : AnyShapeStyle(.fill.tertiary), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func installBar(_ fetched: Fetched) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                install(fetched)
            } label: {
                Text(selected.isEmpty ? "Select Skills to Install" : "Install \(selected.count) \(selected.count == 1 ? "Skill" : "Skills")")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty || agents.isEmpty || working)
            .padding(12)
        }
        .background(.bar)
    }

    func fetch() {
        if let fetched { store.discard(fetched) }
        fetched = nil
        error = nil
        working = true
        Task {
            do {
                let result = try await store.fetch(url)
                withAnimation(.snappy) {
                    fetched = result
                    selected = result.skills.count == 1 ? [result.skills[0].id] : []
                    if !initialSelection.isEmpty {
                        selected = Set(result.skills.filter { initialSelection.contains($0.name) }.map(\.id))
                    }
                }
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
