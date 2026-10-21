import SwiftUI
import BojiDomain

struct RootView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var navigation: DateNavigation
    @State private var showingCalendar = false
    @State private var workspace: WorkspaceModel
    @State private var confirmingRecovery = false
    @State private var mealEditor: MealEditorModel?
    @State private var mealDetail: MealSelection?
    @State private var workoutEditor: WorkoutEditorModel?
    @State private var pendingWorkout: Workout?
    @State private var workoutConflict = false

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
                        if workspace.isDemo {
                            Text("演示空间 · 不联网、不导出")
                                .font(PixelTheme.font(13, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("demo.banner")
                        }
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
                            RecordGrid(events: timeline, workspace: workspace, onSelect: openRecord)
                            if let state = workspace.snapshot {
                                DisclosureGroup("当天汇总") {
                                    DaySummaryView(review: ReviewRules.day(navigation.selectedDay, in: state)) { value in
                                        await workspace.confirm(navigation.selectedDay, value: value)
                                    }.padding(.top, 16)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }
                .background(PixelTheme.canvas)
                .navigationTitle("薄记")
                .safeAreaInset(edge: .bottom) {
                    actionLayout {
                        Button { Task { await openMeal() } } label: {
                            Label("记饮食", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.accessibilityIdentifier("meal.new")
                        Button { Task { await openWorkout() } } label: {
                            Label("记训练", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.accessibilityIdentifier("workout.new")
                    }.buttonStyle(PixelButtonStyle()).padding(.horizontal).padding(.vertical, 12)
                        .background(PixelTheme.canvas).disabled(workspace.snapshot == nil)
                }
            }
            .tabItem { Label("记录", systemImage: "square.and.pencil") }
            ReviewView(workspace: workspace, clock: dependencies.clock, endDay: navigation.selectedDay) { navigation.select($0) }
            .tabItem { Label("回顾", systemImage: "calendar") }
            NavigationStack {
                List {
                    Section("个人") {
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
                    }
                    Section("估算") {
                    NavigationLink { AISettingsView(workspace: workspace) } label: {
                        LabeledContent("AI 估算", value: workspace.snapshot?.aiSettings.acceptedPolicy != nil ? "已授权" : (workspace.snapshot?.aiSettings.serviceURL == nil ? "未配置" : "待授权"))
                    }.disabled(workspace.isDemo).accessibilityIdentifier("ai.settings")
                    }
                    Section("资料") {
                    NavigationLink("导出与 Agent") { ExportView(workspace: workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("export.link")
                    NavigationLink("导入与恢复") { ImportView(workspace: workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("import.link")
                    NavigationLink("目录备份") { BackupView(workspace:workspace) }.disabled(workspace.isDemo || workspace.snapshot == nil).accessibilityIdentifier("backup.link")
                    NavigationLink("回收站") { TrashView(workspace: workspace) }
                    }
                    Section {
                    Button(workspace.isDemo ? "退出演示" : "体验演示") { Task { await workspace.toggleDemo() } }
                        .disabled(workspace.session == nil || workspace.isLoading)
                        .accessibilityIdentifier("demo.toggle")
                    if workspace.isDemo { Text("演示内容保存在独立临时空间，不会进入个人备份或 AI 上传。") }
                    }
                }
                .bojiForm()
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
        .sheet(item: $workoutEditor, onDismiss: {
            if workoutEditor == nil { finishEditing() }
            else { navigation.isEditing = true }
        }) { model in
            WorkoutEditorView(model: model,
                              onSaved: { day in try? await workspace.refresh(); navigation.select(day) },
                              onClosed: { try? await workspace.refresh() },
                              workspace: workspace, clock: dependencies.clock,
                              onReplaceEditor: { workoutEditor = $0; navigation.isEditing = true },
                              onRecordRemoved: { workoutEditor = nil })
                .id(model.id)
        }
        .confirmationDialog("已有进行中的训练草稿", isPresented: $workoutConflict, titleVisibility: .visible) {
            Button("继续已有草稿") { pendingWorkout = nil; Task { await openWorkout() } }
            Button("放弃旧草稿并编辑这次训练", role: .destructive) { Task { await discardWorkoutDraftAndOpen() } }
            Button("取消", role: .cancel) { pendingWorkout = nil }
        } message: { Text("每次只保留一个活动训练。旧草稿不会被覆盖；放弃后，其未保存为正式训练的修改将丢弃。") }
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
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }
    private func finishEditing() { navigation.isEditing = false; navigation.refresh(clock: dependencies.clock) }
    private func openRecord(_ event: TimelineEvent) {
        switch event {
        case .meal(let meal):
            mealDetail = MealSelection(id: meal.id)
        case .workout(let workout):
            Task { await openWorkout(editing: workout) }
        }
    }
    private func openWorkout(editing: Workout? = nil) async {
        do {
            workoutEditor = try await WorkoutEditorModel.open(repository: workspace.activeRepository(), clock: dependencies.clock, day: editing?.time.localDay ?? navigation.selectedDay, editing: editing)
            pendingWorkout = nil
            navigation.isEditing = true
        } catch WorkoutEditorError.activeDraft {
            pendingWorkout = editing
            workoutConflict = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private func discardWorkoutDraftAndOpen() async {
        let target = pendingWorkout
        do {
            let repository = try await workspace.activeRepository()
            if let draft = try await repository.snapshot().drafts.first(where: { $0.content.kind == .workout }) {
                try await repository.discardDraft(id: draft.id, at: dependencies.clock.now, operationID: UUID())
            }
            try await workspace.refresh()
            await openWorkout(editing: target)
        } catch { workspace.errorMessage = error.userMessage }
    }

    private func openMeal(editing: Meal? = nil) async {
        do {
            let repository = try await workspace.activeRepository()
            mealEditor = try await MealEditorModel.open(repository: repository, clock: dependencies.clock, selectedDay: navigation.selectedDay, editing: editing)
            navigation.isEditing = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private var dateNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { navigation.select(navigation.selectedDay.adding(days: -1)) } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("前一天")
                Button { showingCalendar = true } label: {
                    Text(navigation.selectedDay.description)
                        .font(PixelTheme.font(20, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit().frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("records.date")
                .accessibilityLabel("记录日期")
                .accessibilityValue(navigation.selectedDay.description)
                Button { navigation.select(navigation.selectedDay.adding(days: 1)) } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("后一天")
            }
            if !navigation.followsToday && navigation.selectedDay != LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone) {
                Button { navigation.returnToToday(clock: dependencies.clock) } label: {
                    Text("回到今天")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("records.today")
            }
        }
        .buttonStyle(.plain)
    }
}
