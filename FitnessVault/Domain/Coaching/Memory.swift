import Foundation

/// The separate memory stores (M1). Conversation history and commitments have their own entities.
enum MemoryStore: String, Codable, CaseIterable, Sendable, Identifiable {
    case profile, objective, preference, routine, work, rehab, nutrition, inventory, social, decision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "About you"
        case .objective: "Goals"
        case .preference: "Preferences"
        case .routine: "Routines"
        case .work: "Work"
        case .rehab: "Knee and rehab"
        case .nutrition: "Food"
        case .inventory: "At home"
        case .social: "People and social"
        case .decision: "Coach decisions"
        }
    }
}

/// Where a memory came from. Only user-stated, brief and system facts can be confirmed without asking (M3).
enum MemorySource: String, Codable, Sendable {
    case userStated, brief, inferred, imported, system

    var title: String {
        switch self {
        case .userStated: "You told the coach"
        case .brief: "From your Vaultality brief"
        case .inferred: "The coach's guess"
        case .imported: "Imported"
        case .system: "Recorded by the app"
        }
    }
}

enum MemoryStatus: String, Codable, Sendable {
    /// A fact the user has stated or confirmed.
    case confirmed
    /// A guess. Never treated as fact until the user confirms it (M3).
    case hypothesis
    /// Replaced by a newer record; kept for history.
    case superseded
}

/// Privacy class (M4, E3). Sensitive records never appear in notifications or widgets.
enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case general, medical, financial, relationship, location

    var isSensitive: Bool { self != .general }

    var title: String {
        switch self {
        case .general: "General"
        case .medical: "Medical"
        case .financial: "Financial"
        case .relationship: "Relationship"
        case .location: "Location"
        }
    }
}

enum TaskArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case household, houseSale, personal, work

    var id: String { rawValue }

    var title: String {
        switch self {
        case .household: "Household"
        case .houseSale: "House sale"
        case .personal: "Personal"
        case .work: "Work"
        }
    }

    var symbol: String {
        switch self {
        case .household: "house"
        case .houseSale: "signpost.right"
        case .personal: "person"
        case .work: "laptopcomputer"
        }
    }
}

enum TaskState: String, Codable, CaseIterable, Sendable {
    case open, inProgress, parked, done, dropped

    var isActive: Bool { self == .open || self == .inProgress || self == .parked }
}

enum MessageRole: String, Codable, Sendable {
    case user, coach, system
}

/// Pure rule for memories: a guess must be confirmed before it is treated as fact (M3).
enum MemoryRules {
    static func initialStatus(for source: MemorySource) -> MemoryStatus {
        source == .inferred ? .hypothesis : .confirmed
    }
}
