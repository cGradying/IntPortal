import SwiftUI

/// Reports how far a `ScrollView`'s content has scrolled past its own top
/// edge — 0 (or positive) means pinned at the top, negative once scrolled
/// down. The version-independent stand-in for `onScrollGeometryChange`
/// (macOS 15+): this app's deployment target is `.macOS(.v14)`
/// (`Package.swift`), where that API would need an availability branch and
/// silently do nothing anyway.
private struct ScrollTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Apply to a `ScrollView`'s outermost content view; `space` must match
    /// a `.coordinateSpace(.named(space))` placed on the `ScrollView` itself.
    func trackScrollTop(space: String, onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ScrollTopOffsetKey.self, value: proxy.frame(in: .named(space)).minY)
            }
        )
        .onPreferenceChange(ScrollTopOffsetKey.self, perform: onChange)
    }
}
