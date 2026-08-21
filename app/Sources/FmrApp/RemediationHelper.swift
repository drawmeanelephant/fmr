import Foundation

/// Helper for extracting actionable fix commands from `SyncOutcome.message` and `DoctorCheck.message`.
/// Spec regex from #33: `/(git -C "[^"]+" remote set-url[^\n]+|git -C \S+ status|fmr sync \S+)/` — case-sensitive, first match wins.
public enum RemediationHelper {
    /// Pattern scoped to a single line — see `docs/issues/issue-33-*.md`.
    /// - `git -C "quoted path" remote set-url ...` (quoted path with spaces)
    /// - `git -C /unquoted/path status`
    /// - `fmr sync <repo>`
    static let fixCommandPattern = #"git -C "[^"]+" remote set-url[^\n]+|git -C \S+ status|fmr sync \S+"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: fixCommandPattern, options: [])
    }()

    /// Extracts the first fix command substring from a message, if any.
    public static func extractFixCommand(from message: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, options: [], range: range),
              let swiftRange = Range(match.range, in: message) else {
            return nil
        }
        // Trim trailing punctuation that sometimes follows the command in prose.
        var cmd = String(message[swiftRange])
        // Remove trailing period/comma if accidentally captured (should not due to \S but be safe).
        while let last = cmd.last, ".),;".contains(last) {
            cmd.removeLast()
        }
        return cmd.isEmpty ? nil : cmd
    }

    /// Whether a message contains a fixable pattern for the Doctor sheet.
    public static func isFixableDoctorMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("url mismatch") || lower.contains("not a git repo") || lower.contains("stale lock")
    }
}
