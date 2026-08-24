import SwiftUI

extension View {
    /// Browser-style page zoom: lays `self` out in a box scaled inversely
    /// to `scale` (so content actually reflows — more/less fits per line,
    /// exactly like a browser at a different zoom level — never a blurry
    /// stretched bitmap), then visually scales it back to fill the real
    /// available space.
    func uiScaled(_ scale: Double) -> some View {
        GeometryReader { proxy in
            self
                .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                // topLeading matches GeometryReader's own child alignment —
                // the default .center anchor scaled the whole thing off its
                // origin, clipping content and moving hit-testing away from
                // what's drawn. No outer .frame reapplied after: at this
                // anchor the scaled result already fills proxy.size exactly.
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}
