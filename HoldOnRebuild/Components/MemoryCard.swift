import SwiftUI
import AVFAudio
import UIKit

struct MemoryCard: View {
    @EnvironmentObject private var playbackCoordinator: MemoryPreviewPlaybackCoordinator
    @EnvironmentObject private var engine: AudioHoldEngine
    @ObservedObject private var fonts = HoldOnFontManager.shared
    let moment: SavedMoment
    var selected: Bool = false
    var selectionMode: Bool = false
    var showsPlayback: Bool = true
    var onOpen: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil
    var onRequestDelete: (() -> Void)? = nil

    @State private var playbackTime: Double = 0

    private var displayTitle: String {
        let t = moment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == legacyAutomaticTitle(moment.createdAt) { return timeTitle(moment.createdAt) }
        return t
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    MomentBackgroundView(moment: moment)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.34)], startPoint: .top, endPoint: .bottom)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // Card-open hit target deliberately excludes the playback strip.
                    // Previously the full-card title layer also owned an onTapGesture,
                    // so a play-button tap could race the card-open gesture.
                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectionMode { onToggleSelection?() } else { onOpen?() }
                            }
                        Color.clear
                            .frame(height: showsPlayback ? 55 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .zIndex(5)

                    VStack(spacing: 3) {
                        Text(displayTitle)
                            .font(cardTitleFont)
                            .foregroundStyle(cardInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(metaLine(moment))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(cardInk.opacity(0.86))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Keep the title/meta visually above the playback thumb so the card stays readable.
                    .offset(y: showsPlayback ? -12 : 0)
                    .padding(.horizontal, 22)
                    .allowsHitTesting(false)
                    .zIndex(6)

                    if showsPlayback {
                        VStack(spacing: 1) {
                            Spacer()
                            playbackBar.frame(height: 48)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .zIndex(20)
                        .allowsHitTesting(true)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
            }
            .aspectRatio(4, contentMode: .fit)
            .clipped()
            .overlay {
                Rectangle().stroke(selected ? HoldOnTheme.purple : Color.white.opacity(0.32), lineWidth: selected ? 2 : 0.5)
            }

            if selectionMode {
                Button { onToggleSelection?() } label: {
                    ZStack {
                        Circle().fill(selected ? HoldOnTheme.purple : Color.white.opacity(0.92)).frame(width: 25, height: 25)
                        Image(systemName: selected ? "checkmark" : "circle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? .white : HoldOnTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .onReceive(playbackCoordinator.$currentTime) { value in
            if playbackCoordinator.activeID == moment.id { playbackTime = value }
        }
        .onReceive(playbackCoordinator.$activeID) { id in
            if id != moment.id { playbackTime = 0 }
        }
        .onDisappear {
            playbackCoordinator.stopIfActive(moment.id)
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 7) {
            Button { togglePlayback() } label: {
                Image(systemName: cardIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(cardInk)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.16), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cardIsPlaying ? "일시정지" : "재생")

            Button { seekToCapturePoint() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bookmark.fill").font(.system(size: 8, weight: .bold))
                    Text("잡은 순간").font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(cardInk)
                .padding(.horizontal, 7)
                .frame(height: 30)
                .background(.black.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("잡은 순간으로 이동")

            CompactPlaybackSlider(value: Binding(
                get: { min(playbackTime, max(moment.durationSeconds, 0.01)) },
                set: { seek($0) }
            ), maximum: max(moment.durationSeconds, 0.01), ink: cardInk)
            .frame(height: 44)

            Text(time(displayedPlaybackTime))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(cardInk.opacity(0.9))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    private func seekToCapturePoint() {
        let sourcePoint = Double(moment.preSeconds)
        let target = max(0, moment.playbackTimelineTime(forSourceTime: sourcePoint) - 1.5)
        playbackTime = min(target, moment.durationSeconds)
        playbackCoordinator.seek(id: moment.id, to: playbackTime)
    }

    private var cardTitleFont: Font {
        let size = min(max(CGFloat(moment.titleSize ?? 18), 14), 23)
        return (moment.titleFont ?? "serif") == "serif"
            ? fonts.swiftUIFont(size: size, bold: true)
            : .system(size: size, weight: .semibold)
    }

    private var cardInk: Color { Color(hex: moment.inkHex ?? "#FFFFFF") }

    private func metaLine(_ m: SavedMoment) -> String {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy.MM.dd"
        let t = DateFormatter(); t.locale = Locale(identifier: "en_US_POSIX"); t.dateFormat = "HH:mm"
        return "\(d.string(from: m.createdAt))  ·  \(t.string(from: m.createdAt))  ·  HOLD ON"
    }

    private func timeTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func legacyAutomaticTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M월 d일 HH:mm"
        return f.string(from: date)
    }

    private var cardIsPlaying: Bool {
        playbackCoordinator.activeID == moment.id && playbackCoordinator.isPlaying
    }

    private var displayedPlaybackTime: Double {
        guard playbackCoordinator.activeID == moment.id else { return moment.durationSeconds }
        return max(0, moment.durationSeconds - playbackTime)
    }

    private func togglePlayback() {
        playbackCoordinator.toggle(moment: moment, from: playbackTime, engine: engine)
    }

    private func seek(_ value: Double) {
        playbackTime = value
        playbackCoordinator.seek(id: moment.id, to: value)
    }

    private func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// A 14pt visible thumb with the full-height slider touch surface preserved.
struct CompactPlaybackSlider: UIViewRepresentable {
    @Binding var value: Double
    let maximum: Double
    let ink: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.accessibilityLabel = "재생 위치"
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.maximumValue = Float(maximum)
        if !slider.isTracking { slider.value = Float(min(max(0, value), maximum)) }
        let color = UIColor(ink)
        slider.minimumTrackTintColor = color
        slider.maximumTrackTintColor = color.withAlphaComponent(0.32)
        if context.coordinator.color != color {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14))
            let thumb = renderer.image { _ in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 14, height: 14)).fill()
            }
            slider.setThumbImage(thumb, for: .normal)
            slider.setThumbImage(thumb, for: .highlighted)
            context.coordinator.color = color
        }
    }

    final class Coordinator: NSObject {
        var parent: CompactPlaybackSlider
        var color: UIColor?
        init(_ parent: CompactPlaybackSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) { parent.value = Double(slider.value) }
    }
}

struct MomentBackgroundView: View {
    let moment: SavedMoment

    var body: some View {
        GeometryReader { geo in
            background
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if moment.cardBackgroundKind == "album",
           FileManager.default.fileExists(atPath: moment.cardImageURL.path),
           let image = UIImage(contentsOfFile: moment.cardImageURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .id(moment.cardImageRevision ?? 0)
                .overlay(Color.black.opacity(0.12))
        } else if moment.cardBackgroundKind == "solid" {
            Color(hex: moment.cardBackgroundValue ?? "#7B80D9")
        } else if moment.cardBackgroundKind == "gradient" {
            let pair = gradientPair(moment.cardBackgroundValue)
            LinearGradient(
                colors: [Color(hex: pair.0), Color(hex: pair.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if let file = moment.cardBackgroundValue,
                  let image = bundledSky(named: file) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color(red: 0.45, green: 0.58, blue: 0.90), Color(red: 0.78, green: 0.68, blue: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func gradientPair(_ value: String?) -> (String, String) {
        if let value, value.contains("|") {
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        switch value {
        case "blue": return ("#7297B8", "#D6E5F1")
        case "rose": return ("#A987B8", "#E8CCD9")
        default: return ("#758DD8", "#C8A8E2")
        }
    }

    private func bundledSky(named file: String) -> UIImage? {
        let ns = file as NSString
        guard let url = Bundle.main.url(
            forResource: ns.deletingPathExtension,
            withExtension: ns.pathExtension,
            subdirectory: "SkyAssets"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6: (r,g,b) = (value >> 16, value >> 8 & 0xff, value & 0xff)
        default: (r,g,b) = (0x7B,0x80,0xD9)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}
