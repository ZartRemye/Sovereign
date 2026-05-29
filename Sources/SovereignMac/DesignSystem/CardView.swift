import SwiftUI

/// Reusable card container with rounded corners, shadow, and optional glass effect.
struct CardView<Content: View>: View {
    let content: Content
    var padding: CGFloat = AppSpacing.cardPadding
    var cornerRadius: CGFloat = 16
    var useGlass: Bool = false

    init(padding: CGFloat = AppSpacing.cardPadding, cornerRadius: CGFloat = 16,
         useGlass: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.useGlass = useGlass
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if useGlass {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
                }
            }
    }
}
