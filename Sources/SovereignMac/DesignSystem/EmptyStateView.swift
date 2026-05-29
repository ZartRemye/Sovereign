import SwiftUI

/// Empty state placeholder for pages with no data.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(title)
                .font(AppTypography.title3)
                .foregroundColor(.secondary)

            Text(message)
                .font(AppTypography.callout)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Text(label)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
