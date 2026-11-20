import SwiftUI

/// Text and decorative food imagery select the same unchanged qualitative branch.
struct NutritionAdvicePresentation {
    let actionKey: String
    let scene: NutritionFoodScene

    static func selected(for phase: NutritionPhase, context: NutritionWorkoutContext) -> Self {
        guard context.isEndurance, let seconds = context.durationSeconds, seconds > 0 else {
            return .init(actionKey: "card.general.\(phase.rawValue)", scene: phase == .during ? .drink : .usualMeal)
        }
        switch phase {
        case .before: return .init(actionKey: "card.before", scene: .toastAndBanana)
        case .after: return .init(actionKey: "card.after", scene: .yogurtAndFruit)
        case .during:
            if seconds < 45 * 60 { return .init(actionKey: "card.during.short", scene: .shortSession) }
            if seconds >= 90 * 60 { return .init(actionKey: "card.during.long", scene: .portableFoodAndDrink) }
            return .init(actionKey: "card.during.medium", scene: .drink)
        }
    }
}

enum NutritionFoodScene {
    case toastAndBanana, yogurtAndFruit, drink, portableFoodAndDrink, usualMeal, shortSession
}

/// Small vector scenes use shape/outline, rather than color alone, for recognition.
/// No pictured food is a recorded intake or a calculated serving size.
struct NutritionFoodIllustration: View {
    @Environment(\.outboundTheme) private var theme
    let scene: NutritionFoodScene

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 120, y: size.height / 100)
            switch scene {
            case .toastAndBanana:
                toast(in: &context)
                banana(in: &context)
            case .yogurtAndFruit: yogurt(in: &context)
            case .drink: drink(in: &context)
            case .portableFoodAndDrink:
                var glass = context
                glass.translateBy(x: 47, y: 8)
                glass.scaleBy(x: 0.72, y: 0.82)
                drink(in: &glass)
                portableFood(in: &context)
            case .usualMeal: plate(in: &context)
            case .shortSession: clock(in: &context)
            }
        }
        .frame(width: 96, height: 80)
        .padding(OutboundSpacing.compact)
        .background(theme.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: OutboundRadius.card))
        .accessibilityHidden(true)
    }

    private func outline(_ path: Path, in context: inout GraphicsContext, fill: Color? = nil) {
        if let fill { context.fill(path, with: .color(fill)) }
        context.stroke(path, with: .color(theme.actionColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func toast(in context: inout GraphicsContext) {
        let bread = Path { p in
            p.move(to: CGPoint(x: 15, y: 78))
            p.addLine(to: CGPoint(x: 15, y: 36))
            p.addCurve(to: CGPoint(x: 8, y: 26), control1: CGPoint(x: 7, y: 35), control2: CGPoint(x: 5, y: 30))
            p.addCurve(to: CGPoint(x: 66, y: 26), control1: CGPoint(x: 9, y: 6), control2: CGPoint(x: 66, y: 6))
            p.addCurve(to: CGPoint(x: 59, y: 36), control1: CGPoint(x: 69, y: 31), control2: CGPoint(x: 65, y: 35))
            p.addLine(to: CGPoint(x: 59, y: 78)); p.closeSubpath()
        }
        outline(bread, in: &context, fill: theme.secondaryColor.opacity(0.22))
        outline(Path(roundedRect: CGRect(x: 22, y: 34, width: 30, height: 36), cornerRadius: 7), in: &context,
                fill: OutboundPalette.background)
        for point in [CGPoint(x: 30, y: 44), CGPoint(x: 44, y: 52), CGPoint(x: 33, y: 62)] {
            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 2.5, height: 2.5)), with: .color(theme.actionColor))
        }
    }

    private func banana(in context: inout GraphicsContext) {
        let fruit = Path { p in
            p.move(to: CGPoint(x: 67, y: 57))
            p.addCurve(to: CGPoint(x: 109, y: 31), control1: CGPoint(x: 89, y: 68), control2: CGPoint(x: 107, y: 55))
            p.addCurve(to: CGPoint(x: 72, y: 81), control1: CGPoint(x: 117, y: 59), control2: CGPoint(x: 96, y: 89))
            p.addQuadCurve(to: CGPoint(x: 67, y: 57), control: CGPoint(x: 61, y: 72)); p.closeSubpath()
        }
        outline(fruit, in: &context, fill: theme.secondaryColor.opacity(0.3))
        outline(Path { p in
            p.move(to: CGPoint(x: 71, y: 69)); p.addQuadCurve(to: CGPoint(x: 105, y: 48), control: CGPoint(x: 95, y: 77))
            p.move(to: CGPoint(x: 108, y: 31)); p.addLine(to: CGPoint(x: 110, y: 25))
        }, in: &context)
    }

    private func drink(in context: inout GraphicsContext) {
        let glass = Path { p in
            p.move(to: CGPoint(x: 39, y: 17)); p.addLine(to: CGPoint(x: 81, y: 17))
            p.addLine(to: CGPoint(x: 75, y: 84)); p.addLine(to: CGPoint(x: 45, y: 84)); p.closeSubpath()
        }
        context.fill(glass, with: .color(OutboundPalette.background))
        let liquid = Path { p in
            p.move(to: CGPoint(x: 43, y: 47))
            p.addQuadCurve(to: CGPoint(x: 77, y: 47), control: CGPoint(x: 60, y: 54))
            p.addLine(to: CGPoint(x: 74, y: 81)); p.addLine(to: CGPoint(x: 46, y: 81)); p.closeSubpath()
        }
        context.fill(liquid, with: .color(theme.secondaryColor.opacity(0.3)))
        outline(glass, in: &context)
        outline(Path { p in p.move(to: CGPoint(x: 49, y: 27)); p.addLine(to: CGPoint(x: 51, y: 40)) }, in: &context)
    }

    private func portableFood(in context: inout GraphicsContext) {
        let wrapper = Path { p in
            p.move(to: CGPoint(x: 10, y: 45)); p.addLine(to: CGPoint(x: 64, y: 45))
            p.addLine(to: CGPoint(x: 59, y: 54)); p.addLine(to: CGPoint(x: 64, y: 65))
            p.addLine(to: CGPoint(x: 10, y: 65)); p.addLine(to: CGPoint(x: 15, y: 55)); p.closeSubpath()
        }
        outline(wrapper, in: &context, fill: OutboundPalette.background)
        outline(Path(roundedRect: CGRect(x: 21, y: 43, width: 32, height: 24), cornerRadius: 4), in: &context,
                fill: theme.secondaryColor.opacity(0.3))
        for point in [CGPoint(x: 28, y: 50), CGPoint(x: 40, y: 57), CGPoint(x: 44, y: 49)] {
            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 3, height: 3)), with: .color(theme.actionColor))
        }
    }

    private func yogurt(in context: inout GraphicsContext) {
        outline(Path { p in
            p.move(to: CGPoint(x: 77, y: 47)); p.addLine(to: CGPoint(x: 91, y: 17))
        }, in: &context)
        outline(Path(ellipseIn: CGRect(x: 87, y: 7, width: 9, height: 16)), in: &context,
                fill: theme.secondaryColor.opacity(0.2))
        let bowl = Path { p in
            p.move(to: CGPoint(x: 20, y: 43)); p.addLine(to: CGPoint(x: 100, y: 43))
            p.addQuadCurve(to: CGPoint(x: 76, y: 82), control: CGPoint(x: 96, y: 75))
            p.addLine(to: CGPoint(x: 44, y: 82))
            p.addQuadCurve(to: CGPoint(x: 20, y: 43), control: CGPoint(x: 24, y: 75)); p.closeSubpath()
        }
        outline(bowl, in: &context, fill: theme.secondaryColor.opacity(0.22))
        outline(Path(ellipseIn: CGRect(x: 20, y: 34, width: 80, height: 18)), in: &context, fill: OutboundPalette.background)
        for rect in [CGRect(x: 37, y: 33, width: 11, height: 11), CGRect(x: 51, y: 38, width: 11, height: 11), CGRect(x: 64, y: 33, width: 11, height: 11)] {
            outline(Path(ellipseIn: rect), in: &context, fill: theme.secondaryColor)
        }
    }

    private func plate(in context: inout GraphicsContext) {
        outline(Path(ellipseIn: CGRect(x: 30, y: 21, width: 61, height: 61)), in: &context,
                fill: OutboundPalette.background)
        outline(Path(ellipseIn: CGRect(x: 40, y: 31, width: 41, height: 41)), in: &context)
        outline(Path { p in
            p.move(to: CGPoint(x: 15, y: 19)); p.addLine(to: CGPoint(x: 15, y: 83))
            p.move(to: CGPoint(x: 9, y: 19)); p.addLine(to: CGPoint(x: 9, y: 35))
            p.addQuadCurve(to: CGPoint(x: 21, y: 35), control: CGPoint(x: 15, y: 45)); p.addLine(to: CGPoint(x: 21, y: 19))
            p.move(to: CGPoint(x: 105, y: 19)); p.addLine(to: CGPoint(x: 105, y: 83))
            p.move(to: CGPoint(x: 105, y: 19)); p.addQuadCurve(to: CGPoint(x: 105, y: 54), control: CGPoint(x: 118, y: 39))
        }, in: &context)
    }

    private func clock(in context: inout GraphicsContext) {
        outline(Path(ellipseIn: CGRect(x: 29, y: 19, width: 62, height: 62)), in: &context,
                fill: OutboundPalette.background)
        outline(Path { p in
            p.move(to: CGPoint(x: 60, y: 29)); p.addLine(to: CGPoint(x: 60, y: 50)); p.addLine(to: CGPoint(x: 76, y: 58))
        }, in: &context)
    }
}
