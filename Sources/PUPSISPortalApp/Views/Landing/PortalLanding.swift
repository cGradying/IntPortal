import SwiftUI

/// One frame on the hub ring. Only PUP SIS is live; the others are
/// placeholders for systems that aren't connected and never do anything else.
struct HubPortal: Identifiable, Equatable {
    let id: String
    let live: Bool
    static let all = [HubPortal(id: "sis", live: true), HubPortal(id: "l1", live: false), HubPortal(id: "l2", live: false), HubPortal(id: "l3", live: false)]
}

/// Launch: the void, a portal assembling where the student stands, sign in
/// beside it or step straight in, orbit the hub, and warp into the app.
struct PortalLanding: View {
    @ObservedObject var appState: AppState
    @ObservedObject var portal: PortalController
    @ObservedObject var preferences: Preferences
    /// ⌘0 from the app: the hub with the frame already built.
    var quick = false
    let onDone: () -> Void
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.typography) private var typography

    @State private var start = Date()
    @State private var warpStart: Date?
    @State private var ring = 0
    @State private var hint: String?
    @State private var shake = 0
    @State private var submitted = false
    /// Once the intro has played, the scene is still: only the motes and the
    /// swirl move, on their own slower clocks, so the main one can stop.
    @State private var settled = false
    @FocusState private var focused: Bool

    /// Stays on the sign-in panel after a submit until the SIS says yes.
    private var signedIn: Bool {
        guard appState.credentials != nil, !appState.isEditing else { return false }
        return !submitted || portal.status == .success
    }

    private var failure: String? {
        if case .failed(let message) = portal.status { message } else { nil }
    }

    private var front: HubPortal { HubPortal.all[OrbitRing<HubPortal, EmptyView>.wrap(ring, HubPortal.all.count)] }

    var body: some View {
        TimelineView(.animation(paused: settled && warpStart == nil)) { context in
            let t = context.date.timeIntervalSince(start)
            let phase = LandingSequence(signedIn: signedIn, reduceMotion: reduceMotion, playIntro: preferences.playPortalIntro && !quick)
                .phase(elapsed: t, warpStartedAt: warpStart.map { $0.timeIntervalSince(start) })
            LandingStage(
                phase: phase, time: t, ring: $ring, hint: hint, shake: shake,
                liveSubtitle: liveSubtitle, signingIn: portal.status == .loggingIn,
                signedInAs: appState.credentials?.studentNumber,
                existing: appState.credentials, failure: submitted ? failure : nil,
                onSave: { credentials in
                    submitted = true
                    return appState.save(credentials)
                },
                onSelect: select,
                onSwitchAccount: { submitted = false; appState.isEditing = true },
                onSettings: { appState.showingSettings = true }
            )
        }
        .background(VoidPalette.top)
        .ignoresSafeArea()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { primaryAction() }
        .onKeyPress(.leftArrow) { orbit(-1) }
        .onKeyPress(.rightArrow) { orbit(1) }
        .onAppear { focused = true }
        .task(id: start) {
            settled = false
            let intro = preferences.playPortalIntro && !quick && !reduceMotion ? LandingSequence.igniteEnd : 0
            let remaining = intro - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 0.1)) }
            settled = true
        }
        .task(id: warpStart) {
            guard warpStart != nil else { return }
            let seconds = reduceMotion ? LandingSequence.reducedWarpDone : LandingSequence.warpDone
            try? await Task.sleep(for: .seconds(seconds))
            appState.open(.today)
            onDone()
        }
    }

    private var liveSubtitle: String {
        if portal.status == .loggingIn { return "Signing in…" }
        if portal.refreshError != nil, let updated = portal.lastUpdated {
            return "offline · cached \(updated.formatted(date: .omitted, time: .shortened))"
        }
        return "via \(portal.hostLabel)"
    }

    // MARK: Actions

    private func currentPhase() -> LandingPhase {
        LandingSequence(signedIn: signedIn, reduceMotion: reduceMotion, playIntro: preferences.playPortalIntro && !quick)
            .phase(elapsed: Date().timeIntervalSince(start), warpStartedAt: warpStart.map { $0.timeIntervalSince(start) })
    }

    private func primaryAction() -> KeyPress.Result {
        switch currentPhase() {
        case .void, .forming, .ignite:
            start = start.addingTimeInterval(-LandingSequence.skip)
            return .handled
        case .hub:
            enterFront()
            return .handled
        default:
            return .ignored
        }
    }

    private func orbit(_ step: Int) -> KeyPress.Result {
        guard currentPhase() == .hub else { return .ignored }
        ring += step
        hint = nil
        return .handled
    }

    private func select(_ item: HubPortal) {
        guard currentPhase() == .hub, let index = HubPortal.all.firstIndex(of: item) else { return }
        let count = HubPortal.all.count
        let delta = ((index - OrbitRing<HubPortal, EmptyView>.wrap(ring, count)) % count + count) % count
        if delta == 0 { enterFront() } else { ring += delta <= count / 2 ? delta : delta - count }
    }

    private func enterFront() {
        guard front.live else {
            withAnimation(.linear(duration: reduceMotion ? 0 : 0.35)) { shake += 1 }
            hint = "That portal is not connected yet. Only PUP SIS is live."
            return
        }
        guard warpStart == nil else { return }
        warpStart = Date()
        appState.warpingIn = true
    }
}

