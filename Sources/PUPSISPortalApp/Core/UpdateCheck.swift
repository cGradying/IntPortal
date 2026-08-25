import Foundation

/// A release newer than the one currently running.
struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}

/// The in-app "update available" nudge: asks GitHub's public releases API
/// whether there's something newer than the running build and links out to it.
/// No self-update — the user still downloads the `.dmg` by hand, which is also
/// why this stays a quiet footer line rather than a modal.
///
/// ponytail: `AppState` no longer calls this — real self-updating now lives in
/// `UpdaterBridge`/Sparkle. Kept in the tree, untouched, only so anyone still
/// on a pre-Sparkle build (v1.3.0 or older) has one last "there's an update"
/// nudge to find their way to the release that finally installs Sparkle.
/// Delete this file and its test alongside it in v1.5.0.
///
/// Nothing about the user is sent: it's an anonymous GET against this project's
/// own public releases endpoint, with no query and no body.
///
/// The fetch is injectable so the part worth testing — deciding whether a
/// fetched release is actually newer — runs without a network call. Kept
/// deliberately in step with `windows/PUPSISPortal.Core/UpdateCheck.cs`; if the
/// comparison rules change, change both or the two platforms will disagree
/// about what "newer" means.
struct UpdateCheck {
    static let releasesURL = URL(string:
        "https://api.github.com/repos/cGradying/PUPSISPortal/releases/latest")!

    /// The running build's version, or nil when there's no Info.plist to read it
    /// from (a bare `swift run`, tests). Nil means *don't guess* — a stand-in
    /// literal here would make every release look newer and nag in development.
    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private let fetch: () async throws -> Data

    init(fetch: (() async throws -> Data)? = nil) {
        self.fetch = fetch ?? Self.defaultFetch
    }

    private static func defaultFetch() async throws -> Data {
        var request = URLRequest(url: releasesURL)
        // GitHub 403s an unauthenticated API request that sends no User-Agent.
        request.setValue("PUPSISPortal-UpdateCheck", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// The latest release if it's newer than `current`; nil if it isn't, or if
    /// the check fails for any reason (offline, GitHub down, unexpected shape).
    /// A failed check is silence — never an error the user has to deal with.
    func check(current: String) async -> UpdateInfo? {
        struct Release: Decodable {
            let tag: String
            let page: URL
            enum CodingKeys: String, CodingKey {
                case tag = "tag_name"
                case page = "html_url"
            }
        }

        guard let data = try? await fetch(),
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return nil }

        let latest = Self.stripPrefix(release.tag)
        guard !latest.isEmpty, Self.isNewer(latest, than: current) else { return nil }
        return UpdateInfo(version: latest, url: release.page)
    }

    /// True when `latest` is strictly newer. Compares up to four dot-separated
    /// segments, which covers both a `1.1.2` tag and a four-part Windows
    /// `<Version>` like `1.1.2.0`. A missing or non-numeric segment reads as 0
    /// rather than throwing, so an unexpected tag format fails closed — "not
    /// newer" — instead of breaking the check.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = parse(latest)
        let c = parse(current)
        for i in 0..<4 where l[i] != c[i] {
            return l[i] > c[i]
        }
        return false
    }

    private static func stripPrefix(_ version: String) -> String {
        var s = Substring(version.trimmingCharacters(in: .whitespacesAndNewlines))
        while let first = s.first, first == "v" || first == "V" { s = s.dropFirst() }
        return String(s)
    }

    private static func parse(_ version: String) -> [Int] {
        var result = [0, 0, 0, 0]
        let parts = stripPrefix(version).split(separator: ".", omittingEmptySubsequences: false)
        for (i, part) in parts.prefix(4).enumerated() {
            result[i] = Int(part) ?? 0
        }
        return result
    }
}
