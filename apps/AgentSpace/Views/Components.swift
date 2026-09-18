import SwiftUI
import AgentSpaceCore

/// Small, shared pieces. Kept plain on purpose: plan §27 asks for native macOS,
/// minimal, no gradients and no gamified dashboard, in the register of System
/// Settings and OrbStack.

/// The status dot from the plan's §27 sketch. Colour carries the meaning, and the
/// text label always accompanies it so colour is never the only signal.
struct StatusDot: View {
    var state: SpaceState

    private var color: Color {
        switch state {
        case .ready, .running: return .green
        case .console: return .orange
        case .needsLogin, .needsPermission: return .yellow
        case .offline, .error: return .red
        case .created: return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            .accessibilityLabel(state.displayName)
    }
}

/// A bordered group, matching the detail panes in System Settings.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// One key/value line inside a `Card`.
struct Field: View {
    var label: String
    var value: String
    var monospaced: Bool = false
    var tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// A permission chip. Two states only — granted or not — because a "maybe" is
/// what the whole fail-closed design exists to avoid.
struct PermissionChip: View {
    var name: String
    var granted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(name)
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((granted ? Color.green : Color.orange).opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(granted ? "granted" : "not granted")")
    }
}

/// Why an operation did not happen, and what to do about it.
///
/// Always shows the code as well as the sentence. A user reporting a problem, and
/// an agent reading a screenshot of this window, both need the stable name.
struct RefusalBanner: View {
    var title: String
    var code: String
    var message: String
    var fix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let fix {
                Text(fix)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

/// The empty state before any Space exists. It has to explain the one fact that
/// makes AgentSpace different from every other tool with a "New" button: making a
/// Space makes a macOS user, which needs an administrator.
struct EmptyStateView: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Agent Spaces")
                .font(.title3.weight(.semibold))
            Text("An Agent Space is a separate macOS user with its own desktop, so an agent can work without touching your keyboard, mouse or screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Create Agent Space…", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
