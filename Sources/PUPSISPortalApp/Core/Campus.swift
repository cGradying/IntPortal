import Foundation

/// One PUP campus or branch. `code` is the `MN`-shaped fragment embedded in a
/// student number — `nil` for every campus but Sta. Mesa, since that's the
/// only one publicly confirmed (see spec 10). Never guess the others.
struct Campus: Codable, Hashable {
    let code: String?
    let name: String
    let region: String
}

/// What resolving a student number against the catalog turned up.
enum CampusResolution: Equatable {
    case known(Campus)
    case unknownCode(String)
    case incomplete
    case overridden(Campus)
}

enum CampusCatalog {
    /// PUP's ~25 campuses and branches (Wikipedia, "Polytechnic University of
    /// the Philippines", researched 2026-09-23).
    static let all: [Campus] = [
        Campus(code: "MN", name: "Sta. Mesa", region: "Manila"),
        Campus(code: nil, name: "San Juan", region: "Metro Manila"),
        Campus(code: nil, name: "Parañaque", region: "Metro Manila"),
        Campus(code: nil, name: "Taguig", region: "Metro Manila"),
        Campus(code: nil, name: "Quezon City", region: "Metro Manila"),
        Campus(code: nil, name: "Caloocan", region: "Metro Manila"),
        Campus(code: nil, name: "Mariveles", region: "Bataan"),
        Campus(code: nil, name: "Pulilan", region: "Bulacan"),
        Campus(code: nil, name: "Sta. Maria", region: "Bulacan"),
        Campus(code: nil, name: "Cabiao", region: "Nueva Ecija"),
        Campus(code: nil, name: "Maragondon", region: "Cavite"),
        Campus(code: nil, name: "Alfonso", region: "Cavite"),
        Campus(code: nil, name: "Biñan", region: "Laguna"),
        Campus(code: nil, name: "Calauan", region: "Laguna"),
        Campus(code: nil, name: "San Pedro", region: "Laguna"),
        Campus(code: nil, name: "Sta. Rosa", region: "Laguna"),
        Campus(code: nil, name: "Sto. Tomas", region: "Batangas"),
        Campus(code: nil, name: "Talisay", region: "Batangas"),
        Campus(code: nil, name: "Mulanay", region: "Quezon"),
        Campus(code: nil, name: "Lopez", region: "Quezon"),
        Campus(code: nil, name: "Unisan", region: "Quezon"),
        Campus(code: nil, name: "Ragay", region: "Camarines Sur"),
        Campus(code: nil, name: "Bansud", region: "Mindoro"),
        Campus(code: nil, name: "Sablayan", region: "Mindoro"),
        Campus(code: nil, name: "Leyte", region: "Leyte"),
    ]

    // Compiled once, not per call — `String.range(of:options:.regularExpression)`
    // recompiles the pattern every time, which is what blew the 5ms/10,000-call
    // budget (spec 10) the first time this was written that way.
    private static let studentNumberRegex = try! NSRegularExpression(pattern: #"^\d{4}-\d{5}-([A-Za-z]{2})-\d{1,2}$"#)

    /// The two-letter code embedded in a student number, uppercased —
    /// `nil` until the number is fully typed out (`YYYY-NNNNN-XX-N[N]`).
    static func code(fromStudentNumber studentNumber: String) -> String? {
        let trimmed = studentNumber.trimmingCharacters(in: .whitespaces)
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = studentNumberRegex.firstMatch(in: trimmed, range: fullRange),
              let codeRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        return trimmed[codeRange].uppercased()
    }

    /// `override` — a Settings pick, or a code the student already taught the
    /// app (`learnedCodes`, folded in by the caller) — always wins over the
    /// catalog, since that's the whole point of letting someone correct an
    /// unverified or missing code.
    static func resolve(studentNumber: String, override: Campus?, learnedCodes: [String: String] = [:]) -> CampusResolution {
        if let override { return .overridden(override) }
        guard let code = code(fromStudentNumber: studentNumber) else { return .incomplete }
        if let campus = all.first(where: { $0.code == code }) { return .known(campus) }
        if let name = learnedCodes[code] { return .overridden(Campus(code: code, name: name, region: "")) }
        return .unknownCode(code)
    }
}
