import SwiftUI
import BojiDomain

struct GoalView: View {
    let workspace: WorkspaceModel
    let clock: any AppClock
    @State private var selected: Goal?
    @State private var startDate: Date
    @State private var note = ""
    @State private var error: String?
    @State private var saving = false
    @State private var operationID = UUID()
    @State private var stageID = UUID()
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(workspace: WorkspaceModel, clock: any AppClock) {
        self.workspace = workspace; self.clock = clock
        let current = GoalRules.effective(on: LocalDay(clock.now, timeZone: clock.timeZone), stages: workspace.snapshot?.goals ?? [])
        _selected = State(initialValue: current?.goal)
        _startDate = State(initialValue: current?.startDay.date(in: clock.timeZone) ?? clock.now)
        _note = State(initialValue: current?.note ?? "")
    }

    var body: some View {
        Form {
            Section("当前阶段") {
                Picker("阶段目标", selection: $selected) {
                    Text("请选择").tag(Goal?.none)
                    ForEach(Goal.allCases, id: \.self) { Text($0.title).tag(Goal?.some($0)) }
                }
                .accessibilityIdentifier("goal.choice")
                .accessibilityValue(selected?.title ?? "请选择")
                DatePicker("开始日期", selection: $startDate, in: ...clock.now, displayedComponents: .date)
                TextField("阶段备注", text: $note, axis: .vertical).lineLimit(2...6).accessibilityLabel("阶段备注")
                    .focused($noteFocused)
                Text("记录当前阶段，不自动设定摄入量。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            if let error { Text(error) }
            Button(saving ? "正在保存" : "保存阶段") { Task { await save() } }
                .disabled(saving || selected == nil).frame(minHeight: 44)
            Section {
                DisclosureGroup("阶段历史") {
                    if let goals = workspace.snapshot?.goals, !goals.isEmpty {
                        ForEach(goals.sorted { $0.sequence > $1.sequence }) { goal in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.goal.title)
                                Text(goal.startDay.description + " — " + (goal.endDay.map { $0.description + " 前" } ?? "至今"))
                                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
                                if !goal.note.isEmpty { Text(goal.note).font(.footnote) }
                            }
                        }
                    } else { Text("还没有阶段目标") }
                    Text("仅改备注不会新增阶段。")
                        .font(.footnote).foregroundStyle(PixelTheme.subtle)
                }
            }
        }
        .bojiForm()
        .navigationTitle("阶段目标")
        .scrollDismissesKeyboard(.interactively)
        .recordingKeyboard { noteFocused = false }
    }
    private func save() async {
        guard let selected, !saving else { return }
        saving = true; defer { saving = false }
        do {
            let repository = try await workspace.activeRepository()
            try await repository.saveGoal(selected, start: LocalDay(startDate, timeZone: clock.timeZone), note: note,
                                          today: LocalDay(clock.now, timeZone: clock.timeZone), operationID: operationID, stageID: stageID)
            try await workspace.refresh(); dismiss()
        } catch { self.error = error.userMessage }
    }
}
