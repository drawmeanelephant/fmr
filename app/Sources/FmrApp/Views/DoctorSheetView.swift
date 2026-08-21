import SwiftUI
import AppKit

public struct DoctorSheetView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Doctor")
                        .font(.title2)
                        .bold()
                    Text("Offline diagnostic suite for paths, branch hygiene, locks, and disk space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            // Problem / Warning Counter Banner
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.doctorProblemsCount == 0 ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text("\(model.doctorProblemsCount) Problems")
                        .font(.subheadline)
                        .bold()
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(model.doctorWarningsCount == 0 ? Color.green : Color.yellow)
                        .frame(width: 10, height: 10)
                    Text("\(model.doctorWarningsCount) Warnings")
                        .font(.subheadline)
                        .bold()
                }

                Spacer()

                if !model.doctorChecks.isEmpty {
                    Button {
                        let text = model.doctorChecks.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    model.runDoctor(fix: true)
                } label: {
                    Label("Fix Issues (`fmr doctor --fix`)", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            // Checks List
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.doctorChecks.isEmpty {
                        EmptyStateView.noDoctor(style: .regular, onRun: {
                            model.runDoctor(fix: false)
                        })
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(model.doctorChecks) { check in
                            DoctorCheckRow(check: check, model: model)
                        }
                    }
                }
                .padding(18)
            }

            Divider()

            // Footer
            HStack {
                Button("Re-run Diagnostics") {
                    model.runDoctor(fix: false)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(minWidth: 540, minHeight: 440)
    }

    private func iconForCheck(_ level: String) -> String {
        switch level {
        case "ok": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "problem": return "xmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }

    private func colorForCheck(_ level: String) -> Color {
        switch level {
        case "ok": return .green
        case "warn": return .yellow
        case "problem": return .red
        default: return .blue
        }
    }
}

// MARK: - DoctorCheckRow (#33)

private struct DoctorCheckRow: View {
    let check: DoctorCheck
    @Bindable var model: WorkspaceViewModel
    @State private var isHovering = false
    @State private var copied = false
    @State private var fixCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconForCheck(check.level))
                .foregroundStyle(colorForCheck(check.level))
                .font(.subheadline)

            // Message — monospaced per spec
            Text(check.message)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)

            // Actions — visible on hover (reuse MenuBarRecentRow pattern), but always accessible via accessibility.
            if isHovering || copied || fixCopied {
                HStack(spacing: 6) {
                    // Copy button — always for any row
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(check.message, forType: .string)
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption2)
                            Text(copied ? "Copied ✓" : "Copy")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy diagnostic line")

                    // Fix button — only for problem + fixable + resolvable repo
                    if shouldShowFix {
                        Button {
                            performFix()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.caption2)
                                Text(fixCopied ? "Copied ✓" : "Fix")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help(fixHelp)
                    }
                }
            } else {
                // Reserve space to avoid layout shift — show subtle dot
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .padding(10)
        .background(isHovering ? Color(NSColor.selectedControlColor).opacity(0.08) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.level): \(check.message)")
    }

    private var repoName: String? {
        model.doctorFixableRepoName(from: check.message)
    }

    private var isUrlMismatch: Bool {
        model.isUrlMismatchMessage(check.message)
    }

    private var isNotARepo: Bool {
        model.isNotARepoMessage(check.message)
    }

    private var shouldShowFix: Bool {
        guard check.level == "problem" else { return false }
        guard let repo = repoName else { return false }
        // Only url mismatch and not_a_repo are explicitly fixable via GUI per #33.
        // Stale lock is handled by the footer Fix Issues button; we still show Fix for stale lock if repo resolvable.
        let msg = check.message.lowercased()
        if msg.contains("url mismatch") { return true }
        if msg.contains("not a git repo") || msg.contains("not_a_repo") { return true }
        if msg.contains("stale lock") || msg.contains("stale staging") { return true }
        // Defense: if message contains a fix command and repo is resolvable, allow Fix
        if RemediationHelper.extractFixCommand(from: check.message) != nil && !repo.isEmpty { return true }
        return false
    }

    private var fixHelp: String {
        if isUrlMismatch { return "Fix url mismatch via fmr sync --fix-origin" }
        if isNotARepo { return "Open in Finder and copy fmr sync command" }
        return "Attempt fix"
    }

    private func performFix() {
        guard let repo = repoName else { return }
        if isUrlMismatch {
            model.fixUrlMismatch(for: repo)
        } else if isNotARepo {
            // Never delete checkout via shell — just open Finder and copy hint.
            let path = model.repos.first(where: { $0.name == repo })?.resolvedPath
                ?? model.catalog[repo]?.path
                ?? "\(model.reposRoot)/\(repo)"
            model.openIn(editor: .finder, path: path)
            let hint = "fmr sync \(repo)"
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hint, forType: .string)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            withAnimation { fixCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { fixCopied = false }
            }
        } else {
            // Generic: try doctor --fix then refresh
            model.runDoctor(fix: true)
        }
    }

    private func iconForCheck(_ level: String) -> String {
        switch level {
        case "ok": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "problem": return "xmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }

    private func colorForCheck(_ level: String) -> Color {
        switch level {
        case "ok": return .green
        case "warn": return .yellow
        case "problem": return .red
        default: return .blue
        }
    }
}
