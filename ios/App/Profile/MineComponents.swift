import SwiftUI
import BojiDomain

enum MinePresentation {
    static func profileStatus(_ state: DatasetSnapshot?, today: LocalDay, loadingFailed: Bool = false) -> String {
        guard let state else { return loadingFailed ? "暂不可用" : "载入中" }
        return ProfileRules.effective(on: today, versions: state.profiles) == nil ? "待填写" : "已填写"
    }
    static func aiStatus(_ settings: AISettings?, loadingFailed: Bool = false) -> String {
        guard let settings else { return loadingFailed ? "暂不可用" : "载入中" }
        guard settings.serviceURL != nil else { return "未配置" }
        guard let policy = settings.cachedPolicy, policy.available else { return "暂不可用" }
        return settings.acceptedPolicy == policy.version ? "已授权" : "待授权"
    }
    static func trashCount(_ state: DatasetSnapshot?) -> Int {
        (state?.meals.filter { $0.deletedAt != nil }.count ?? 0) + (state?.workouts.filter { $0.deletedAt != nil }.count ?? 0)
    }
}

struct MinePage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }.background(PixelTheme.canvas).font(.body).tint(.primary)
            .navigationBarTitleDisplayMode(.inline)
    }
}
struct MineSection<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct MineDisclosure<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) { content }.frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
    }
}
struct MineFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize > .xxxLarge {
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.subheadline); content }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    content
                }
            }
        }.frame(minHeight: 56).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct MineNavigationRow: View {
    let title: String
    var status: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body)
                    if let status { Text(status).font(.footnote).foregroundStyle(PixelTheme.subtle) }
                }
                Spacer(minLength: 0)
            } else {
                Text(title).font(.body)
                Spacer(minLength: 0)
                if let status { Text(status).font(.footnote).foregroundStyle(PixelTheme.subtle) }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
        }.padding(.vertical, 12).frame(minHeight: 64).contentShape(Rectangle())
            .foregroundStyle(.primary).accessibilityElement(children: .combine)
    }
}
struct MineActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(prominent ? .semibold : .regular))
            .padding(.horizontal, prominent ? 16 : 0).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: prominent ? .center : .leading)
            .foregroundStyle(prominent ? PixelTheme.canvas : Color.primary)
            .background(prominent ? Color.primary : configuration.isPressed ? PixelTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle()).opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
