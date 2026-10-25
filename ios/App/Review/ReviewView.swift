import SwiftUI
import BojiDomain

struct ReviewView: View {
    let workspace: WorkspaceModel
    let clock: any AppClock
    let endDay: LocalDay
    let trendRequest: UUID
    @Binding var section: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rangeCount = 7
    @State private var calendarOffset = 0
    @State private var trendEnd: LocalDay?
    private var state: DatasetSnapshot { workspace.snapshot ?? DatasetSnapshot() }
    private var today: LocalDay { LocalDay(clock.now, timeZone: clock.timeZone) }
    private var chartEnd: LocalDay { min(trendEnd ?? endDay, today) }
    private var days: [DayReview] { (try? ReviewRules.range(ending: chartEnd, count: rangeCount, in: state).days) ?? [] }
    private var calendarDays: [LocalDay] { ReviewPresentation.calendarDays(today: today, offset: calendarOffset) }
    private var earliest: LocalDay? { ReviewPresentation.earliest(in: state, today: today) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionPicker
                    if section == "趋势" { trend } else { calendar }
                }.padding(16)
            }.background(PixelTheme.canvas)
                .navigationTitle("回顾").navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: endDay) { _, _ in trendEnd = nil }
        .onChange(of: trendRequest) { _, _ in trendEnd = nil }
    }
    private var picker: some View {
        Picker("回顾方式", selection: $section) { Text("日历").tag("日历"); Text("趋势").tag("趋势") }
    }
    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize { picker.pickerStyle(.menu).frame(minHeight: 44) }
        else {
            HStack(spacing: 0) {
                ForEach(["日历", "趋势"], id: \.self) { value in
                    Button { section = value } label: {
                        Text(value).font(.subheadline).fontWeight(section == value ? .semibold : .regular)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(section == value ? PixelTheme.canvas : PixelTheme.subtle)
                            .background(section == value ? Color.primary : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }.accessibilityAddTraits(section == value ? [.isSelected] : [])
                }
            }.buttonStyle(.plain).padding(4).background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 24) {
            rangePicker
            pager(start: chartEnd.adding(days: 1 - rangeCount), end: chartEnd, canNext: chartEnd < today) { delta in
                trendEnd = min(chartEnd.adding(days: delta * rangeCount), today)
            }
            VStack(alignment: .leading, spacing: 36) {
                ReviewChart(days: days, metric: .intake)
                ReviewChart(days: days, metric: .training)
            }
        }
    }
    private var rangeControl: some View {
        Picker("趋势范围", selection: $rangeCount) { Text("7 天").tag(7); Text("30 天").tag(30) }
    }
    @ViewBuilder private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize { rangeControl.pickerStyle(.menu).frame(minHeight: 44) }
        else {
            HStack(spacing: 4) {
                ForEach([7, 30], id: \.self) { count in
                    Button { rangeCount = count } label: {
                        Text("\(count) 天").font(.subheadline).frame(minWidth: 56, minHeight: 44)
                            .foregroundStyle(rangeCount == count ? Color.primary : PixelTheme.subtle)
                            .background(rangeCount == count ? PixelTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }.accessibilityAddTraits(rangeCount == count ? [.isSelected] : [])
                }
            }.buttonStyle(.plain)
        }
    }
    private var calendar: some View {
        let reviews = calendarDays.map { ReviewRules.day($0, in: state) }
        return VStack(alignment: .leading, spacing: 24) {
            pager(start: calendarDays[0], end: min(calendarDays[90], today), canNext: calendarOffset > 0) { delta in
                calendarOffset = max(0, calendarOffset - delta)
            }
            VStack(alignment: .leading, spacing: 36) {
                ReviewContributionGrid(days: reviews, today: today, isMeal: true)
                ReviewContributionGrid(days: reviews, today: today, isMeal: false)
            }
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                legend("未记录", color: PixelTheme.surface)
                legend("已记录", color: .primary)
            }.font(.caption2).foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
        }
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10); Text(title) }
    }
    private func pager(start: LocalDay, end: LocalDay, canNext: Bool, move: @escaping (Int) -> Void) -> some View {
        let canPrevious = earliest.map { $0 < start } ?? false
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { period(start, end); Spacer(minLength: 0); pageButtons(canPrevious, canNext, move) }
            VStack(alignment: .leading, spacing: 4) { period(start, end); HStack { Spacer(); pageButtons(canPrevious, canNext, move) } }
        }
    }
    private func period(_ start: LocalDay, _ end: LocalDay) -> some View {
        Text(ReviewPresentation.period(start, end)).font(.caption).foregroundStyle(PixelTheme.subtle)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("review.period")
    }
    private func pageButtons(_ previous: Bool, _ next: Bool, _ move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Button("上一段") { move(-1) }.disabled(!previous).accessibilityIdentifier("review.previous")
            Button("下一段") { move(1) }.disabled(!next).accessibilityIdentifier("review.next")
        }.buttonStyle(ReviewPageButtonStyle()).fixedSize(horizontal: true, vertical: false)
    }
}

private struct ReviewPageButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption).foregroundStyle(Color.primary)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .opacity(!isEnabled ? 0.3 : configuration.isPressed ? 0.5 : 1)
    }
}

private struct ReviewContributionGrid: View {
    let days: [DayReview]
    let today: LocalDay
    let isMeal: Bool
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var monthHeight: CGFloat = 22
    private var title: String { isMeal ? "饮食" : "训练" }
    private var key: String { isMeal ? "meal" : "workout" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            GeometryReader { geometry in
                let cell = max(1, (geometry.size.width - min(labelWidth, 28) - 6 - 48) / 13)
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: 4) {
                        ForEach(0..<7) { index in
                            Text(["一", "", "三", "", "五", "", "日"][index]).font(.caption2)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .frame(width: min(labelWidth, 28), height: cell, alignment: .leading)
                        }
                    }.padding(.top, min(monthHeight, 32)).foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(0..<13) { week in
                            VStack(spacing: 0) {
                                Text(monthLabel(week)).font(.caption2).foregroundStyle(PixelTheme.subtle)
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: cell, height: min(monthHeight, 32), alignment: week >= 11 ? .trailing : .leading).accessibilityHidden(true)
                                VStack(spacing: 4) {
                                    ForEach(0..<7) { weekday in
                                        let day = days[week * 7 + weekday]
                                        let recorded = isMeal ? day.mealCount > 0 : day.workoutCount > 0
                                        RoundedRectangle(cornerRadius: 3).fill(recorded ? Color.primary : PixelTheme.surface)
                                            .frame(width: cell, height: cell).opacity(day.day > today ? 0 : 1)
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel(day.day.description + "，" + title + (recorded ? "已记录" : "未记录"))
                                            .accessibilityIdentifier("review.cell." + key + "." + day.day.description)
                                            .accessibilityHidden(day.day > today)
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear { availableWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in availableWidth = width }
            }.frame(height: gridHeight)
        }
    }
    @State private var availableWidth: CGFloat = 0
    // The grid's intrinsic height follows its available width, including on small phones.
    private var gridHeight: CGFloat { 7 * max(1, (availableWidth - min(labelWidth, 28) - 6 - 48) / 13) + 24 + min(monthHeight, 32) }
    private func monthLabel(_ week: Int) -> String {
        let day = days[week * 7].day
        if week == 0 && days[7].day.month != day.month { return "" }
        return week == 0 || day.month != days[(week - 1) * 7].day.month ? "\(day.month)月" : ""
    }
}
