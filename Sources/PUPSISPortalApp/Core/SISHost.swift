import Foundation

/// Which SIS host to try next, and whether a signed-in host is worth
/// keeping. Pulled out of `PortalController` so the failover rules from
/// `docs/specs/00-sis-host.md` run — and are tested — without a real
/// `WKWebView`.
///
/// Mirrors are not interchangeable (commit f763487): sis1 signs in but
/// never carries this account's schedule, sis8 does. So "reachable" and
/// "signs in" are not enough — only a host that actually returns schedule
/// rows counts as good.
enum SISHost {
    /// PUP SIS mirrors are numbered `sisN.pup.edu.ph`. Anchored and exact so
    /// neither a different subdomain (`www.pup.edu.ph`) nor a lookalike
    /// domain piggybacking the suffix (`sis8.pup.edu.ph.evil.com`) can pass.
    static func isCandidateHost(_ host: String) -> Bool {
        host.range(of: #"^sis\d+\.pup\.edu\.ph$"#, options: .regularExpression) != nil
    }

    /// Remembered host first (if it's still a valid candidate), then the
    /// confirmed-live hosts in spec order, deduplicated.
    static func candidates(remembered: String?) -> [String] {
        var order: [String] = []
        if let remembered, isCandidateHost(remembered) { order.append(remembered) }
        for host in ["sis8.pup.edu.ph", "sis1.pup.edu.ph", "sis2.pup.edu.ph"] where !order.contains(host) {
            order.append(host)
        }
        return order
    }

    /// What happened trying one candidate host.
    enum Attempt {
        /// Wrong credentials — a property of the account, not the host.
        case validationError
        /// Timed out, network error, or any other non-validation failure.
        case failed
        /// Signed in, but the schedule page scraped zero rows.
        case signedInEmpty
        /// Signed in and the schedule scraped at least one row.
        case signedInWithRows
    }

    enum Decision: Equatable {
        /// Persist this host and stop.
        case keep(host: String)
        /// Try the next candidate.
        case next
        /// Stop trying entirely — no host is persisted. Only for
        /// `validationError`: retrying bad credentials on another host
        /// would send them to a second server for nothing.
        case stop
    }

    static func decide(_ attempt: Attempt, host: String) -> Decision {
        switch attempt {
        case .validationError: return .stop
        case .failed, .signedInEmpty: return .next
        case .signedInWithRows: return .keep(host: host)
        }
    }
}
