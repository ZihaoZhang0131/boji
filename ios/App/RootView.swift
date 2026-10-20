import SwiftUI
import BojiDomain

struct RootView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation: DateNavigation
    @State private var showingCalendar = false
    @State private var workspace: WorkspaceModel
    @State private var confirmingRecovery = false
    @State private var mealEditor: MealEditorModel?
    @State private var mealDetail: MealSelection?
    @State private var workoutEditor: WorkoutEditorModel?
    @State private var workoutDetail: WorkoutSelection?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _navigation = State(initialValue: DateNavigation(clock: dependencies.clock))
        _workspace = State(initialValue: WorkspaceModel(dependencies: dependencies))
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if workspace.isDemo { Text("演示空间 · 不联网、不导出").accessibilityIdentifier("demo.banner") }
                        dateNavigation
                        if workspace.snapshot == nil {
                            if let message = workspace.errorMessage {
                                Text(message)
                                Button("重试打开资料") { Task { await workspace.load() } }
                                Button("恢复上次升级前资料") { confirmingRecovery = true }
                            } else { ProgressView("正在打开资料") }
                        } else if timeline.isEmpty {
                            PixelEmptyState(title: "这天还没有记录", message: "从一餐或一次训练开始。")
                                .accessibilityIdentifier("records.empty")
                        } else {
                            ForEach(timeline) { event in timelineRow(event) }
                            if let state = workspace.snapshot {
                                DisclosureGroup("当天汇总") {
                                    DaySummaryView(review: ReviewRules.day(navigation.selectedDay, in: state)) { value in
                                        await workspace.confirm(navigation.selectedDay, value: value)
                                    }.padding(.vertical)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("薄记")
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("记饮食") { Task { await openMeal() } }.accessibilityIdentifier("meal.new")
                        Button("记训练") { Task { await openWorkout() } }.accessibilityIdentifier("workout.new")
                    }.buttonStyle(PixelButtonStyle()).frame(maxWidth: .infinity).padding()
                        .background(.background).disabled(workspace.snapshot == nil)
                }
            }
            .tabItem { Label("记录", systemImage: "square.and.pencil") }
            ReviewView(workspace: workspace, clock: dependencies.clock, endDay: navigation.selectedDay) { navigation.select($0) }
            .tabItem { Label("回顾", systemImage: "calendar") }
            NavigationStack {
                List {
                    NavigationLink {
                        ProfileView(workspace: workspace, clock: dependencies.clock)
                    } label: { LabeledContent("个人资料", value: workspace.snapshot?.profiles.isEmpty == false ? "查看与修改" : "待填写") }
                    .disabled(workspace.snapshot == nil)
                    .accessibilityIdentifier("profile.link")
                    .accessibilityValue(workspace.snapshot?.profiles.isEmpty == false ? "查看与修改" : "待填写")
                    NavigationLink {
                        GoalView(workspace: workspace, clock: dependencies.clock)
                    } label: { LabeledContent("阶段目标", value: GoalRules.effective(on: LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone), stages: workspace.snapshot?.goals ?? [])?.goal.title ?? "未设置") }
                    .disabled(workspace.snapshot == nil)
                    .accessibilityIdentifier("goal.link")
                    .accessibilityValue(GoalRules.effective(on: LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone), stages: workspace.snapshot?.goals ?? [])?.goal.title ?? "未设置")
                    NavigationLink { AISettingsView(workspace: workspace) } label: {
                        LabeledContent("AI 估算", value: workspace.snapshot?.aiSettings.acceptedPolicy != nil ? "已授权" : (workspace.snapshot?.aiSettings.serviceURL == nil ? "未配置" : "待授权"))
                    }.disabled(workspace.isDemo).accessibilityIdentifier("ai.settings")
                    NavigationLink("导出与 Agent") { ExportView(workspace: workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("export.link")
                    NavigationLink("导入与恢复") { ImportView(workspace: workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("import.link")
                    NavigationLink("目录备份") { BackupView(workspace:workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("backup.link")
                    NavigationLink("回收站") { TrashView(workspace: workspace) }
                    Button(workspace.isDemo ? "退出演示" : "体验演示") { Task { await workspace.toggleDemo() } }
                        .disabled(workspace.session == nil || workspace.isLoading)
                        .accessibilityIdentifier("demo.toggle")
                    if workspace.isDemo { Text("演示内容保存在独立临时空间，不会进入个人备份或 AI 上传。") }
                }
                .navigationTitle("我的")
            }
            .tabItem { Label("我的", systemImage: "person.crop.square") }
        }
        .font(PixelTheme.font())
        .disabled(workspace.isLoading)
        .tint(.primary)
        .task { await workspace.load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await workspace.processEstimation()
                await workspace.processBackup()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .sheet(item: $mealEditor, onDismiss: { finishEditing() }) { model in
            MealEditorView(model: model, workspace: workspace, onSaved: { day in
                try? await workspace.refresh()
                await workspace.requestEstimate(recordID: model.meal.id, automatic: true)
                if day == LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone) { navigation.returnToToday(clock: dependencies.clock) }
                else { navigation.select(day) }
            }, onClosed: { try? await workspace.refresh() })
        }
        .sheet(item: $mealDetail, onDismiss: { finishEditing() }) { selection in
            MealDetailView(id: selection.id, workspace: workspace, clock: dependencies.clock)
                .onAppear { navigation.isEditing = true }
        }
        .sheet(item: $workoutEditor, onDismiss: { finishEditing() }) { model in
            WorkoutEditorView(model: model, onSaved: { day in try? await workspace.refresh(); navigation.select(day) }, onClosed: { try? await workspace.refresh() })
        }
        .sheet(item: $workoutDetail, onDismiss: { finishEditing() }) { selection in
            WorkoutDetailView(id: selection.id, workspace: workspace, clock: dependencies.clock)
                .onAppear { navigation.isEditing = true }
        }
        .confirmationDialog("恢复上次升级前资料？", isPresented: $confirmingRecovery, titleVisibility: .visible) {
            Button("确认恢复") { Task { await workspace.restorePreviousStore() } }
        } message: { Text("仅在存在完整旧版本时切换。升级后的资料目录会保留，请勿卸载应用。") }
        .alert("操作未完成", isPresented: Binding(get: { workspace.errorMessage != nil && workspace.snapshot != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                navigation.refresh(clock: dependencies.clock)
                Task { await workspace.resumeBackup() }
                if workspace.session != nil { Task { do { try await workspace.refresh() } catch { workspace.errorMessage = error.userMessage } } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            navigation.refresh(clock: dependencies.clock)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            navigation.refresh(clock: dependencies.clock)
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker("记录日期", selection: Binding(
                    get: { navigation.selectedDay.date(in: dependencies.clock.timeZone) },
                    set: { navigation.select(LocalDay($0, timeZone: dependencies.clock.timeZone)) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("选择日期")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingCalendar = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var timeline: [TimelineEvent] { workspace.snapshot.map { RecordQuery.timeline(on: navigation.selectedDay, in: $0) } ?? [] }
    private func finishEditing() { navigation.isEditing = false; navigation.refresh(clock: dependencies.clock) }
    @ViewBuilder private func timelineRow(_ event: TimelineEvent) -> some View {
        switch event {
        case .meal(let meal):
            Button { mealDetail = MealSelection(id: meal.id) } label: {
                HStack(alignment: .top) {
                    if let photoID = meal.photoIDs.first { MealThumbnail(photoID: photoID, workspace: workspace) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meal.time.displayTime).foregroundStyle(.secondary)
                        Text(meal.note.isEmpty ? "照片饮食" : meal.note)
                        Text(calories(for: meal)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityIdentifier("meal.row.\(meal.id)")
        case .workout(let workout):
            Button { workoutDetail = WorkoutSelection(id: workout.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.time.displayTime)
                    Text(workout.name.isEmpty ? "训练" : workout.name)
                    Text("\(workout.exercises.flatMap(\.sets).count) 个完成组")
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityIdentifier("workout.row.\(workout.id)")
        }
    }
    private func openWorkout() async {
        do {
            workoutEditor = try await WorkoutEditorModel.open(repository: workspace.activeRepository(), clock: dependencies.clock, day: navigation.selectedDay)
            navigation.isEditing = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private func calories(for meal: Meal) -> String {
        guard let estimate = workspace.snapshot?.estimates.first(where: { $0.id == meal.currentEstimateID && $0.inputRevision == meal.inputRevision && $0.source != .demo }) else { return "待估算" }
        return estimate.totalKcal.description + " kcal · " + estimate.sourceTitle
    }

    private func openMeal(editing: Meal? = nil) async {
        do {
            let repository = try await workspace.activeRepository()
            mealEditor = try await MealEditorModel.open(repository: repository, clock: dependencies.clock, selectedDay: navigation.selectedDay, editing: editing)
            navigation.isEditing = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private var dateNavigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { navigation.select(navigation.selectedDay.adding(days: -1)) } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("前一天")
                Button { showingCalendar = true } label: {
                    Text(navigation.selectedDay.description)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .monospacedDigit().frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("records.date")
                .accessibilityLabel("记录日期")
                .accessibilityValue(navigation.selectedDay.description)
                Button { navigation.select(navigation.selectedDay.adding(days: 1)) } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("后一天")
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text("现在 " + RecordTime(clock: dependencies.clock).displayTime)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !navigation.followsToday {
                    Button("回到今天") { navigation.returnToToday(clock: dependencies.clock) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("records.today")
                }
            }
        }
        .buttonStyle(PixelButtonStyle())
    }
}
