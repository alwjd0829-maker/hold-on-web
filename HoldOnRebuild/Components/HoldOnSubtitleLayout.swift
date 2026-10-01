import CoreGraphics
import SwiftUI
import UIKit

enum HoldOnSubtitleLayout {
    static func referenceWidth(for ratio: String) -> CGFloat {
        switch ratio {
        case "9:16": return 180
        case "1:1": return 250
        case "3:2": return 320
        default: return 350
        }
    }

    static func ratioName(for size: CGSize) -> String {
        let r = size.width / max(size.height, 1)
        if r < 0.8 { return "9:16" }
        if r < 1.15 { return "1:1" }
        if r < 2.0 { return "3:2" }
        return "4:1"
    }

    static func fontSize(canvasWidth: CGFloat, ratio: String, scale: Double) -> CGFloat {
        max(8, canvasWidth * (16 / referenceWidth(for: ratio)) * CGFloat(scale))
    }

    static func titleSize(canvasWidth: CGFloat, ratio: String, storedSize: Double) -> CGFloat {
        max(10, CGFloat(storedSize) * canvasWidth / referenceWidth(for: ratio))
    }

    static func metaSize(canvasWidth: CGFloat) -> CGFloat {
        max(7, min(18, canvasWidth * 0.028))
    }

    static func audioMarkWidth(canvasWidth: CGFloat) -> CGFloat {
        max(22, min(58, canvasWidth * 0.11))
    }

    static func audioMarkHeight(canvasWidth: CGFloat) -> CGFloat {
        max(6, min(13, canvasWidth * 0.021))
    }

    // Build 145: export resolution is higher than the earlier 720/960px pipeline.
    // Scale the small meta line and audio mark from the old output dimensions so
    // their *visual size* stays exactly where users were used to seeing it.
    private static func legacyExportWidth(for ratio: String) -> CGFloat {
        switch ratio {
        case "9:16", "1:1": return 720
        default: return 960
        }
    }

    static func exportMetaSize(canvasWidth: CGFloat, ratio: String) -> CGFloat {
        let oldWidth = legacyExportWidth(for: ratio)
        return metaSize(canvasWidth: oldWidth) * (canvasWidth / oldWidth)
    }

    static func exportAudioMarkWidth(canvasWidth: CGFloat, ratio: String) -> CGFloat {
        let oldWidth = legacyExportWidth(for: ratio)
        return audioMarkWidth(canvasWidth: oldWidth) * (canvasWidth / oldWidth)
    }

    static func exportAudioMarkHeight(canvasWidth: CGFloat, ratio: String) -> CGFloat {
        let oldWidth = legacyExportWidth(for: ratio)
        return audioMarkHeight(canvasWidth: oldWidth) * (canvasWidth / oldWidth)
    }
}

struct HoldOnSubtitleStyle: ViewModifier {
    @ObservedObject private var fonts = HoldOnFontManager.shared
    let cue: HoldOnSubtitleCue
    let canvasWidth: CGFloat
    let ratio: String
    func body(content: Content) -> some View {
        let factor = canvasWidth / HoldOnSubtitleLayout.referenceWidth(for: ratio)
        content
            .font(cue.font == "serif"
                  ? fonts.swiftUIFont(size: HoldOnSubtitleLayout.fontSize(canvasWidth: canvasWidth, ratio: ratio, scale: cue.scale), bold: true)
                  : .system(size: HoldOnSubtitleLayout.fontSize(canvasWidth: canvasWidth, ratio: ratio, scale: cue.scale), weight: .semibold))
            .foregroundStyle(Color(hex: cue.textHex))
            .lineLimit(3)
            .multilineTextAlignment(cue.alignment == "left" ? .leading : (cue.alignment == "right" ? .trailing : .center))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10 * factor)
            .padding(.vertical, 6 * factor)
            .background(Color(hex: cue.backgroundHex).opacity(cue.backgroundAlpha), in: RoundedRectangle(cornerRadius: 8 * factor))
    }
}

struct HoldOnSubtitleLabel: View {
    let cue: HoldOnSubtitleCue
    let canvasWidth: CGFloat
    let ratio: String
    var body: some View {
        Text(cue.text).modifier(HoldOnSubtitleStyle(cue: cue, canvasWidth: canvasWidth, ratio: ratio))
    }
}

/// Shared title editor used by both the memory detail card and the audio/subtitle editor.
/// Keep title editing simple: the title line itself edits text, while one Aa button opens
/// font/size controls so the title never gets crowded with several tiny controls.
struct HoldOnTitleEditor: View {
    @ObservedObject private var fonts = HoldOnFontManager.shared
    @Binding var text: String
    let fontName: String
    let storedSize: Double
    let displaySize: CGFloat
    let inkHex: String
    let onCommit: (String) -> Void
    let onFontChange: (String) -> Void
    let onSizeChange: (Double) -> Void

    @FocusState private var focused: Bool
    @State private var showStyle = false

    var body: some View {
        // The editable title owns the full width. HOLD ON titles are always one line:
        // use the full title box first, then shrink the glyphs only when the text still
        // does not fit. The Aa control remains diagonally outside and steals no width.
        ZStack(alignment: .topTrailing) {
            TextField("제목", text: $text)
                .font(fontName == "serif"
                      ? fonts.swiftUIFont(size: displaySize, bold: true)
                      : .system(size: displaySize, weight: .semibold))
                .foregroundStyle(Color(hex: inkHex))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { commitAndDismiss() }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color(hex: inkHex).opacity(focused ? 0.95 : 0.54), lineWidth: focused ? 1.5 : 1)
                )

            Button {
                if focused { commitAndDismiss() }
                showStyle = true
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: inkHex))
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 9, y: -9)
            .accessibilityLabel("제목 글꼴과 크기")
        }
        .padding(.top, 4)
        .onChange(of: focused) { oldValue, newValue in
            if !oldValue && newValue {
                DispatchQueue.main.async {
                    UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                }
            }
            if oldValue && !newValue { commit() }
        }
        .sheet(isPresented: $showStyle) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("제목 스타일").font(.headline)
                    Spacer()
                    Button("완료") { showStyle = false }.fontWeight(.semibold)
                }

                Picker("글꼴", selection: Binding(
                    get: { fontName },
                    set: { onFontChange($0) }
                )) {
                    Text("고딕").tag("system")
                    Text("고운바탕").tag("serif")
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("제목 크기")
                        Spacer()
                        Text("\(Int(storedSize))")
                            .monospacedDigit()
                            .foregroundStyle(HoldOnTheme.muted)
                    }
                    Slider(value: Binding(
                        get: { storedSize },
                        set: { onSizeChange($0) }
                    ), in: 12...34, step: 1)
                }
            }
            .padding(22)
            .presentationDetents([.height(230)])
            .presentationDragIndicator(.visible)
        }
    }

    private func commit() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if clean != text { text = clean }
        onCommit(clean)
    }

    private func commitAndDismiss() {
        commit()
        focused = false
    }
}
