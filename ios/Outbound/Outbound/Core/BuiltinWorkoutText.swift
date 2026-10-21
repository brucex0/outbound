import Foundation

/// Resolves only known product-authored vocabulary; unrecognized/generated prose
/// and user-entered names pass through unchanged.
enum BuiltinWorkoutText {
    static func localized(_ value: String) -> String {
        let exact = NSLocalizedString(value, bundle: .main, value: value, comment: "Built-in workout vocabulary")
        if exact != value { return exact }
        // Backend archetypes prefix a stable workout name with a variable duration.
        let pattern = #"^(\d+) min (easy run \+ strides|easy run|recovery run|recovery walk|brisk walk|walk-run return|easy ride|recovery spin)$"#
        if let match = value.range(of: pattern, options: .regularExpression), match == value.startIndex..<value.endIndex,
           let separator = value.range(of: " min "), let minutes = Int(value[..<separator.lowerBound]) {
            let title = String(value[separator.upperBound...])
            return String(format: String(localized: "workout.duration_title", defaultValue: "%d min %@"), minutes, localized(title))
        }
        return value
    }
}
