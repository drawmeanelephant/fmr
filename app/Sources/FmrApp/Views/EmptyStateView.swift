import SwiftUI
import AppKit

/// Reusable illustrated empty state built on `ContentUnavailableView` (macOS 14+).
/// One shared design — one SF Symbol set, one copy voice — to keep empties intentional.
///
/// Use `.compact` in the 320pt menu bar popover (no large illustration, capped height)
/// and `.regular` in the dashboard. See `docs/issues/issue-31-empty-states-and-delight.md`.
public struct EmptyStateView: View {
    public enum Style {
        case compact
        case regular
    }

    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    let style: Style

    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        style: Style = .regular
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.style = style
    }

    public var body: some View {
        Group {
            if actionTitle != nil || secondaryActionTitle != nil {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                        .font(style == .compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                } description: {
                    Text(message)
                        .font(style == .compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } actions: {
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(style == .compact ? .small : .regular)
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .controlSize(style == .compact ? .small : .regular)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                        .font(style == .compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                } description: {
                    Text(message)
                        .font(style == .compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style == .compact ? 120 : .infinity)
        .padding(style == .compact ? 8 : 12)
    }
}

// MARK: - Presets

public extension EmptyStateView {
    /// No repos configured — menu bar / dashboard sidebar when `repos.isEmpty`.
    static func noRepos(style: Style = .regular, onAdd: @escaping () -> Void, onOpenWorkspace: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            systemImage: "folder.badge.plus",
            title: "No repositories yet",
            message: "Add a repo or drag a folder to get started.",
            actionTitle: "Add Repository...",
            action: onAdd,
            secondaryActionTitle: "Open workspace.json",
            secondaryAction: onOpenWorkspace,
            style: style
        )
    }

    /// Search / filter produced no results — `model.searchQuery` non-empty.
    static func noSearchResults(query: String, style: Style = .regular, onClear: @escaping () -> Void) -> EmptyStateView {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "No matches" : "No matches for '\(trimmed)'"
        return EmptyStateView(
            systemImage: "magnifyingglass",
            title: title,
            message: "Try another filter or clear search.",
            actionTitle: "Clear Search",
            action: onClear,
            style: style
        )
    }

    /// No active Conductor session worktrees for a repo.
    static func noWorktrees(repoName: String, style: Style = .regular, onCreate: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up",
            title: "No session worktrees",
            message: "Create an isolated branch for an agent in \(repoName).",
            actionTitle: "New Worktree...",
            action: onCreate,
            style: style
        )
    }

    /// Doctor diagnostics have not yet been run.
    static func noDoctor(style: Style = .regular, onRun: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            systemImage: "stethoscope",
            title: "Diagnostics not run",
            message: "Run Doctor to check paths, branch hygiene, locks, and disk space.",
            actionTitle: "Run Doctor",
            action: onRun,
            style: style
        )
    }

    /// No recent repositories remembered.
    static func noRecents(style: Style = .regular, onBrowse: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            systemImage: "clock.arrow.circlepath",
            title: "No recent repos",
            message: "Clone a repo and open it to see it here.",
            actionTitle: onBrowse == nil ? nil : "Browse...",
            action: onBrowse,
            style: style
        )
    }

    /// Drop zone placeholder — animated when `isTargeted` (caller should add scale/border).
    static func dropReady(style: Style = .regular, isTargeted: Bool) -> EmptyStateView {
        EmptyStateView(
            systemImage: isTargeted ? "folder.badge.plus.fill" : "folder.badge.plus",
            title: isTargeted ? "Drop to add" : "Drop folder to add",
            message: "Release to pre-fill Add Repository.",
            style: style
        )
    }

    /// Detail pane when no repo is selected — keeps Cmd+K hint from spec.
    static func noSelection(style: Style = .regular, onOpenPalette: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            systemImage: "folder.badge.gearshape",
            title: "No Repository Selected",
            message: "Select a repository from the sidebar to inspect status, snapshots, and commands. Press ⌘K for the command palette.",
            actionTitle: onOpenPalette == nil ? nil : "Open Palette (⌘K)",
            action: onOpenPalette,
            style: style
        )
    }
}
