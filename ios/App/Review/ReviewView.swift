import SwiftUI
import BojiDomain

struct ReviewView: View {
    let workspace: WorkspaceModel
    let clock: any AppClock
    let endDay: LocalDay
    let selectDay: (LocalDay) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section = "概览"
    @State private var rangeCount = 7
    @State private var detailDay: LocalDay?
    @State private var search = ""
    @State private var photosOnly = false
    @State private var meal: MealSelection?
    @State private var workout: WorkoutSelection?
    private var state: DatasetSnapshot { workspace.snapshot ?? DatasetSnapshot() }
    private var days: [DayReview] { (try? ReviewRules.range(ending: endDay, count: rangeCount, in: state).days) ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionPicker
                    if state.activeMeals.isEmpty && state.activeWorkouts.isEmpty {
                        Text("回顾从记录开始")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("review.empty")
                    }
                    switch section {
                    case "概览": overview
                    case "日历": calendar
                    case "饮食": meals
                    default: workouts
                    }
                }.padding()
            }
            .background(PixelTheme.canvas)
            .navigationTitle("回顾")
        }
        .sheet(item: $meal) {
            MealDetailView(id: $0.id, workspace: workspace, clock: clock)
                .onDisappear { Task { try? await workspace.refresh() } }
        }
        .sheet(item: $workout) {
            WorkoutDetailView(id: $0.id, workspace: workspace, clock: clock)
                .onDisappear { Task { try? await workspace.refresh() } }
        }
        .onChange(of: endDay) { _, _ in detailDay = nil }
    }

    private var picker: some View {
        Picker("回顾方式", selection: $section) {
            ForEach(["概览", "日历", "饮食", "训练"], id: \.self) { Text($0).tag($0) }
        }
    }

    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize { picker.pickerStyle(.menu) }
        else { picker.pickerStyle(.segmented) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 12) {
                DatePicker("截至日期", selection: dateBinding, displayedComponents: .date)
                Picker("天数", selection: $rangeCount) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }.pickerStyle(.segmented)
            }
            if let range = try? ReviewRules.range(ending: endDay, count: rangeCount, in: state) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("日均摄入：" + (range.averageIntakeKcal.map { "\(EnergyRules.rounded($0)) kcal" } ?? "未知"))
                        .font(PixelTheme.font(22, relativeTo: .title2))
                        .monospacedDigit()
                    Text("仅使用 \(range.completeDayCount) 个完整统计日")
                        .font(PixelTheme.font(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
                ReviewChart(days: range.days, selected: detailDay ?? endDay) { detailDay = $0 }.id(rangeCount)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text((detailDay ?? endDay).description)
                    .font(PixelTheme.font(16, relativeTo: .headline))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.selectedDay")
                summary(detailDay ?? endDay)
            }
            DisclosureGroup("逐日数值表") {
                VStack(spacing: 0) {
                    ForEach(days) { value in
                        dayRow(value)
                        if value.id != days.last?.id { Divider() }
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("统计说明") {
                VStack(alignment: .leading, spacing: 12) {
                    if let range = try? ReviewRules.range(ending: endDay, count: rangeCount, in: state) {
                        Text("范围内已知训练净消耗 \(range.knownWorkoutKcal) kcal，\(range.pendingWorkoutCount) 次待估算")
                    }
                    Text("完整统计须已确认记全、至少一餐，且所有餐食和已完成训练都有有效热量。缺资料时总消耗与差值未知。阶段按当天归属；草稿、回收站及演示内容均不计入。")
                }
                .font(PixelTheme.font(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
        }
    }

    private func dayRow(_ value: DayReview) -> some View {
        let burn = value.totalBurnKcal.map { String($0) + " kcal" } ?? "未知"
        let difference = value.differenceKcal.map { $0.description + " kcal" } ?? "未知"
        let energyDescription = "消耗 \(burn) · 差值 \(difference)"
        let intake: String
        if value.mealCount == 0 { intake = "摄入 —" }
        else if value.pendingMeals == value.mealCount { intake = "摄入待估算" }
        else { intake = "已知摄入 \(value.knownIntakeKcal.description) kcal" }

        return Button { detailDay = value.day } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(value.day.description)
                    Spacer()
                    Text(value.complete ? "已记全" : "未完整").foregroundStyle(.secondary)
                }
                Text(intake)
                Text(energyDescription).foregroundStyle(.secondary)
                if !value.missingReasons.isEmpty {
                    Text(value.missingReasons.joined(separator: "；"))
                        .font(PixelTheme.font(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 12)
        }.buttonStyle(.plain)
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { endDay.date(in: clock.timeZone) }, set: { selectDay(LocalDay($0, timeZone: clock.timeZone)) })
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 24) {
            DatePicker("按月查记录", selection: dateBinding, displayedComponents: .date).datePickerStyle(.graphical)
            Text(endDay.description).foregroundStyle(.secondary)
            summary(endDay)
            let events = RecordQuery.timeline(on: endDay, in: state)
            if events.isEmpty { Text("这天没有正式记录").foregroundStyle(.secondary) }
            else { RecordGrid(events: events, workspace: workspace, onSelect: selectRecord) }
        }
    }

    private var meals: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("搜索备注、餐次或标签", text: $search)
                        .accessibilityIdentifier("review.search")
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 12)
                .background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Toggle("只看有照片的饮食", isOn: $photosOnly)
            }
            let results = RecordQuery.meals(search: search, photosOnly: photosOnly, in: state)
            if results.isEmpty { Text("没有匹配的饮食记录").foregroundStyle(.secondary) }
            else { recordGroups(results.map(TimelineEvent.meal)) }
        }
    }

    private var workouts: some View {
        VStack(alignment: .leading, spacing: 20) {
            let values = state.activeWorkouts.sorted { ($0.time.localDay, $0.time.hour, $0.time.minute, $0.id.uuidString) > ($1.time.localDay, $1.time.hour, $1.time.minute, $1.id.uuidString) }
            if values.isEmpty { Text("还没有完成的训练").foregroundStyle(.secondary) }
            else { recordGroups(values.map(TimelineEvent.workout)) }
        }
    }

    private func recordGroups(_ events: [TimelineEvent]) -> some View {
        let dates = Set(events.map { $0.time.localDay }).sorted(by: >)
        return LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(dates, id: \.self) { date in
                VStack(alignment: .leading, spacing: 12) {
                    Text(date.description)
                        .font(PixelTheme.font(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                    RecordGrid(events: events.filter { $0.time.localDay == date }, workspace: workspace, onSelect: selectRecord)
                }
            }
        }
    }

    private func summary(_ day: LocalDay) -> some View {
        DaySummaryView(review: ReviewRules.day(day, in: state)) { value in await workspace.confirm(day, value: value) }
    }

    private func selectRecord(_ event: TimelineEvent) {
        switch event {
        case .meal(let value): meal = MealSelection(id: value.id)
        case .workout(let value): workout = WorkoutSelection(id: value.id)
        }
    }
}
