import SwiftUI

/// Liquid Glass on macOS 26+, frosted material on older systems.
private struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        }
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S) -> some View { modifier(GlassModifier(shape: shape)) }
}

/// Lets neighbouring glass shapes blend on macOS 26+; a plain passthrough elsewhere.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 0) { content } } else { content }
    }
}