/// Everything the landing draws for one phase and moment: the void, the
/// ring of portals on the platform, the student, the flash, and the chrome
/// (wordmark, account line, sign-in panel, hint). Plain values in, so a
/// snapshot can pin any beat.
struct LandingStage: View {
    let phase: LandingPhase
    let time: Double
    @Binding var ring: Int
    var hint: String?
    var shake = 0
    var liveSubtitle: String
    var signingIn = false
    var signedInAs: String?
    var existing: Credentials?
    var failure: String?
    let onSave: (Credentials) -> Bool
    let onSelect: (HubPortal) -> Void
    let onSwitchAccount: () -> Void
    let onSettings: () -> Void
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.typography) private var typography
    @Environment(\.controlActiveState) private var activeState

    private var front: HubPortal { HubPortal.all[OrbitRing<HubPortal, EmptyView>.wrap(ring, HubPortal.all.count)] }
    /// Motes and the swirl hold still while the window isn't key.
    private var still: Bool { reduceMotion || activeState == .inactive }

    var body: some View {
        GeometryReader { geo in
            scene(phase: phase, time: time, size: geo.size)
        }
        .background(VoidPalette.top)
    }

    // MARK: Scene

    @ViewBuilder
    private func scene(phase: LandingPhase, time: Double, size: CGSize) -> some View {
        let block = max(12, (min(size.width / 24, size.height / 17)).rounded())
        let shift: CGFloat = phase == .signIn && size.width > 760 ? -size.width * 0.16 : 0
        let cx = size.width / 2 + shift
        let baseY = (size.height * 0.69).rounded()
        let portalCenter = CGPoint(x: cx, y: baseY - 4 * block)
        let hubShown = phase == .hub
        let speed = phase.swirlSpeed * (signingIn ? 2 : 1)

        ZStack {
            LinearGradient(colors: [VoidPalette.top, VoidPalette.bottom], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: still)) { motes in
                VoidBackdrop(time: still ? 0 : motes.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000),
                             lit: phase.lit, rising: phase.isWarp ? 6 : 1, focus: portalCenter)
            }
            PlatformAndFigure(block: block, lit: phase.lit, drawsFigure: false)
                .position(x: cx, y: baseY - 1.9 * block - 0.55 * block + 3 * block)
            OrbitRing(items: HubPortal.all, index: $ring, radius: min(size.width * 0.32, 380)) { item, _ in
                ringItem(item, showsTag: false, phase: phase, block: block, speed: speed)
                    .opacity(item.live ? 1 : (hubShown ? 1 : 0))
                    .animation(Motion.orbit(reduced: reduceMotion), value: hubShown)
            }
            .position(x: cx, y: baseY - 4 * block + 22)
            PlatformAndFigure(block: block, lit: phase.lit, drawsPlatform: false)
                .position(x: cx, y: baseY - 1.9 * block - 0.55 * block + 3 * block)
                .allowsHitTesting(false)
            // Tags ride the same ring above the student, so the figure stands
            // in front of the portal but never covers a label.
            OrbitRing(items: HubPortal.all, index: $ring, radius: min(size.width * 0.32, 380)) { item, _ in
                ringItem(item, showsTag: true, phase: phase, block: block, speed: speed)
                    .opacity(item.live ? 1 : (hubShown ? 1 : 0))
                    // The slot straight behind the front one would show its
                    // label through the front portal.
                    .opacity(isBehind(item) ? 0 : 1)
            }
            .position(x: cx, y: baseY - 4 * block + 22)
        }
        .scaleEffect(phase.zoom, anchor: UnitPoint(x: portalCenter.x / max(size.width, 1), y: portalCenter.y / max(size.height, 1)))
        .modifier(WarpPixelate(active: phase.isWarp, cell: phase.pixelCell))
        .overlay { chrome(phase: phase, size: size) }
        .overlay {
            RadialGradient(colors: [Color(rgb: 0xFFFDF4), Color(rgb: 0xF6E7B0), Color(rgb: 0xC9A227), Color(rgb: 0x6D0E1F)],
                           center: UnitPoint(x: 0.5, y: 0.48), startRadius: 0, endRadius: max(size.width, size.height) * 0.8)
                .opacity(reduceMotion && phase.isWarp ? 1 : phase.flash)
                .animation(.easeIn(duration: reduceMotion ? 0.2 : 0.12), value: phase.flash)
                .allowsHitTesting(false)
        }
    }

    private func isBehind(_ item: HubPortal) -> Bool {
        let count = HubPortal.all.count
        guard let index = HubPortal.all.firstIndex(of: item) else { return false }
        return ((index - OrbitRing<HubPortal, EmptyView>.wrap(ring, count)) % count + count) % count == count / 2
    }

    /// One ring slot: the frame, or (on the upper layer) an invisible frame
    /// holding the slot's place with the tag underneath it.
    private func ringItem(_ item: HubPortal, showsTag: Bool, phase: LandingPhase, block: CGFloat, speed: Double) -> some View {
        VStack(spacing: 6) {
            if showsTag {
                Color.clear.frame(width: 6 * block, height: 8 * block).allowsHitTesting(false)
            } else {
                PortalFrame(block: block, formed: item.live ? phase.formed : 1, lit: phase.lit, live: item.live, speed: speed, cell: phase.pixelCell)
                    .onTapGesture { onSelect(item) }
            }
            if phase == .hub {
                Button { onSelect(item) } label: { tag(item) }
                    .buttonStyle(.plain)
                    .modifier(Shake(amount: item.id == front.id && !item.live ? shake : 0))
                    .accessibilityLabel(item.live ? "Enter the PUP SIS portal" : "Locked portal, not connected yet")
                    .opacity(showsTag ? 1 : 0)
                    .accessibilityHidden(!showsTag)
            }
        }
    }

    private func tag(_ item: HubPortal) -> some View {
        VStack(spacing: 2) {
            Text(item.live ? "PUP SIS" : "Not connected yet")
                .font(typography.display(size: 15, weight: .bold))
                .foregroundStyle(item.live ? VoidPalette.goldText : Color(rgb: 0x8D7E87))
            if item.live {
                Text(liveSubtitle).font(typography.reading(size: 12, weight: .semibold)).foregroundStyle(Color(rgb: 0xC9B9C2))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(VoidPalette.panel, in: PixelNotch())
        .overlay(PixelNotch().strokeBorder(item.live ? VoidPalette.goldLine : VoidPalette.panelLine, lineWidth: 2))
    }

    // MARK: Chrome

    private func chrome(phase: LandingPhase, size: CGSize) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("IntPortal").font(typography.display(size: 30, weight: .bold)).foregroundStyle(Color(rgb: 0xF4E8D6))
                Text("Unofficial app by a PUP student, not affiliated with PUP").font(typography.reading(size: 13)).foregroundStyle(Color(rgb: 0xA99AA3))
            }
            .padding(.leading, 28).padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 10) {
                if phase == .hub, let signedInAs {
                    (Text("Signed in as ") + Text(signedInAs).bold())
                        .font(typography.reading(size: 13)).foregroundStyle(VoidPalette.textDim)
                    Button("Switch account", action: onSwitchAccount)
                        .buttonStyle(.plain)
                        .font(typography.reading(size: 13))
                        .foregroundStyle(Color(rgb: 0xF0D98A))
                }
                Button(action: onSettings) { PixelIcon(.gear, size: 24) }
                    .buttonStyle(.plain)
                    .foregroundStyle(VoidPalette.textDim)
                    .accessibilityLabel("Settings")
            }
            .padding(.trailing, 28).padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if phase == .signIn {
                SignInPanel(existing: existing, signingIn: signingIn, failure: failure, onSave: onSave)
                .padding(.trailing, size.width > 760 ? 48 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size.width > 760 ? .trailing : .bottom)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Text(hint ?? defaultHint(phase))
                .font(typography.display(size: 14))
                .foregroundStyle(VoidPalette.textDim)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .animation(Motion.arrival(reduced: reduceMotion), value: phase == .signIn)
    }

    private func defaultHint(_ phase: LandingPhase) -> String {
        switch phase {
        case .void, .forming, .ignite: "Press Return to skip"
        case .signIn: "Sign in beside the portal"
        case .hub: front.live ? "Step through ⏎ · ← → to look around" : "Not connected yet. Only PUP SIS is live."
        case .warp, .done: ""
        }
    }

}

/// The warp's pixelation. Only attached while warping: a layer effect, even
/// disabled, renders the whole scene offscreen on every tick.
private struct WarpPixelate: ViewModifier {
    let active: Bool
    let cell: Double

    func body(content: Content) -> some View {
        if active, let library = Shaders.library {
            content.layerEffect(library.pixelate(.float(cell)), maxSampleOffset: CGSize(width: 16, height: 16))
        } else {
            content
        }
    }
}

/// A short horizontal shake for a portal that won't open.
private struct Shake: GeometryEffect {
    var amount: Int
    var animatableData: Double

    init(amount: Int) {
        self.amount = amount
        animatableData = Double(amount)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}
