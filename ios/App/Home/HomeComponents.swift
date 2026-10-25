import SwiftUI
import BojiDomain

/// Presentation only: no categories or derived values are written back to records.
enum HomePresentation {
    enum Region: String {
        case upper, lower, core, full, unknown
        var title: String {
            switch self {
            case .upper: "上肢训练"
            case .lower: "下肢训练"
            case .core: "核心训练"
            case .full: "全身训练"
            case .unknown: "训练"
            }
        }
        var symbol: String {
            switch self {
            case .upper: "figure.strengthtraining.traditional"
            case .lower: "figure.strengthtraining.functional"
            case .core: "figure.core.training"
            case .full: "figure.stand"
            case .unknown: "dumbbell"
            }
        }
    }
    static func dates(around today: LocalDay) -> [LocalDay] { (-15...15).map { today.adding(days: $0) } }
    static func mealCategory(_ slot: String?) -> String {
        if let slot, ["早餐", "午餐", "晚餐", "加餐"].contains(slot) { return slot }
        return slot == "下午茶" ? "加餐" : "饮食"
    }
    private static func region(in text: String) -> Region? {
        let text = text.lowercased()
        func contains(_ terms: [String]) -> Bool { terms.contains { text.contains($0) } }
        func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if contains(["全身"]) || matches(#"\bfull[ -]?body\b"#) { return .full }
        let upper = contains(["上肢", "胸", "肩", "背", "手臂", "二头", "三头", "卧推", "推举", "划船", "引体", "俯卧撑"])
            || matches(#"\b(?:upper|bench|shoulder press|overhead press|chest press|rows?|pull[ -]?ups?|push[ -]?ups?|biceps?|hammer curls?|triceps?)\b"#)
        let lower = contains(["下肢", "腿", "臀", "深蹲", "硬拉", "弓步", "提踵"])
            || matches(#"\b(?:lower|squats?|deadlifts?|lunges?|legs?|hips?|calf)\b"#)
        if upper && lower { return .full }
        if upper { return .upper }
        if lower { return .lower }
        return contains(["核心", "腹", "平板支撑", "卷腹"]) || matches(#"\b(?:core|planks?|crunch(?:es)?)\b"#) ? .core : nil
    }
    static func region(_ workout: Workout) -> Region {
        region(in: workout.name) ?? region(in: workout.exercises.map(\.name).joined(separator: " ")) ?? .unknown
    }
    static func number(_ value: Decimal?) -> String {
        value.map { String(EnergyRules.rounded($0)) } ?? "—"
    }
    struct Entry: Identifiable {
        let event: TimelineEvent
        var id: String { event.id }
    }
    static func entries(on day: LocalDay, in state: DatasetSnapshot) -> [Entry] {
        RecordQuery.timeline(on: day, in: state).map { Entry(event: $0) }
    }
}

struct HomeDateStrip: View {
    let today: LocalDay
    let selectedDay: LocalDay
    let timeZone: TimeZone
    let onSelect: (LocalDay) -> Void
    @State private var centered = false
    @ScaledMetric(relativeTo: .title3) private var daySize = 20
    @ScaledMetric(relativeTo: .title3) private var dayDiameter = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "\(selectedDay.year)年\(selectedDay.month)月\(selectedDay.day)日，\(weekday(selectedDay))")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("records.date")
                .accessibilityValue(selectedDay.description)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(HomePresentation.dates(around: today), id: \.self) { day in
                            Button { onSelect(day) } label: {
                                Text(String(day.day))
                                    .font(.system(size: daySize, weight: .medium)).monospacedDigit()
                                    .frame(width: max(44, dayDiameter), height: max(44, dayDiameter))
                                    .foregroundStyle(day == selectedDay ? PixelTheme.canvas : Color.primary)
                                    .background(day == selectedDay ? Color.primary : PixelTheme.surface, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .id(day)
                            .accessibilityLabel("\(day.description) \(weekday(day))\(day == today ? " 今天" : "")")
                            .accessibilityIdentifier("home.date.\(day.description)")
                            .accessibilityAddTraits(day == selectedDay ? [.isSelected] : [])
                        }
                    }.padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("home.dates")
                .onAppear {
                    if !centered {
                        reader.scrollTo(selectedDay, anchor: .center)
                        centered = true
                    }
                }
                .onChange(of: today) { _, _ in reader.scrollTo(selectedDay, anchor: .center) }
            }
        }
    }
    private func weekday(_ day: LocalDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: day.date(in: timeZone)) - 1]
    }
}

struct HomeEnergySummary: View {
    let review: DayReview
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var numberSize = 30

    var body: some View {
        Button(action: onOpen) {
            layout {
                metric(review.pendingMeals > 0 ? "已知摄入" : "摄入",
                       value: review.mealCount > review.pendingMeals ? HomePresentation.number(review.knownIntakeKcal) : "—",
                       identifier: "home.intake")
                if dynamicTypeSize.isAccessibilitySize { Divider() }
                else { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 50) }
                metric(review.pendingWorkouts > 0 ? "已知训练消耗" : "训练消耗",
                       value: review.workoutCount > review.pendingWorkouts ? String(review.knownWorkoutKcal) : "—",
                       identifier: "home.burn")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.energy")
        .accessibilityHint("查看所选日期的热量趋势，训练消耗为净消耗估算")
    }
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 20))
    }
    private func metric(_ title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(PixelTheme.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: numberSize, weight: .semibold)).monospacedDigit()
                    .minimumScaleFactor(0.65).lineLimit(1)
                    .accessibilityIdentifier(identifier)
                Text("kcal").font(.caption).foregroundStyle(PixelTheme.subtle)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeRecordRow: View {
    let entry: HomePresentation.Entry
    let state: DatasetSnapshot
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var title: String {
        switch entry.event {
        case .meal(let meal): HomePresentation.mealCategory(meal.slot)
        case .workout(let workout): HomePresentation.region(workout).title
        }
    }
    private var symbol: String {
        switch entry.event {
        case .meal: "fork.knife"
        case .workout(let workout): HomePresentation.region(workout).symbol
        }
    }
    private var value: String? {
        switch entry.event {
        case .meal(let meal):
            return ReviewRules.effectiveEstimate(for: meal, in: state).map { HomePresentation.number($0.totalKcal) }
        case .workout(let workout):
            guard let kcal = workout.energyHistory.first(where: { $0.id == workout.currentEnergyID })?.kcal, kcal >= 0 else { return nil }
            return String(kcal)
        }
    }
    private var identifier: String {
        switch entry.event {
        case .meal(let meal): "meal.row.\(meal.id)"
        case .workout(let workout): "workout.row.\(workout.id)"
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 26, weight: .medium)).frame(width: 28)
                    .accessibilityHidden(true)
                contentLayout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        Text(entry.event.time.displayTime).font(.footnote).foregroundStyle(PixelTheme.subtle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let value {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                            Text("kcal").font(.caption).foregroundStyle(PixelTheme.subtle)
                        }
                    } else { Text("待估算").font(.footnote).foregroundStyle(PixelTheme.subtle) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(PixelTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(entry.event.time.displayTime)，\(value.map { $0 + " kcal" } ?? "待估算")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开记录，查看或修改内容")
        .accessibilityIdentifier(identifier)
    }
    private var contentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
}
