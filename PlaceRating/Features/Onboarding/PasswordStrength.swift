import Foundation

/// A rough, offline guess at how hard a password is to guess, for the bar on the sign-up screen.
/// The server only requires 8 characters; this nudges people towards better ones.
enum PasswordStrength: Int, Comparable, CaseIterable {
    case empty, tooShort, weak, fair, good, strong

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Passwords people pick first, plus the app's own name. Compared after lowercasing.
    private static let common: Set<String> = [
        "password", "password1", "password123", "12345678", "123456789", "1234567890", "qwertyuiop",
        "qwerty123", "iloveyou", "11111111", "00000000", "abcdefgh", "abc12345", "letmein1",
        "welcome1", "football", "baseball", "sunshine", "princess", "stoop123", "stooppass",
    ]

    init(_ password: String) {
        guard !password.isEmpty else { self = .empty; return }
        guard password.count >= 8 else { self = .tooShort; return }
        let lower = password.lowercased()
        let distinct = Set(password).count
        if Self.common.contains(lower) || distinct <= 3 { self = .weak; return }

        var score = 0
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        if password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase) { score += 1 }
        if password.contains(where: \.isNumber) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }
        self = switch score {
        case 0...1: .weak
        case 2: .fair
        case 3: .good
        default: .strong
        }
    }

    /// How many of the bar's four segments are lit.
    var filledSegments: Int {
        switch self {
        case .empty: 0
        case .tooShort, .weak: 1
        case .fair: 2
        case .good: 3
        case .strong: 4
        }
    }

    var label: String {
        switch self {
        case .empty: ""
        case .tooShort: tr("At least 8 characters.")
        case .weak: tr("Weak")
        case .fair: tr("Fair")
        case .good: tr("Good")
        case .strong: tr("Strong")
        }
    }

    /// A tip for getting to the next level, if there is one.
    var hint: String? {
        switch self {
        case .weak, .fair: tr("Longer is better. Mix in capitals, numbers or symbols.")
        default: nil
        }
    }
}
