import SwiftUI

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
                        Text("No diagnostics run yet. Click 'Fix Issues' or 'Re-run' below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 30)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(model.doctorChecks) { check in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: iconForCheck(check.level))
                                    .foregroundStyle(colorForCheck(check.level))
                                    .font(.subheadline)

                                Text(check.message)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
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
