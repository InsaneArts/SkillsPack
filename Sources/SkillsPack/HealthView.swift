import SkillsPackCore
import SwiftUI

/// Problems in the skill folders, what skills cost in context, and repos to match sources from.
struct HealthView: View {
    @Environment(SkillStore.self) private var store
    @Binding var route: Route
    @State private var newRepo = ""
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            BackBar(action: { route = .list }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Health").font(.system(size: 20, weight: .bold))
                    problems
                    context
                    unused
                    sources
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Problems

    var problems: some View {
        Card(title: "PROBLEMS") {
            if store.issues.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(.green)
                    Text("No problems found.").font(.system(size: 13))
                    Spacer()
                }
                .padding(12)
            } else {
                ForEach(Array(store.issues.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 { CardDivider(inset: 40) }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: issue)).font(.system(size: 15)).foregroundStyle(.orange).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.system(size: 13, weight: .medium))
                            Text(issue.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Button("Fix") { act { await store.fix([issue]) } }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .disabled(working)
                    }
                    .padding(12)
                }
                if store.issues.count > 1 {
                    CardDivider(inset: 0)
                    Button {
                        act { await store.fix(store.issues) }
                    } label: {
                        Text("Fix All \(store.issues.count) Problems").font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: 34).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(working)
                }
            }
        }
    }

    func icon(for issue: HealthIssue) -> String {
        switch issue.kind {
        case .brokenLink: "link.badge.plus"
        case .strayFolder: "folder.badge.questionmark"
        case .differentCopies: "doc.on.doc"
        }
    }

    // MARK: Context

    var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            Card(title: "CONTEXT PER SESSION") {
                ForEach(Array(Agent.allCases.enumerated()), id: \.element) { index, agent in
                    if index > 0 { CardDivider(inset: 48) }
                    let cost = store.contextTokens(for: agent)
                    HStack(spacing: 10) {
                        AgentLogo(agent: agent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.title).font(.system(size: 13))
                            Text("\(cost.skills) skills on").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("≈ \(Self.format(cost.tokens)) tokens").font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            Text("Agents load the name and description of every skill that is on, in every session. Estimate: 4 characters per token.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Unused

    @ViewBuilder
    var unused: some View {
        let skills = store.unusedSkills
        if !skills.isEmpty {
            let total = skills.reduce(0) { $0 + ContextCost.tokens(for: $1) }
            Card(title: "NOT USED IN 90 DAYS · \(skills.count) SKILLS · ≈ \(Self.format(total)) TOKENS") {
                ForEach(Array(skills.prefix(8).enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { CardDivider(inset: 48) }
                    HStack(spacing: 10) {
                        SkillIcon(name: skill.name, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name).font(.system(size: 13)).lineLimit(1)
                            Text("≈ \(ContextCost.tokens(for: skill)) tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Turn Off") { act { await store.turnOffEverywhere([skill]) } }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .disabled(working)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { route = .detail(skill.name) }
                }
                CardDivider(inset: 0)
                Button {
                    act { await store.turnOffEverywhere(skills) }
                } label: {
                    Text("Turn Off All \(skills.count) Everywhere").font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(working)
            }
        }
    }

    // MARK: Sources

    var sources: some View {
        let unknown = store.skills.filter { $0.isDeletable && store.sources[$0.name] == nil }.count
        return VStack(alignment: .leading, spacing: 6) {
            Card(title: "SOURCE REPOS") {
                ForEach(store.repos, id: \.self) { repo in
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary).frame(width: 18)
                        Text(SourceRef.parse(repo)?.display ?? repo).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Button { act { await store.removeRepo(repo) } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    CardDivider(inset: 40)
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green).frame(width: 18)
                    TextField("Add repo, like owner/repo", text: $newRepo)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit(addRepo)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            HStack {
                Text("\(unknown) skills have no known source. SkillsPack links them to skills with the same name in these repos.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    act { await store.matchSources() }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Match") }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(working || store.repos.isEmpty)
            }
            .padding(.horizontal, 4)
        }
    }

    func addRepo() {
        let repo = newRepo
        newRepo = ""
        act { await store.addRepo(repo) }
    }

    func act(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
    }

    static func format(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1000) : "\(tokens)"
    }
}
