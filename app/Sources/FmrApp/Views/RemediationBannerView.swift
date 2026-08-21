import SwiftUI
import AppKit

/// Dismissible banner shown above the repo list when `syncAll` / `syncRepo` refuses or fails.
/// Displays `SyncOutcome.message` and offers `Copy fix` which extracts the git command via
/// `RemediationHelper.extractFixCommand` and copies to pasteboard with `Copied ✓` feedback.
/// Dismissal persists via `fmr.dismissedRemediationId` until next distinct message.
public struct RemediationBannerView: View {
    let message: String
    var onDismiss: () -> Void
    @State private var copied = false

    public init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let fixCommand = RemediationHelper.extractFixCommand(from: message) {
                Button {
                    copyToPasteboard(fixCommand)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption2)
                        Text(copied ? "Copied ✓" : "Copy fix")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Copy: \(fixCommand)")
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss remediation banner")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: 64)
        .background(Color.orange.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remediation: \(message)")
    }

    private func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) { copied = false }
        }
    }
}

// MARK: - Inline remediation for MenuBarRepoRow

/// Compact inline remediation shown under a `MenuBarRepoRow` when that repo had a sync outcome with `refused`/`failed`.
/// Mirrors `RemediationBannerView` but compact for 320pt popover — no large background, just a single line + Copy.
public struct InlineRemediationView: View {
    let outcome: SyncOutcome
    @State private var copied = false

    public init(outcome: SyncOutcome) {
        self.outcome = outcome
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
            Text(outcome.message)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let fix = RemediationHelper.extractFixCommand(from: outcome.message) {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(fix, forType: .string)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 8))
                        Text(copied ? "Copied ✓" : "Copy fix")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
                .help("Copy: \(fix)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remediation for \(outcome.name): \(outcome.message)")
    }
}
