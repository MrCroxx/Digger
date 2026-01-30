import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(UIStrings.Welcome.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(UIStrings.Welcome.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                PermissionRow(
                    title: UIStrings.Welcome.accessibilityTitle,
                    description: UIStrings.Welcome.accessibilityDescription,
                    granted: viewModel.status.accessibility,
                    actionTitle: UIStrings.Welcome.openAccessibilityButton
                ) {
                    SystemPreferencesLinks.openAccessibility()
                }
                TipRow(
                    title: UIStrings.Welcome.lookupDataDetectorsTitle,
                    description: UIStrings.Welcome.lookupDataDetectorsDescription,
                    actionTitle: UIStrings.Welcome.openTrackpadButton
                ) {
                    SystemPreferencesLinks.openTrackpad()
                }
                Toggle(UIStrings.Welcome.skipNextTimeLabel, isOn: $viewModel.skipWelcomeWhenReady)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            Spacer()

            HStack {
                Text(viewModel.status.allGranted ? UIStrings.Welcome.statusReady : UIStrings.Welcome.statusMissing)
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.status.allGranted ? .secondary : .orange)
                Spacer()
                Button(UIStrings.Welcome.startButton) {
                    onStart()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
                .font(.system(size: 18))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle) {
                action()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }
}

private struct TipRow: View {
    let title: String
    let description: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 18))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle) {
                action()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }
}
