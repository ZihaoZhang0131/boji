import SwiftUI
import BojiDomain

struct ReviewCharts: View {
    let days: [DayReview]
    @ScaledMetric(relativeTo: .caption) private var axisFontSize: CGFloat = 12

    var body: some View {
        let font = UIFont.monospacedDigitSystemFont(ofSize: axisFontSize, weight: .regular)
        let labels = [ReviewPresentation.Metric.intake, .training].flatMap { metric in
            let maximum = ReviewPresentation.ceiling(days.map { metric.value($0) })
            return [maximum, maximum / 2, 0].map { String(Int($0.rounded())) }
        } + ["000"]
        let axisWidth = ceil(labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
        VStack(alignment: .leading, spacing: 32) {
            ReviewChart(days: days, metric: .intake, axisWidth: axisWidth, axisFontSize: axisFontSize)
            ReviewChart(days: days, metric: .training, axisWidth: axisWidth, axisFontSize: axisFontSize)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, -4)
    }
}

struct ReviewChart: View {
    let days: [DayReview]
    let metric: ReviewPresentation.Metric
    let axisWidth: CGFloat
    let axisFontSize: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .headline) private var titleFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var plotHeight: CGFloat = 160
    private var values: [Double?] { days.map { metric.value($0) } }
    private var runs: [[ReviewPresentation.Point]] { ReviewPresentation.runs(values) }
    private var maximum: Double { ReviewPresentation.ceiling(values) }
    private var title: String { (days.contains(where: { metric.pending($0) }) ? "已知" : "") + metric.title }
    private var axisFont: UIFont { .monospacedDigitSystemFont(ofSize: axisFontSize, weight: .regular) }
    private var axisHeight: CGFloat { ceil(axisFont.lineHeight) }
    private var plotInset: CGFloat { max(8, axisHeight / 2) }
    private var labelIndices: [Int] { ReviewChartGeometry.labelIndices(count: days.count, accessibility: dynamicTypeSize > .large) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { heading; unit }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) { heading; unit }
            }.padding(.leading, axisWidth + 6)
            if runs.isEmpty {
                Text("暂无热量数据").font(.subheadline).foregroundStyle(PixelTheme.subtle)
                    .padding(.vertical, 12).padding(.leading, axisWidth + 6)
                    .accessibilityIdentifier("review.empty." + metric.rawValue)
            } else {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        let layout = ReviewChartGeometry(count: days.count, maximum: maximum,
                                                         size: CGSize(width: max(1, geometry.size.width - axisWidth - 6), height: plotHeight), inset: plotInset)
                        HStack(alignment: .top, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                ForEach(layout.ticks, id: \.self) { value in
                                    Text(verbatim: String(Int(value.rounded())))
                                        .font(.system(size: axisFontSize)).monospacedDigit()
                                        .foregroundStyle(PixelTheme.subtle).fixedSize()
                                        .frame(width: axisWidth, alignment: .trailing)
                                        .position(x: axisWidth / 2, y: layout.y(value))
                                }
                            }.frame(width: axisWidth, height: plotHeight)
                            plot(layout).frame(width: layout.size.width, height: plotHeight)
                        }
                    }.frame(height: plotHeight).accessibilityHidden(true)
                    ReviewDateAxisLayout(count: days.count, indices: labelIndices) {
                        ForEach(labelIndices, id: \.self) { index in
                            Text("\(days[index].day.month)/\(days[index].day.day)")
                                .font(.system(size: axisFontSize)).monospacedDigit().fixedSize()
                                .foregroundStyle(PixelTheme.subtle)
                        }
                    }.padding(.leading, axisWidth + 6).padding(.top, 6 - plotInset).accessibilityHidden(true)
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
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heading: some View {
        Text(title).font(.system(size: titleFontSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder private var unit: some View {
        if !runs.isEmpty { Text("kcal").font(.system(size: axisFontSize)).foregroundStyle(PixelTheme.subtle) }
    }
    private func plot(_ layout: ReviewChartGeometry) -> some View {
        ZStack {
            ForEach(layout.ticks, id: \.self) { value in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: layout.y(value)))
                    path.addLine(to: CGPoint(x: layout.size.width, y: layout.y(value)))
                }.stroke(Color.primary.opacity(contrast == .increased ? 0.35 : value == 0 ? 0.16 : 0.08), lineWidth: 1)
            }
            Path { path in
                for index in labelIndices {
                    let x = layout.x(Double(index))
                    path.move(to: CGPoint(x: x, y: layout.baseline))
                    path.addLine(to: CGPoint(x: x, y: layout.baseline + 3))
                }
            }.stroke(Color.primary.opacity(contrast == .increased ? 0.35 : 0.16), lineWidth: 1)
            if metric == .training {
                Path { path in
                    for sample in runs.flatMap({ $0 }) {
                        let p = layout.point(sample), width = layout.slot * 0.6
                        // A real zero stays visible without inventing a positive bar.
                        path.addRect(CGRect(x: p.x - width / 2, y: sample.y == 0 ? p.y - 1 : p.y,
                                            width: width, height: sample.y == 0 ? 2 : layout.baseline - p.y))
                    }
                }.fill(Color.primary)
            } else {
                Path { path in
                    for run in runs where run.count > 1 {
                        path.move(to: layout.point(run[0]))
                        if run.count == 2 { path.addLine(to: layout.point(run[1])) }
                        else {
                            for curve in ReviewPresentation.curves(run) {
                                path.addCurve(to: layout.point(curve.end), control1: layout.point(curve.c1), control2: layout.point(curve.c2))
                            }
                        }
                    }
                }.stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { path in
                    for sample in runs.flatMap({ $0 }) {
                        let p = layout.point(sample)
                        path.addEllipse(in: CGRect(x: p.x - 2.7, y: p.y - 2.7, width: 5.4, height: 5.4))
                    }
                }.fill(Color.primary)
            }
        }
    }
    private func accessibilityDescription(_ day: DayReview) -> String {
        let value = metric.value(day).map { String(Int($0.rounded())) + " kcal" } ?? "无有效热量"
        let name = (metric.pending(day) ? "已知" : "") + metric.title
        return day.day.description + "，" + name + "，" + value
    }
}

