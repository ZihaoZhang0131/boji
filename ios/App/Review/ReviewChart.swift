import SwiftUI
import BojiDomain

struct ReviewChart: View {
    let days: [DayReview]
    let metric: ReviewPresentation.Metric
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var axisWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .caption) private var plotHeight: CGFloat = 160
    private var values: [Double?] { days.map { metric.value($0) } }
    private var runs: [[ReviewPresentation.Point]] { ReviewPresentation.runs(values) }
    private var maximum: Double { ReviewPresentation.ceiling(values) }
    private var title: String { (days.contains(where: { metric.pending($0) }) ? "已知" : "") + metric.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !runs.isEmpty { Text("kcal").font(.caption).foregroundStyle(PixelTheme.subtle) }
            }
            if runs.isEmpty {
                Text("暂无热量数据").font(.subheadline).foregroundStyle(PixelTheme.subtle).padding(.vertical, 12)
                    .accessibilityIdentifier("review.empty." + metric.rawValue)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        VStack(alignment: .leading) {
                            axis(maximum); Spacer(); axis(maximum / 2); Spacer(); axis(0)
                        }.frame(width: axisWidth, height: plotHeight).accessibilityHidden(true)
                        GeometryReader { geometry in
                            let height = geometry.size.height
                            let point: (ReviewPresentation.Point) -> CGPoint = { p in
                                CGPoint(x: 4 + p.x / Double(max(1, days.count - 1)) * max(1, geometry.size.width - 8),
                                        y: height - 4 - p.y / maximum * (height - 8))
                            }
                            ZStack {
                                Path { path in path.move(to: CGPoint(x: 4, y: height - 4)); path.addLine(to: CGPoint(x: geometry.size.width - 4, y: height - 4)) }
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                Path { path in
                                    for run in runs where run.count > 1 {
                                        path.move(to: point(run[0]))
                                        if run.count == 2 { path.addLine(to: point(run[1])) }
                                        else { for curve in ReviewPresentation.curves(run) { path.addCurve(to: point(curve.end), control1: point(curve.c1), control2: point(curve.c2)) } }
                                    }
                                }.stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                Path { path in
                                    for sample in runs.flatMap({ $0 }) {
                                        let p = point(sample)
                                        path.addEllipse(in: CGRect(x: p.x - 2.7, y: p.y - 2.7, width: 5.4, height: 5.4))
                                    }
                                }.fill(Color.primary)
                            }
                        }.frame(height: plotHeight).accessibilityHidden(true)
                    }
                    HStack(alignment: .top) {
                        ForEach(labelIndices, id: \.self) { index in
                            if index != labelIndices.first { Spacer(minLength: 8) }
                            Text("\(days[index].day.month)/\(days[index].day.day)")
                                .font(.caption).monospacedDigit().fixedSize(horizontal: true, vertical: false)
                        }
                    }.padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : axisWidth + 4)
                        .foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title + "趋势")
                .accessibilityIdentifier("review.chart." + metric.rawValue)
                .accessibilityChildren {
                    ForEach(days) { day in
                        Text(accessibilityDescription(day))
                            .accessibilityIdentifier("review.value." + metric.rawValue + "." + day.day.description)
                    }
                }
            }
        }
    }
    private var labelIndices: [Int] { days.isEmpty ? [] : dynamicTypeSize.isAccessibilitySize ? [0, days.count - 1] : [0, (days.count - 1) / 2, days.count - 1] }
    private func accessibilityDescription(_ day: DayReview) -> String {
        let value = metric.value(day).map { String(Int($0.rounded())) + " kcal" } ?? "无有效热量"
        let name = (metric.pending(day) ? "已知" : "") + metric.title
        return day.day.description + "，" + name + "，" + value
    }
    private func axis(_ value: Double) -> some View {
        Text(verbatim: String(Int(value.rounded()))).font(.caption2).monospacedDigit().fixedSize(horizontal: true, vertical: false).foregroundStyle(PixelTheme.subtle)
    }
}
