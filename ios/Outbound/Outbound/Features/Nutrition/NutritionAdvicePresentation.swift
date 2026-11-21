/// Advice text and its optional decorative photo select one unchanged qualitative branch.
struct NutritionAdvicePresentation {
    let actionKey: String
    let photoAsset: String?

    static func selected(for phase: NutritionPhase, context: NutritionWorkoutContext) -> Self {
        guard context.isEndurance, let seconds = context.durationSeconds, seconds > 0 else {
            return .init(actionKey: "card.general.\(phase.rawValue)", photoAsset: phase == .during ? "nutrition_drink" : nil)
        }
        switch phase {
        case .before: return .init(actionKey: "card.before", photoAsset: "nutrition_toast_banana")
        case .after: return .init(actionKey: "card.after", photoAsset: "nutrition_yogurt_fruit")
        case .during:
            if seconds < 45 * 60 { return .init(actionKey: "card.during.short", photoAsset: nil) }
            if seconds >= 90 * 60 { return .init(actionKey: "card.during.long", photoAsset: "nutrition_portable_food_drink") }
            return .init(actionKey: "card.during.medium", photoAsset: "nutrition_drink")
        }
    }
}