/// Keep date labels attached to their ticks; at very large sizes a second row
/// preserves the complete endpoints instead of shrinking or overlapping them.
private struct ReviewDateAxisLayout: Layout {
    let count: Int
    let indices: [Int]
    private func arrangement(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], height: CGFloat) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rowHeight = sizes.map(\.height).max() ?? 0
        let gap: CGFloat = indices.count < count && rowHeight > 20 ? rowHeight / 2 : 0
        let geometry = ReviewChartGeometry(count: count, maximum: 1, size: CGSize(width: width, height: 0), inset: 0)
        var rowEnds: [CGFloat] = [], points: [CGPoint] = []
        for (offset, size) in sizes.enumerated() {
            let index = indices[offset], x = geometry.x(Double(index))
            let anchor: CGFloat = indices.count < count ? (index == 0 ? 0 : index == count - 1 ? 1 : 0.5) : 0.5
            let left = max(0, min(width - size.width, x - size.width * anchor))
            let row = rowEnds.firstIndex(where: { $0 + gap <= left }) ?? rowEnds.count
            if row == rowEnds.count { rowEnds.append(left + size.width) } else { rowEnds[row] = left + size.width }
            points.append(CGPoint(x: left, y: CGFloat(row) * (rowHeight + 2)))
        }
        return (points, CGFloat(rowEnds.count) * (rowHeight + 2) - (rowEnds.isEmpty ? 0 : 2))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + 2 }
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + result.points[index].x, y: bounds.minY + result.points[index].y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}
