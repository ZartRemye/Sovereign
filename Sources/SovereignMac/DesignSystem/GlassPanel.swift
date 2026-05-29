import SwiftUI

/// Glass-morphism panel using native materials.
struct GlassPanel<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = AppSpacing.cardPadding

    init(cornerRadius: CGFloat = 20, padding: CGFloat = AppSpacing.cardPadding,
         @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
    }
}
