import SkillsPackCore
import SwiftUI

extension Agent {
    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.25, green: 0.48, blue: 0.96)
        case .pi: Color(red: 0.58, green: 0.38, blue: 0.88)
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .pi: "terminal"
        }
    }
}

/// A rounded tile with the skill's first letter, tinted by a stable color from its name.
struct SkillIcon: View {
    let name: String
    var size: CGFloat = 30

    static let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .mint, .teal, .cyan, .brown]

    var body: some View {
        let base = name.split(separator: ":").last.map(String.init) ?? name
        let color = Self.palette[abs(base.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % Self.palette.count]
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Text(base.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: color.opacity(0.25), radius: 1, y: 0.5)
    }
}

/// Three dots, one per agent: filled when on, a ring when off, faint when not installed.
struct AgentDots: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Agent.allCases, id: \.self) { agent in
                let state = store.state(skill, agent)
                Circle()
                    .fill(state == .on ? agent.color : .clear)
                    .overlay { Circle().strokeBorder(state == .notInstalled ? Color.secondary.opacity(0.25) : agent.color, lineWidth: 1.2) }
                    .frame(width: 7, height: 7)
                    .help("\(agent.title): \(state.label)")
            }
        }
    }
}

extension AgentState {
    var label: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .notInstalled: "Not installed"
        }
    }
}

/// An inset group, like a System Settings section.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5) }
        }
    }
}

struct CardDivider: View {
    var inset: CGFloat = 12

    var body: some View { Divider().padding(.leading, inset) }
}

/// A row that shows a soft highlight on hover, like a menu item.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear)))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

/// The back button at the top of a pushed screen.
struct BackBar<Trailing: View>: View {
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                    Text("Skills")
                }
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// A short-lived message at the bottom of the window, like a system HUD.
struct Toast: View {
    @Environment(SkillStore.self) private var store

    var body: some View {
        let error = store.error
        let text = error ?? store.message
        if let text {
            HStack(spacing: 8) {
                Image(systemName: error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error == nil ? Color.green : Color.orange)
                Text(text).font(.system(size: 12)).lineLimit(3).textSelection(.enabled)
                if error != nil {
                    Button { store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: text) {
                guard error == nil else { return }
                try? await Task.sleep(for: .seconds(3))
                withAnimation { store.message = nil }
            }
        }
    }
}
