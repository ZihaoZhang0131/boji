import SwiftUI
import BojiDomain

struct RootView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var navigation: DateNavigation
    @State private var selectedTab = "today"
    @State private var reviewSection = "日历"
    @State private var reviewTrendRequest = UUID()
    @State private var homeToday: LocalDay
    @State private var workspace: WorkspaceModel
    @State private var confirmingRecovery = false
    @State private var mealEditor: MealEditorModel?
    @State private var workoutEditor: WorkoutEditorModel?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _navigation = State(initialValue: DateNavigation(clock: dependencies.clock))
        _homeToday = State(initialValue: LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone))
        _workspace = State(initialValue: WorkspaceModel(dependencies: dependencies))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if workspace.isDemo {
                            Text("演示空间 · 不联网、不导出")
                                .font(PixelTheme.font(13, relativeTo: .footnote))
                                .foregroundStyle(PixelTheme.subtle)
                                .accessibilityIdentifier("demo.banner")
                        }
                        HomeDateStrip(today: homeToday, selectedDay: navigation.selectedDay, timeZone: dependencies.clock.timeZone) { day in
                            if day == homeToday { navigation.returnToToday(clock: dependencies.clock) }
                            else { navigation.select(day) }
                        }
                        if let state = workspace.snapshot {
                            HomeEnergySummary(review: ReviewRules.day(navigation.selectedDay, in: state)) {
                                reviewTrendRequest = UUID()
                                reviewSection = "趋势"
                                selectedTab = "review"
                            }
                        }
                        if workspace.snapshot == nil {
                            if let message = workspace.errorMessage {
                                Text(message)
                                Button("重试打开资料") { Task { await workspace.load() } }
                                Button("恢复上次升级前资料") { confirmingRecovery = true }
                            } else { ProgressView("正在打开资料") }
                        } else if homeEntries.isEmpty {
                            PixelEmptyState(title: "这天还没有记录", message: "从一餐或一次训练开始。")
                                .accessibilityIdentifier("records.empty")
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(homeEntries) { entry in
                                    HomeRecordRow(entry: entry, state: workspace.snapshot ?? DatasetSnapshot()) {
                                        openRecord(entry.event)
                                    }
                                }
                            }

                        }
                    }
                    .padding()
                }
                .background(PixelTheme.canvas)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom) {
                    actionLayout {
                        Button { Task { await openMeal() } } label: {
                            Text("记饮食")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.accessibilityIdentifier("meal.new")
                        Button { Task { await openWorkout() } } label: {
                            Text("记训练")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.accessibilityIdentifier("workout.new")
                    }.buttonStyle(PixelButtonStyle()).padding(.horizontal).padding(.vertical, 12)
                        .background(PixelTheme.canvas).disabled(workspace.snapshot == nil)
                }
            }
            .tabItem { Label("记录", systemImage: "square.and.pencil") }.tag("today")
            ReviewView(workspace: workspace, clock: dependencies.clock, today: homeToday, trendRequest: reviewTrendRequest, section: $reviewSection)
            .tabItem { Label("回顾", systemImage: "calendar") }.tag("review")
            NavigationStack {
                mineHome
            }
            .tabItem { Label("我的", systemImage: "person.crop.square") }.tag("library")
        }
        .font(PixelTheme.font())
        .disabled(workspace.isLoading)
        .tint(.primary)
        .task { await workspace.load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Independent from AI requests, which may wait on a slow network.
            while workspace.session == nil && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await workspace.resumeBackup()
            while !Task.isCancelled {
                await workspace.processBackup()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await workspace.processEstimation()
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
        .confirmationDialog("恢复上次升级前资料？", isPresented: $confirmingRecovery, titleVisibility: .visible) {
            Button("确认恢复") { Task { await workspace.restorePreviousStore() } }
        } message: { Text("仅在存在完整旧版本时切换。升级后的资料目录会保留，请勿卸载应用。") }
        .alert("操作未完成", isPresented: Binding(get: { workspace.errorMessage != nil && workspace.snapshot != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshHomeDate()
                if workspace.session != nil { Task { do { try await workspace.refresh() } catch { workspace.errorMessage = error.userMessage } } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshHomeDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshHomeDate()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == "today" { refreshHomeDate() }
        }
    }

    private var mineHome: some View {
        MinePage {
            if workspace.snapshot == nil, let error = workspace.errorMessage {
                MineSection {
                    Text(error).font(.footnote).foregroundStyle(PixelTheme.subtle)
                    Button("重试打开资料") { Task { await workspace.load() } }.buttonStyle(MineActionStyle())
                }
            }
            VStack(spacing: 0) {
                NavigationLink { ProfileView(workspace: workspace, clock: dependencies.clock) } label: {
                    MineNavigationRow(title: "身体资料", status: MinePresentation.profileStatus(workspace.snapshot, today: homeToday, loadingFailed: workspace.errorMessage != nil))
                }.accessibilityIdentifier("profile.link").accessibilityLabel("身体资料")
                    .accessibilityValue(MinePresentation.profileStatus(workspace.snapshot, today: homeToday, loadingFailed: workspace.errorMessage != nil)).disabled(workspace.snapshot == nil)
                Divider()
                NavigationLink { AISettingsView(workspace: workspace) } label: {
                    MineNavigationRow(title: "AI 估算", status: MinePresentation.aiStatus(workspace.snapshot?.aiSettings, loadingFailed: workspace.errorMessage != nil))
                }.accessibilityIdentifier("ai.settings").accessibilityLabel("AI 估算")
                    .accessibilityValue(MinePresentation.aiStatus(workspace.snapshot?.aiSettings, loadingFailed: workspace.errorMessage != nil)).disabled(workspace.isDemo || workspace.snapshot == nil)
                Divider()
                NavigationLink { dataManagement } label: { MineNavigationRow(title: "数据管理") }
                    .accessibilityIdentifier("data.management").disabled(workspace.snapshot == nil)
            }.buttonStyle(.plain)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-demo-controls") {
                Button(workspace.isDemo ? "退出演示" : "体验演示") { Task { await workspace.toggleDemo() } }
                    .buttonStyle(MineActionStyle()).accessibilityIdentifier("demo.toggle")
            }
            #endif
        }.navigationTitle("我的")
    }

    private var dataManagement: some View {
        MinePage {
            VStack(spacing: 0) {
                NavigationLink { BackupView(workspace: workspace) } label: {
                    MineNavigationRow(title: "iCloud 备份", status: BackupPresentation.automaticStatus(workspace.snapshot?.backup ?? BackupState()))
                }.accessibilityIdentifier("backup.link").disabled(workspace.isDemo)
                Divider()
                NavigationLink { ExportView(workspace: workspace) } label: { MineNavigationRow(title: "导出数据") }
                    .accessibilityIdentifier("export.link").disabled(workspace.isDemo)
                Divider()
                NavigationLink { ImportView(workspace: workspace) } label: { MineNavigationRow(title: "导入与恢复") }
                    .accessibilityIdentifier("import.link").disabled(workspace.isDemo)
                Divider()
                NavigationLink { TrashView(workspace: workspace) } label: {
                    let count = MinePresentation.trashCount(workspace.snapshot)
                    MineNavigationRow(title: "回收站", status: count == 0 ? "空" : "\(count) 项")
                }.accessibilityIdentifier("trash.link")
            }.buttonStyle(.plain)
        }.navigationTitle("数据管理")
    }

    private var homeEntries: [HomePresentation.Entry] { workspace.snapshot.map { HomePresentation.entries(on: navigation.selectedDay, in: $0) } ?? [] }
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }
    private func finishEditing() { navigation.isEditing = false; refreshHomeDate() }
    private func openRecord(_ event: TimelineEvent) {
        switch event {
        case .meal(let meal):
            Task { await openMeal(editing: meal) }
        case .workout(let workout):
            Task { await openWorkout(editing: workout) }
        }
    }
    private func openWorkout(editing: Workout? = nil) async {
        do {
            workoutEditor = try await WorkoutEditorModel.open(repository: workspace.activeRepository(), clock: dependencies.clock, day: editing?.time.localDay ?? navigation.selectedDay, editing: editing)
            navigation.isEditing = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private func openMeal(editing: Meal? = nil) async {
        do {
            let repository = try await workspace.activeRepository()
            mealEditor = try await MealEditorModel.open(repository: repository, clock: dependencies.clock, selectedDay: navigation.selectedDay, editing: editing)
            navigation.isEditing = true
        } catch { workspace.errorMessage = error.userMessage }
    }

    private func refreshHomeDate() {
        navigation.refresh(clock: dependencies.clock)
        homeToday = LocalDay(dependencies.clock.now, timeZone: dependencies.clock.timeZone)
        if selectedTab == "today" && !navigation.isEditing && !HomePresentation.dates(around: homeToday).contains(navigation.selectedDay) {
            navigation.returnToToday(clock: dependencies.clock)
        }
    }
}
