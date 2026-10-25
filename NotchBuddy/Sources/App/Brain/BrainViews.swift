#if !APPSTORE
import SwiftUI

// MARK: - Brain card

/// The brain at a glance: the queues and local services its `.coucou/brain.json`
/// declares, and one click to ask the brain, run a queue's command or open it.
struct BrainCardView: View {
    @ObservedObject private var brain = BrainController.shared

    private var accent: Color {
        Color(hex: PillCatalog.definition(for: BrainController.pillId)?.color ?? "#8B5CF6")
    }

    var body: some View {
        let status = brain.status
        VStack(alignment: .leading, spacing: 0) {
            header(status)
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

            Group {
                if status.lastUpdated == nil {
                    Text("Loading…")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 8)
                } else if !status.vaultConfigured {
                    notConfigured
                } else {
                    counts(status)
                    actions(status)
                }
            }
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
        .onAppear { brain.refreshIfStale() }
    }

    // MARK: Parts

    private func header(_ status: BrainStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(verbatim: "Brain")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .fixedSize()
            if status.vaultConfigured {
                ForEach(Array(status.services.filter { $0.health != nil }.enumerated()), id: \.offset) { _, service in
                    ServiceDot(name: service.name, up: service.up)
                }
            } else {
                Text("Integration")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            Spacer(minLength: 2)
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#F4505E")).frame(width: 5, height: 5)
                Text(AppState.shared.brainVaultPath.isEmpty ? LocalizedStringKey("No brain folder yet")
                                                            : LocalizedStringKey("Brain folder not found"))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
            Button("Choose it in Settings…") { BrainActions.openSettings() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accent.opacity(0.85))
                .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func counts(_ status: BrainStatus) -> some View {
        if status.counters.isEmpty {
            Text("Add .coucou/brain.json to show your queues here.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(status.counters.enumerated()), id: \.offset) { _, counter in
                    BrainStatRow(counter: counter, accent: accent)
                }
            }
            .padding(.top, 6)
        }
    }

    private func actions(_ status: BrainStatus) -> some View {
        HStack(spacing: 12) {
            Button("Ask") { BrainActions.openChat() }
                .foregroundColor(accent.opacity(0.9))
                .fixedSize()
            Button { BrainActions.openObsidian() } label: { Text(verbatim: "Obsidian") }
                .foregroundColor(Color(hex: "#8E939C"))
                .fixedSize()
            ForEach(Array(status.services.filter { $0.open != nil }.enumerated()), id: \.offset) { _, service in
                Button { BrainActions.open(service) } label: { Text(verbatim: service.name).lineLimit(1) }
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .medium))
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

/// "● Search": green when its health URL answers, grey when not, dim until probed.
/// A long name is cut short rather than pushing the header out.
private struct ServiceDot: View {
    let name: String
    let up: Bool?

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: up == true ? "#22C55E" : up == false ? "#6B7079" : "#3A3D43"))
                .frame(width: 5, height: 5)
            Text(verbatim: name)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: up == true ? "#8E939C" : "#5F646D"))
                .lineLimit(1)
        }
    }
}

/// One queue: icon, label, count and the button the config gives it.
private struct BrainStatRow: View {
    let counter: BrainStatus.Counter
    let accent: Color
    @State private var hovered = false

    private var isEmpty: Bool { (counter.value ?? 0) == 0 }
    /// A command waits on the queue, so it dims with nothing to do; a draft starts
    /// a question whatever the count. Both stay clickable.
    private var dimsWhenEmpty: Bool {
        guard case .send = counter.action?.effect else { return false }
        return true
    }
    private var icon: String { counter.kind == .notesWithoutFrontmatter ? "tray.full" : "doc.on.doc" }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(isEmpty ? Color(hex: "#6B7079") : accent)
                .frame(width: 14)
            Text(verbatim: counter.label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: counter.value.map(String.init) ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .monospacedDigit()
            // None of its folders exists: nothing for the command to work on.
            if counter.value != nil, let action = counter.action {
                Button { BrainActions.run(action) } label: {
                    Text(verbatim: action.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#E8E9EC"))
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(accent.opacity(hovered ? 0.32 : 0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(dimsWhenEmpty && isEmpty ? 0.5 : 1)
                .onHover { hovered = $0 }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
