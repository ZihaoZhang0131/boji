import SwiftUI
import BojiDomain

/// Bars use solid / diagonal fill; lines connect only adjacent days with known expenditure.
/// Every day also has a 44-point selection target and a numeric accessibility description.
struct ReviewChart: View {
    let days: [DayReview]
    let selected: LocalDay
    let onSelect: (LocalDay) -> Void
    private let column: CGFloat = 48
    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Canvas { context, size in draw(context: context, size: size) }
                        .accessibilityHidden(true)
                    HStack(spacing: 0) {
                        ForEach(days) { day in
                            Button { onSelect(day.day) } label: { Color.clear.frame(width: column, height: 180).contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("review.day." + day.day.description)
                                .accessibilityLabel(day.day.description + "，" + description(day))
                                .accessibilityAddTraits(day.day == selected ? .isSelected : [])
                        }
                    }
                }.frame(width: column * CGFloat(days.count), height: 180)
                HStack(spacing: 0) {
                    ForEach(days) { day in Text(String(day.day.day)).font(PixelTheme.font(12)).frame(width: column, height: 32) }
                }.accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("review.chart")
        Text("实心：完整摄入；斜线：未完整摄入；折线：估算总消耗，未知处断开。单位 kcal。")
            .font(.footnote)
    }
    private func description(_ day: DayReview) -> String {
        let burn = day.totalBurnKcal.map(String.init) ?? "未知"
        return "已知摄入 \(day.knownIntakeKcal.description)，消耗 \(burn)，" + (day.complete ? "完整" : "未完整")
    }
    private func draw(context: GraphicsContext, size: CGSize) {
        let maximum = max(1.0, days.map { max(NSDecimalNumber(decimal: $0.knownIntakeKcal).doubleValue, Double($0.totalBurnKcal ?? 0)) }.max() ?? 1)
        func y(_ value: Double) -> CGFloat { size.height - 12 - CGFloat(value / maximum) * (size.height - 24) }
        for (index, day) in days.enumerated() {
            let x = column * CGFloat(index) + column / 2
            let intake = NSDecimalNumber(decimal: day.knownIntakeKcal).doubleValue
            let rect = CGRect(x: x - 12, y: y(intake), width: 24, height: max(1, size.height - 12 - y(intake)))
            if day.mealCount > 0 {
                if day.complete { context.fill(Path(rect), with: .foreground) }
                else {
                    var clipped = context; clipped.clip(to: Path(rect))
                    var stripes = Path()
                    for start in stride(from: rect.minY - 24, through: rect.maxY + 24, by: 6) {
                        stripes.move(to: CGPoint(x: rect.minX, y: start)); stripes.addLine(to: CGPoint(x: rect.maxX, y: start + 24))
                    }
                    clipped.stroke(stripes, with: .foreground, lineWidth: 1)
                    context.stroke(Path(rect), with: .foreground, lineWidth: 1)
                }
            }
            if let burn = day.totalBurnKcal {
                let point = CGPoint(x: x, y: y(Double(burn)))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .foreground)
                if index > 0, let previous = days[index - 1].totalBurnKcal {
                    var line = Path(); line.move(to: CGPoint(x: x - column, y: y(Double(previous)))); line.addLine(to: point)
                    context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            if day.day == selected { context.stroke(Path(CGRect(x: x - 21, y: 0, width: 42, height: size.height)), with: .foreground, lineWidth: 1) }
        }
    }
}
