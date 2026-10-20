import SwiftUI

extension View {
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
    static func font(_ size: CGFloat = 16, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(fontName, size: size, relativeTo: style)
    }
}

struct PixelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 8)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(enabled ? 1 : 0.3), lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
    }
}

/// Original 12 × 12 monochrome notebook mark; the visual size does not set the hit target.
struct PixelNotebook: View {
    private let rows = [
        "001111111100", "011000000110", "011010100110", "011000000110",
        "011011110110", "011000000110", "011011110110", "011000000110",
        "011010000110", "011000000110", "001111111100", "000000000000"
    ]
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 12
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() where character == "1" {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)), with: .foreground)
                }
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }
}

struct PixelEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 20) {
            PixelNotebook()
            Text(title).font(PixelTheme.font(24, relativeTo: .title2))
            Text(message).foregroundStyle(.secondary)
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
