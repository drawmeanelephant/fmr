import SwiftUI
import AppKit

/// Skeleton shown while `isRefreshing && repos.isEmpty && !catalogLoaded`.
/// 3 placeholder rows with `.redacted(reason: .placeholder)` and a subtle
/// opacity pulse (1.2s) — no layout jank. Must NOT be used for filtered empty
/// (that is `EmptyStateView.noSearchResults`).
public struct RedactedPlaceholderView: View {
    @State private var pulse = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 12)
                            .frame(maxWidth: .infinity)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(height: 8)
                            .frame(maxWidth: 120)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .redacted(reason: .placeholder)
                .opacity(pulse ? 0.55 : 1.0)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Compact variant for the 320pt menu bar popover.
public struct MenuBarRedactedPlaceholderView: View {
    @State private var pulse = false

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 10)
                        .frame(maxWidth: .infinity)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 50, height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .redacted(reason: .placeholder)
                .opacity(pulse ? 0.55 : 1.0)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
