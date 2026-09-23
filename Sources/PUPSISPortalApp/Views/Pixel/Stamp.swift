import AppKit
import SwiftUI

/// A rubber-stamp class status: display face, uppercase, 2pt border in the
/// ink color, tilted −3°, with a speckled ink mask. `landing` changing plays
/// the thunk (scale 1.9 to 0.92 to 1, blur 2 to 0, 420ms).
struct Stamp: View {
    enum Kind: CaseIterable {
        case inPerson, online, vacant

        var label: String {
            switch self {
            case .inPerson: "In person"
            case .online: "Online"
            case .vacant: "Vacant"
            }
        }
    }

    let kind: Kind
    /// The class's subject color; in-person stamps ink in it.
    var subject: Color?
    var small = false
    /// Change it to replay the thunk.
    var landing = 0
    @Environment(\.palette) private var palette
    @Environment(\.typography) private var typography
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        let ink = inkColor
        Text(kind.label.uppercased())
            .font(typography.display(size: small ? 10 : 11, weight: .bold))
            .tracking(small ? 1.2 : 1.32)
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
            .mask(Image(nsImage: Self.inkMask).resizable(resizingMode: .tile).luminanceToAlpha())
            .rotationEffect(.degrees(-3))
            .keyframeAnimator(initialValue: Thunk(), trigger: landing) { content, value in
                content.scaleEffect(value.scale).blur(radius: value.blur).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    if reduceMotion {
                        LinearKeyframe(1, duration: 0)
                    } else {
                        LinearKeyframe(1.9, duration: 0)
                        CubicKeyframe(0.92, duration: 0.23)
                        CubicKeyframe(1, duration: 0.19)
                    }
                }
                KeyframeTrack(\.blur) {
                    if reduceMotion {
                        LinearKeyframe(0, duration: 0)
                    } else {
                        LinearKeyframe(2, duration: 0)
                        CubicKeyframe(0, duration: 0.23)
                    }
                }
                KeyframeTrack(\.opacity) {
                    if reduceMotion {
                        LinearKeyframe(1, duration: 0)
                    } else {
                        LinearKeyframe(0, duration: 0)
                        CubicKeyframe(1, duration: 0.23)
                    }
                }
            }
            .accessibilityLabel(kind.label)
    }

    private var inkColor: Color {
        switch kind {
        case .inPerson: subject ?? palette.subjectColors[0]
        case .online: palette.roles.actionInk
        case .vacant: palette.roles.goldInk
        }
    }

    private struct Thunk {
        var scale = 1.0
        var blur = 0.0
        var opacity = 1.0
    }

    /// 90×90 speckle, built once: mostly solid ink with a few worn cells,
    /// seeded so every launch prints the same stamp.
    static let inkMask: NSImage = {
        let side = 90
        var seed: UInt32 = 7
        let bytes = (0..<side * side).map { _ -> UInt8 in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (seed >> 24) < 38 ? 60 : 255
        }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite,
            bytesPerRow: side, bitsPerPixel: 8
        )!
        rep.bitmapData!.update(from: bytes, count: bytes.count)
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }()
}
