import SwiftUI
import BojiDomain

extension View {
    func bojiForm() -> some View {
        scrollContentBackground(.hidden)
            .background(PixelTheme.canvas)
            .font(PixelTheme.font())
    }

    func recordingKeyboard(dismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { dismiss() }
            }
        }
    }
}

enum PixelTheme {
    static let fontName = "Fusion-Pixel-12px-Prop-zh-Hans-Regular"
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.95, alpha: 1) })
    static let subtle = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.68, alpha: 1) : UIColor(white: 0.4, alpha: 1) })
    static let radius: CGFloat = 16
    static func font(_ size: CGFloat = 16, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(style == .body ? (size < 14 ? .footnote : size < 16 ? .subheadline : size < 20 ? .body : size < 24 ? .title3 : .title2) : style)
            .weight(size >= 20 ? .semibold : .regular)
    }
}

struct PixelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : PixelTheme.surface,
                        in: RoundedRectangle(cornerRadius: PixelTheme.radius, style: .continuous))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
    }
}

/// The same quiet visual vocabulary is used in the journal and all review lists.
/// Metadata remains available to VoiceOver without competing with the image and energy.
struct RecordGrid: View {
    let events: [TimelineEvent]
    let workspace: WorkspaceModel
    let onSelect: (TimelineEvent) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(events) { event in
                RecordCard(event: event, workspace: workspace) { onSelect(event) }
            }
        }
    }
}

struct RecordCard: View {
    let event: TimelineEvent
    let workspace: WorkspaceModel
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                media
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 168 : 128)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Text(calories)
                    .font(PixelTheme.font(20, relativeTo: .title3))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            .background(PixelTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PixelTheme.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PixelTheme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("打开记录，查看或修改内容")
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var media: some View {
        switch event {
        case .meal(let meal):
            if let photoID = meal.photoIDs.first {
                MealThumbnail(photoID: photoID, workspace: workspace)
            } else {
                Text(meal.note.isEmpty ? (meal.slot ?? "饮食") : meal.note)
                    .font(.headline).lineLimit(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(16)
            }
        case .workout(let workout):
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.name.isEmpty ? "训练" : workout.name).font(.headline).lineLimit(3)
                Text("\(workout.exercises.flatMap(\.sets).filter(\.completed).count) 组完成")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var calories: String {
        switch event {
        case .meal(let meal):
            guard let state = workspace.snapshot,
                  let estimate = ReviewRules.effectiveEstimate(for: meal, in: state) else { return "待估算" }
            return estimate.totalKcal.description + " kcal"
        case .workout(let workout):
            guard let value = workout.energyHistory.first(where: { $0.id == workout.currentEnergyID }),
                  let kcal = value.kcal, kcal >= 0 else { return "待估算" }
            return "\(kcal) kcal"
        }
    }

    private var identifier: String {
        switch event {
        case .meal(let meal): "meal.row.\(meal.id)"
        case .workout(let workout): "workout.row.\(workout.id)"
        }
    }

    private var accessibilityDescription: String {
        let metadata: String
        switch event {
        case .meal(let meal):
            metadata = ([meal.slot ?? "饮食", meal.note] + meal.tags).filter { !$0.isEmpty }.joined(separator: "，")
        case .workout(let workout):
            metadata = (workout.name.isEmpty ? "训练" : workout.name) + "，\(workout.exercises.flatMap(\.sets).filter(\.completed).count) 个完成组"
        }
        return event.time.localDay.description + " " + event.time.displayTime + "，" + metadata + "，" + calories
    }


}

struct MealThumbnail: View {
    let photoID: UUID
    let workspace: WorkspaceModel
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.system(size: 36, weight: .light))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: photoID) {
            image = nil
            guard let photo = workspace.snapshot?.photos.first(where: { $0.id == photoID }) else { return }
            do {
                let repository = try await workspace.activeRepository()
                image = UIImage(data: try await repository.thumbnail(photo))
            } catch { image = nil }
        }
    }
}

struct PixelEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(PixelTheme.font(24, relativeTo: .title2))
            Text(message).foregroundStyle(PixelTheme.subtle)
        }
        .font(PixelTheme.font())
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

#Preview("像素组件 · 大字号") {
    ScrollView {
        VStack(spacing: 24) {
            PixelEmptyState(title: "这天还没有记录", message: "从一餐或一次训练开始。")
            Button("保存记录") {}.buttonStyle(PixelButtonStyle())
        }.padding()
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("像素组件 · 深色") {
    PixelEmptyState(title: "回顾从记录开始", message: "还没有饮食和训练记录。")
        .preferredColorScheme(.dark)
}

struct RecordingTimePicker: View {
    @Binding var selection: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("时间").foregroundStyle(PixelTheme.subtle)
                // Compact date controls have a fixed intrinsic width; separate them on small screens.
                DatePicker("日期", selection: $selection, displayedComponents: .date)
                    .labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                DatePicker("时间", selection: $selection, displayedComponents: .hourAndMinute)
                    .labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DatePicker("时间", selection: $selection)
                .foregroundStyle(PixelTheme.subtle)
        }
    }
}

struct RecordingSaveBar: View {
    let disabled: Bool
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("保存").font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(PixelTheme.canvas)
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.5 : 1)
        .accessibilityIdentifier(identifier)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
        .background(PixelTheme.canvas)
    }
}

extension View {
    func recordingField() -> some View {
        padding(14).background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
