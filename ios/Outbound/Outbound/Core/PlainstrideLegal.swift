import Foundation

enum PlainstrideLegalDocument: String, Sendable {
    case terms
    case privacy
    case support

    var url: URL {
        switch self {
        case .terms: PlainstrideLegal.termsURL
        case .privacy: PlainstrideLegal.privacyURL
        case .support: PlainstrideLegal.supportURL
        }
    }
}

enum PlainstrideLegal {
    // Increment with the backend constant whenever a material Terms update requires reacceptance.
    static let currentTermsVersion = 2
    static let termsURL = URL(string: "https://plainstride.ai/terms")!
    static let privacyURL = URL(string: "https://plainstride.ai/privacy")!
    static let supportURL = URL(string: "https://plainstride.ai/support")!

    static func document(for url: URL) -> PlainstrideLegalDocument? {
        PlainstrideLegalDocument.allCases.first { $0.url == url }
    }
}

extension PlainstrideLegalDocument: CaseIterable {}
