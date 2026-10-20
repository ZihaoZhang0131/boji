import SwiftUI
import BojiDomain

struct ReviewView: View {
    let workspace: WorkspaceModel
    let clock: any AppClock
    let endDay: LocalDay
    let selectDay: (LocalDay) -> Void
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
                    Picker("回顾方式", selection: $section) { ForEach(["概览", "日历", "饮食", "训练"], id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.segmented)
                    if state.activeMeals.isEmpty && state.activeWorkouts.isEmpty {
                        Text("回顾从记录开始").accessibilityIdentifier("review.empty")
                    }
                    switch section {
                    case "概览": overview
                    case "日历": calendar
                    case "饮食": meals
                    default: workouts
                    }
                }.padding()
            }.navigationTitle("回顾")
        }
        .sheet(item: $meal) { MealDetailView(id: $0.id, workspace: workspace, clock: clock).onDisappear { Task { try? await workspace.refresh() } } }
        .sheet(item: $workout) { WorkoutDetailView(id: $0.id, workspace: workspace, clock: clock) }
        .onChange(of: endDay) { _, _ in detailDay = nil }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            DatePicker("截至日期", selection: dateBinding, displayedComponents: .date)
            Picker("天数", selection: $rangeCount) { Text("7 天").tag(7); Text("30 天").tag(30) }.pickerStyle(.segmented)
            if let range = try? ReviewRules.range(ending: endDay, count: rangeCount, in: state) {
                Text("日均摄入：" + (range.averageIntakeKcal.map { "\(EnergyRules.rounded($0)) kcal" } ?? "未知"))
                Text("仅使用 \(range.completeDayCount) 个完整统计日")
                Text("范围内已知训练净消耗 \(range.knownWorkoutKcal) kcal，\(range.pendingWorkoutCount) 次待估算")
                ReviewChart(days: range.days, selected: detailDay ?? endDay) { detailDay = $0 }.id(rangeCount)
            }
            Text((detailDay ?? endDay).description).font(.headline).accessibilityIdentifier("review.selectedDay")
            summary(detailDay ?? endDay)
            DisclosureGroup("逐日数值表") {
                ForEach(days) { value in
                    Button { detailDay = value.day } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(value.day.description)
                            Text("已知摄入 \(value.knownIntakeKcal.description) kcal · " + (value.complete ? "完整" : "未完整"))
                            Text("消耗 " + (value.totalBurnKcal.map { "\($0) kcal" } ?? "未知"))
                            Text("差值 " + (value.differenceKcal.map { $0.description + " kcal" } ?? "未知"))
                            Text(value.missingReasons.joined(separator: "；"))
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
            }
            Text("口径：完整统计须已确认记全、至少一餐，且所有餐食和已完成训练都有有效热量。缺资料时总消耗与差值未知。阶段按当天归属；草稿、回收站及演示内容均不计入。")
                .font(.footnote)
        }
    }
    private var dateBinding: Binding<Date> {
        Binding(get: { endDay.date(in: clock.timeZone) }, set: { selectDay(LocalDay($0, timeZone: clock.timeZone)) })
    }
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 20) {
            DatePicker("按月查记录", selection: dateBinding, displayedComponents: .date).datePickerStyle(.graphical)
            Text(endDay.description)
            summary(endDay)
            ForEach(RecordQuery.timeline(on: endDay, in: state)) { event in eventButton(event) }
            if RecordQuery.timeline(on: endDay, in: state).isEmpty { Text("这天没有正式记录") }
        }
    }
    private var meals: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("搜索备注、餐次或标签", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("review.search")
            Toggle("只看有照片的饮食", isOn: $photosOnly)
            let results = RecordQuery.meals(search: search, photosOnly: photosOnly, in: state)
            if results.isEmpty { Text("没有匹配的饮食记录") }
            ForEach(results) { value in
                Button { meal = MealSelection(id: value.id) } label: {
                    HStack(alignment: .top) {
                        if let photoID = value.photoIDs.first { MealThumbnail(photoID: photoID, workspace: workspace) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(value.time.localDay.description + " " + value.time.displayTime)
                            Text(value.note.isEmpty ? "照片饮食" : value.note)
                            Text(value.tags.joined(separator: " · "))
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }
    private var workouts: some View {
        VStack(alignment: .leading, spacing: 16) {
            let values = state.activeWorkouts.sorted { ($0.time.localDay, $0.time.hour, $0.time.minute, $0.id.uuidString) > ($1.time.localDay, $1.time.hour, $1.time.minute, $1.id.uuidString) }
            if values.isEmpty { Text("还没有完成的训练") }
            ForEach(values) { eventButton(.workout($0)) }
        }
    }
    private func summary(_ day: LocalDay) -> some View {
        DaySummaryView(review: ReviewRules.day(day, in: state)) { value in await workspace.confirm(day, value: value) }
    }
    private func eventButton(_ event: TimelineEvent) -> some View {
        Button {
            switch event { case .meal(let value): meal = MealSelection(id: value.id); case .workout(let value): workout = WorkoutSelection(id: value.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.time.localDay.description + " " + event.time.displayTime)
                switch event { case .meal(let value): Text(value.note.isEmpty ? "照片饮食" : value.note); case .workout(let value): Text(value.name.isEmpty ? "训练" : value.name) }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain)
    }
}

struct MealThumbnail: View {
    let photoID: UUID
    let workspace: WorkspaceModel
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").resizable().scaledToFit().padding() }
        }.frame(width: 64, height: 64).clipped().accessibilityHidden(true)
            .task(id: photoID) {
                guard let photo = workspace.snapshot?.photos.first(where: { $0.id == photoID }) else { return }
                do { let repository = try await workspace.activeRepository(); image = UIImage(data: try await repository.thumbnail(photo)) } catch { image = nil }
            }
    }
}
