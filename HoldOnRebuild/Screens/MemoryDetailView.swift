import SwiftUI
import AVFAudio
import AVFoundation
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers

struct MemoryDetailView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let momentID: UUID

    @State private var title = ""
    @State private var player: HoldOnBoostedAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTime: Double = 0
    @State private var playbackTask: Task<Void, Never>?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showEditor = false
    @State private var showBackgroundPicker = false
    @State private var showRatioPicker = false
    @State private var showExportChoices = false
    @State private var showDeleteConfirm = false
    @State private var showAudioExporter = false
    @State private var exportAudioURL: URL?
    @State private var exportMessage: String?
    @State private var isExportingVideo = false
    @State private var detailWaveform: [Float] = []
    @State private var premiumContext: HoldOnPremiumContext?
    @State private var freeTrialPromptContext: HoldOnPremiumContext?
    @ObservedObject private var purchaseManager = HoldOnPurchaseManager.shared

    private var moment: SavedMoment? { engine.savedMoments.first { $0.id == momentID } }

    var body: some View {
        NavigationStack {
            ZStack {
                HoldOnTheme.ambientBackground.ignoresSafeArea()
                if let moment {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            card(moment)
                            actionStrip(moment)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    })
                }
            }
            .navigationTitle("기억")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
            .onAppear {
                if let m = moment {
                    title = presentedTitle(m)
                    loadDetailWaveform(m.audioURL)
                }
            }
            .onDisappear { stopPlayback() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    player?.stop()
                    player = nil
                    isPlaying = false
                    playbackTime = 0
                    playbackTask?.cancel()
                    playbackTask = nil
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        engine.setMomentCardPhoto(id: momentID, jpegData: data)
                    }
                    selectedPhoto = nil
                }
            }
            .sheet(isPresented: $showEditor) { AudioSubtitleEditorView(momentID: momentID) }
            .sheet(item: $premiumContext) { context in
                HoldOnPremiumAccessView(context: context) {
                    DispatchQueue.main.async {
                        runPremiumAction(context)
                    }
                }
            }
            .sheet(isPresented: $showBackgroundPicker) {
                BackgroundPickerSheet(momentID: momentID, selectedPhoto: $selectedPhoto)
                    .environmentObject(engine)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRatioPicker) {
                RatioPickerSheet(current: moment?.cardRatio ?? "4:1") { ratio in
                    engine.updateMomentCardAppearance(id: momentID, ratio: ratio)
                    showRatioPicker = false
                }
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog("내보내기", isPresented: $showExportChoices, titleVisibility: .visible) {
                Button("영상 → 사진 앱") { requestPremium(.videoExport) }
                Button("오디오 → 파일") {
                    exportAudioURL = moment?.audioURL
                    showAudioExporter = exportAudioURL != nil
                }
                Button("취소", role: .cancel) {}
            }
            .fileExporter(
                isPresented: $showAudioExporter,
                document: exportAudioURL.map { AudioFileDocument(url: $0, filename: exportFilename + ".m4a") },
                contentType: .mpeg4Audio,
                defaultFilename: exportFilename
            ) { _ in }
            .alert("이 기억을 삭제할까요?", isPresented: $showDeleteConfirm) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    if let moment { engine.moveToTrash(moment) }
                    dismiss()
                }
            } message: { Text("삭제된 항목에서 다시 복원할 수 있어요.") }
            .alert("내보내기", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                Button("확인") { exportMessage = nil }
            } message: { Text(exportMessage ?? "") }
            .alert(
                "광고 없이 무료 체험",
                isPresented: Binding(
                    get: { freeTrialPromptContext != nil },
                    set: { if !$0 { freeTrialPromptContext = nil } }
                )
            ) {
                Button("취소", role: .cancel) {
                    freeTrialPromptContext = nil
                }
                Button("무료로 사용") {
                    guard let context = freeTrialPromptContext else { return }
                    _ = purchaseManager.consumeFreeTrialUseIfAvailable()
                    freeTrialPromptContext = nil
                    runPremiumAction(context)
                }
            } message: {
                if purchaseManager.freeTrialRemainingUses == 1 {
                    Text("이번이 마지막 무료 체험이에요.\n이번 사용 후부터는 광고 또는 Full Access로 이용할 수 있어요.")
                } else {
                    Text("고급 기능을 광고 없이 사용할 수 있어요.\n무료 체험 \(purchaseManager.freeTrialRemainingUses)회 남았어요.")
                }
            }
            .overlay {
                if isExportingVideo {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.large)
                            Text("영상으로 만드는 중…")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private func card(_ moment: SavedMoment) -> some View {
        let size = previewSize(for: moment.cardRatio ?? "4:1")
        return ZStack {
            MomentBackgroundView(moment: moment)
                .frame(width: size.width, height: size.height)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                .frame(width: size.width, height: size.height)

            VStack(spacing: 5) {
                HoldOnTitleEditor(
                    text: $title,
                    fontName: moment.titleFont ?? "serif",
                    storedSize: moment.titleSize ?? 18,
                    displaySize: HoldOnSubtitleLayout.titleSize(
                        canvasWidth: size.width,
                        ratio: moment.cardRatio ?? "4:1",
                        storedSize: moment.titleSize ?? 18
                    ),
                    inkHex: moment.inkHex ?? "#FFFFFF",
                    onCommit: { newTitle in
                        engine.renameMoment(moment, title: newTitle)
                    },
                    onFontChange: { font in
                        engine.updateMomentCardAppearance(id: moment.id, titleFont: font)
                    },
                    onSizeChange: { value in
                        engine.updateMomentCardAppearance(id: moment.id, titleSize: value)
                    }
                )

                Text(metaLine(moment))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF").opacity(0.87))
                    .lineLimit(1)

                DetailAudioMark(samples: detailWaveform, duration: moment.durationSeconds, position: playbackTime)
                    .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF").opacity(0.84))
            }
            .padding(.horizontal, 22)
            .frame(width: size.width, height: size.height)
            .zIndex(10)

            let sourceSubtitleTime = moment.sourceTimelineTime(forPlaybackTime: playbackTime)
            ForEach((moment.subtitles ?? []).filter { sourceSubtitleTime >= $0.start && sourceSubtitleTime < $0.end }) { cue in
                HoldOnSubtitleLabel(cue: cue, canvasWidth: size.width, ratio: moment.cardRatio ?? "4:1")
                    .position(
                        x: size.width * min(max(cue.x, 0.06), 0.94),
                        y: size.height * min(max(cue.y, 0.08), 0.92)
                    )
                    .zIndex(15)
            }

            VStack {
                Spacer()
                playback(moment)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            .frame(width: size.width, height: size.height)
            .zIndex(20)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .frame(maxWidth: .infinity)
    }

    private func playback(_ moment: SavedMoment) -> some View {
        HStack(spacing: 9) {
            Button { togglePlayback(moment) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.20), in: Circle())
            }
            .buttonStyle(.plain)

            Button { seekToCapturePoint(moment) } label: {
                VStack(spacing: 1) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("잡은 순간")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(.black.opacity(0.20), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("잡은 순간으로 이동")

            ZStack {
                CompactPlaybackSlider(value: Binding(
                    get: { min(playbackTime, max(moment.durationSeconds, 0.01)) },
                    set: { value in playbackTime = value; try? player?.seek(to: value) }
                ), maximum: max(moment.durationSeconds, 0.01), ink: .white)

                GeometryReader { geo in
                    let fraction = capturePointFraction(moment)
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .position(x: max(5, min(geo.size.width - 5, geo.size.width * fraction)), y: 3)
                        .allowsHitTesting(false)
                        .accessibilityLabel("잡은 순간")
                }
            }
            .frame(height: 28)

            Text(format(max(0, moment.durationSeconds - playbackTime)))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 42, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private func actionStrip(_ moment: SavedMoment) -> some View {
        HStack(spacing: 10) {
            action("rectangle.ratio.3.to.4", "화면비율") { showRatioPicker = true }
            action("photo", "배경") { showBackgroundPicker = true }
            action("waveform.badge.magnifyingglass", "오디오+자막") {
                stopPlayback()
                requestPremium(.editor)
            }
            action("square.and.arrow.up", "내보내기") { showExportChoices = true }
            action("trash", "삭제", destructive: true) { showDeleteConfirm = true }
        }
        .padding(.horizontal, 14)
    }

    private func action(_ symbol: String, _ text: String, destructive: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(symbol, text, destructive: destructive) }.buttonStyle(.plain)
    }

    private func actionLabel(_ symbol: String, _ text: String, destructive: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(destructive ? Color.red : HoldOnTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
    }

    private func requestPremium(_ context: HoldOnPremiumContext) {
        if purchaseManager.hasFullAccess {
            runPremiumAction(context)
            return
        }

        if purchaseManager.freeTrialRemainingUses > 0 {
            freeTrialPromptContext = context
            return
        }

        premiumContext = context
    }

    private func runPremiumAction(_ context: HoldOnPremiumContext) {
        premiumContext = nil
        switch context {
        case .editor:
            stopPlayback()
            showEditor = true
        case .videoExport:
            exportVideoToPhotos()
        case .manage:
            break
        }
    }

    private func togglePlayback(_ moment: SavedMoment) {
        if isPlaying { stopPlayback(); return }
        engine.prepareForMemoryPlayback()
        do {
            guard FileManager.default.fileExists(atPath: moment.audioURL.path) else { return }
            if player == nil {
                let boosted = HoldOnBoostedAudioPlayer()
                try boosted.load(url: moment.audioURL)
                player = boosted
            }
            player?.gainFactor = moment.playbackGain ?? 1.0
            if playbackTime >= max(0, moment.durationSeconds - 0.05) { playbackTime = 0 }
            try player?.play(from: playbackTime)
            isPlaying = true
            playbackTask?.cancel()
            playbackTask = Task { @MainActor in
                while !Task.isCancelled, let p = player, p.isPlaying {
                    playbackTime = p.currentTime
                    if playbackTime >= max(0, moment.durationSeconds - 0.03) { break }
                    try? await Task.sleep(for: .milliseconds(80))
                }
                isPlaying = false
            }
        } catch { isPlaying = false }
    }

    private func stopPlayback() {
        player?.pause(); isPlaying = false; playbackTask?.cancel(); playbackTask = nil
    }

    private func seekToCapturePoint(_ moment: SavedMoment) {
        let sourcePoint = Double(moment.preSeconds)
        let target = max(0, moment.playbackTimelineTime(forSourceTime: sourcePoint) - 1.5)
        playbackTime = min(target, moment.durationSeconds)
        try? player?.seek(to: playbackTime)
    }

    private func capturePointFraction(_ moment: SavedMoment) -> Double {
        let sourcePoint = Double(moment.preSeconds)
        let playbackPoint = moment.playbackTimelineTime(forSourceTime: sourcePoint)
        return moment.durationSeconds > 0 ? min(1, max(0, playbackPoint / moment.durationSeconds)) : 0
    }

    private func previewSize(for ratio: String) -> CGSize {
        let maxW = max(280, UIScreen.main.bounds.width - 28)
        let aspect: CGFloat
        switch ratio {
        case "3:2": aspect = 1.5
        case "1:1": aspect = 1
        case "9:16": aspect = 9.0 / 16.0
        default: aspect = 4
        }
        var w = maxW
        var h = w / aspect
        if h > 470 { h = 470; w = h * aspect }
        return CGSize(width: w, height: h)
    }

    private func presentedTitle(_ m: SavedMoment) -> String {
        let raw = m.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacy = DateFormatter(); legacy.locale = Locale(identifier: "ko_KR"); legacy.dateFormat = "M월 d일 HH:mm"
        if raw.isEmpty || raw == legacy.string(from: m.createdAt) {
            let time = DateFormatter(); time.locale = Locale(identifier: "ko_KR"); time.dateFormat = "HH:mm"
            return time.string(from: m.createdAt)
        }
        return raw
    }

    private func metaLine(_ m: SavedMoment) -> String {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy.MM.dd"
        let t = DateFormatter(); t.locale = Locale(identifier: "en_US_POSIX"); t.dateFormat = "HH:mm"
        return "\(d.string(from: m.createdAt))  ·  \(t.string(from: m.createdAt))  ·  HOLD ON"
    }

    private func loadDetailWaveform(_ url: URL) {
        Task.detached(priority: .utility) {
            let result = Self.readDetailWaveform(url: url, points: 360)
            await MainActor.run { detailWaveform = result }
        }
    }

    nonisolated private static func readDetailWaveform(url: URL, points: Int) -> [Float] {
        guard points > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let totalFrames = max(Int64(1), file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return [] }
        var peaks = [Float](repeating: 0, count: points)
        var absoluteFrame: Int64 = 0
        while absoluteFrame < totalFrames {
            buffer.frameLength = 0
            do { try file.read(into: buffer) } catch { break }
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<count {
                let globalFrame = absoluteFrame + Int64(frame)
                let bin = min(points - 1, Int(globalFrame * Int64(points) / totalFrames))
                var value: Float = 0
                for channel in 0..<Int(format.channelCount) {
                    value = max(value, abs(channels[channel][frame]))
                }
                peaks[bin] = max(peaks[bin], value)
            }
            absoluteFrame += Int64(count)
        }
        return peaks.map { min(1, max(0.03, $0 * 2.2)) }
    }

    private var exportFilename: String {
        guard let moment else { return "HOLD_ON" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: moment.createdAt)
    }

    private func exportVideoToPhotos() {
        guard let moment else { return }
        isExportingVideo = true
        Task {
            do {
                let image = renderExportImage(moment)
                let url = try await StaticCardVideoExporter.makeVideo(
                    image: image,
                    audioURL: moment.audioURL,
                    duration: moment.durationSeconds,
                    subtitles: moment.exportSubtitles,
                    cardRatio: moment.cardRatio ?? "4:1",
                    titleSize: moment.titleSize ?? 18
                )
                try await StaticCardVideoExporter.saveToPhotos(url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    engine.markMomentExportedToPhotos(id: moment.id)
                    isExportingVideo = false
                    exportMessage = "사진 앱의 HOLD ON 앨범에 영상을 저장했어요."
                }
            } catch {
                await MainActor.run { isExportingVideo = false; exportMessage = "영상 저장에 실패했어요.\n\(error.localizedDescription)" }
            }
        }
    }

    @MainActor
    private func renderExportImage(_ moment: SavedMoment) -> UIImage {
        let size = StaticCardVideoExporter.outputSize(for: moment.cardRatio ?? "4:1")
        let view = ExportCardView(moment: moment)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}


private struct DetailAudioMark: View {
    let samples: [Float]
    let duration: Double
    let position: Double

    private func level(_ offset: Int) -> CGFloat {
        guard !samples.isEmpty, duration > 0 else { return 0.22 }
        let shifted = min(max(position + Double(offset) * 0.045, 0), duration)
        let ratio = shifted / duration
        let index = min(max(0, Int(ratio * Double(samples.count - 1))), samples.count - 1)
        return CGFloat(min(max(samples[index], 0.08), 1))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<10, id: \.self) { index in
                let boosted = CGFloat(pow(Double(level(index - 5)), 0.55))
                Capsule()
                    .fill(.primary)
                    .frame(width: 2.5, height: 2 + 12 * boosted)
                    .animation(.linear(duration: 0.10), value: boosted)
            }
        }
        .frame(width: 39, height: 16)
        .accessibilityLabel("오디오가 있는 기억")
    }
}


private struct BackgroundPickerSheet: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let momentID: UUID
    @Binding var selectedPhoto: PhotosPickerItem?
    @State private var tab = "하늘"
    @State private var gradientA = "#758DD8"
    @State private var gradientB = "#C8A8E2"

    private let palette = [
        "#FFFFFF", "#F1D6DB", "#E8CCD9", "#DDB8A6",
        "#F0D88A", "#BFD59B", "#9DC8BF", "#A7CDE8",
        "#7B80D9", "#A987B8", "#8A8D99", "#222222"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("배경 종류", selection: $tab) {
                    Text("하늘").tag("하늘")
                    Text("내 사진").tag("내 사진")
                    Text("단색").tag("단색")
                    Text("그라데이션").tag("그라데이션")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if tab == "하늘" {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            ForEach(1...23, id: \.self) { i in
                                let file = skyFile(i)
                                Button {
                                    engine.updateMomentCardAppearance(id: momentID, backgroundKind: "sky", backgroundValue: file)
                                    dismiss()
                                } label: {
                                    SkyThumb(file: file)
                                        .frame(height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                } else if tab == "내 사진" {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("사진 앱에서 선택", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HoldOnTheme.purple)
                    .padding(20)
                    Spacer()
                } else if tab == "단색" {
                    colorPalette { hex in
                        engine.updateMomentCardAppearance(id: momentID, backgroundKind: "solid", backgroundValue: hex)
                        dismiss()
                    }
                    Spacer()
                } else {
                    VStack(spacing: 14) {
                        LinearGradient(
                            colors: [Color(hex: gradientA), Color(hex: gradientB)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack(alignment: .top, spacing: 12) {
                            miniPalette(selected: $gradientA)
                            miniPalette(selected: $gradientB)
                        }

                        Button("이 그라데이션 사용") {
                            engine.updateMomentCardAppearance(
                                id: momentID,
                                backgroundKind: "gradient",
                                backgroundValue: "\(gradientA)|\(gradientB)"
                            )
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HoldOnTheme.purple)
                    }
                    .padding(16)
                    Spacer()
                }
            }
            .navigationTitle("배경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } } }
        }
    }

    private func colorPalette(onSelect: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 6), spacing: 10) {
            ForEach(palette, id: \.self) { hex in
                Button { onSelect(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
    }

    private func miniPalette(selected: Binding<String>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 4), spacing: 6) {
            ForEach(palette, id: \.self) { hex in
                Button { selected.wrappedValue = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 23, height: 23)
                        .overlay(
                            Circle().stroke(
                                selected.wrappedValue == hex ? HoldOnTheme.purple : Color.black.opacity(0.10),
                                lineWidth: selected.wrappedValue == hex ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func skyFile(_ i: Int) -> String {
        String(format: "sky_%02d.%@", i, [7,9,16,20,22,23].contains(i) ? "png" : "jpg")
    }
}

private struct SkyThumb: View {
    let file: String
    var body: some View {
        if let image = load() { Image(uiImage: image).resizable().scaledToFill() }
        else { Color.gray.opacity(0.15) }
    }
    private func load() -> UIImage? {
        let ns = file as NSString
        guard let url = Bundle.main.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension, subdirectory: "SkyAssets") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct RatioPickerSheet: View {
    let current: String
    let onSelect: (String) -> Void
    private let ratios = ["4:1", "3:2", "1:1", "9:16"]

    var body: some View {
        VStack(spacing: 16) {
            Text("화면 비율").font(.system(size: 18, weight: .bold)).padding(.top, 24)
            HStack(spacing: 10) {
                ForEach(ratios, id: \.self) { ratio in
                    Button { onSelect(ratio) } label: {
                        Text(ratio)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(current == ratio ? .white : HoldOnTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(current == ratio ? HoldOnTheme.purple : Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .background(HoldOnTheme.background)
    }
}

private struct AudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Audio] }
    let url: URL
    let filename: String

    init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        self.url = FileManager.default.temporaryDirectory.appendingPathComponent("unused.m4a")
        self.filename = "HOLD_ON.m4a"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: url)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = filename
        return wrapper
    }
}

private struct ExportCardView: View {
    @ObservedObject private var fonts = HoldOnFontManager.shared
    let moment: SavedMoment
    var body: some View {
        GeometryReader { geo in
            ZStack {
                MomentBackgroundView(moment: moment)
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: max(5, geo.size.height * 0.012)) {
                    Text(moment.title.isEmpty ? "HOLD ON" : moment.title)
                        .font((moment.titleFont ?? "serif") == "serif"
                              ? fonts.swiftUIFont(size: HoldOnSubtitleLayout.titleSize(canvasWidth: geo.size.width, ratio: moment.cardRatio ?? "4:1", storedSize: moment.titleSize ?? 18), bold: true)
                              : .system(size: HoldOnSubtitleLayout.titleSize(canvasWidth: geo.size.width, ratio: moment.cardRatio ?? "4:1", storedSize: moment.titleSize ?? 18), weight: .semibold))
                        .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, geo.size.width * 0.06)
                    Text(exportMeta(moment.createdAt))
                        .font(.system(size: HoldOnSubtitleLayout.exportMetaSize(canvasWidth: geo.size.width, ratio: moment.cardRatio ?? "4:1"), weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF").opacity(0.88))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .clipped()
        }
    }

    private func exportTitleSize(width: CGFloat, ratio: String) -> CGFloat {
        let base = CGFloat(moment.titleSize ?? 18)
        let reference: CGFloat
        switch ratio {
        case "9:16": reference = 180
        case "1:1": reference = 250
        case "3:2": reference = 320
        default: reference = 350
        }
        return max(18, base * width / reference)
    }

    private func exportMeta(_ date: Date) -> String {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy.MM.dd"
        let t = DateFormatter(); t.locale = Locale(identifier: "en_US_POSIX"); t.dateFormat = "HH:mm"
        return "\(d.string(from: date))  ·  \(t.string(from: date))  ·  HOLD ON"
    }
}

private enum StaticCardVideoExporter {
    static func outputSize(for ratio: String) -> CGSize {
        switch ratio {
        case "3:2": return CGSize(width: 1440, height: 960)
        case "1:1": return CGSize(width: 1080, height: 1080)
        case "9:16": return CGSize(width: 1080, height: 1920)
        default: return CGSize(width: 1920, height: 480)
        }
    }

    static func makeVideo(image: UIImage, audioURL: URL, duration: Double, subtitles: [HoldOnSubtitleCue], cardRatio: String, titleSize: Double) async throws -> URL {
        let fm = FileManager.default
        let silentURL = fm.temporaryDirectory.appendingPathComponent("holdon_still_\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: silentURL) }
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let finalURL = fm.temporaryDirectory.appendingPathComponent("\(stampFormatter.string(from: Date()))_\(UUID().uuidString).mp4")
        var exportSucceeded = false
        defer { if !exportSucceeded { try? fm.removeItem(at: finalURL) } }
        try? fm.removeItem(at: silentURL); try? fm.removeItem(at: finalURL)

        let size = CGSize(width: max(2, floor(image.size.width / 2) * 2), height: max(2, floor(image.size.height / 2) * 2))
        let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_800_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        guard writer.canAdd(input) else { throw NSError(domain: "HoldOnExport", code: 1) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "HoldOnExport", code: 7) }
        writer.startSession(atSourceTime: .zero)

        let buffer = try pixelBuffer(from: image, size: size, pool: adaptor.pixelBufferPool)
        // The card is static. Two samples are enough to span the entire duration; writing one
        // duplicate frame every second only increased export time and disk writes.
        let stillTimes = [0.0, max(duration, 1.0)]
        for time in stillTimes {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? NSError(domain: "HoldOnExport", code: 8) }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)) else {
                writer.cancelWriting()
                throw writer.error ?? NSError(domain: "HoldOnExport", code: 9)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "HoldOnExport", code: 2) }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silentURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "HoldOnExport", code: 3)
        }
        let wanted = CMTime(seconds: max(duration, 0.1), preferredTimescale: 600)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: wanted), of: sourceVideo, at: .zero)

        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            let use = CMTimeMinimum(audioDuration, wanted)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: use), of: sourceAudio, at: .zero)
        }

        // Static photo/title/meta are pre-rendered once at export resolution. Only the waveform
        // and timed subtitles are composited per frame. Preserve text edges during the final pass.
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "HoldOnExport", code: 4)
        }
        exporter.outputURL = finalURL
        exporter.outputFileType = .mp4

        // The card itself is static. Only the tiny audio mark and timed subtitles change.
        // 4 fps is enough for that subtle motion and halves the composition work again versus
        // the previous 8 fps path, which measured about one minute for a six-minute memory.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 4)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: wanted)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        // HOLD ON audio mark: keep it close to the title/meta rather than in a remote corner.
        // The motion follows a lightweight envelope sampled from the real recording, so even
        // a muted social feed reads this as an audio memory rather than a still image.
        let rawEnvelope = audioEnvelope(url: audioURL, duration: max(duration, 0.1), points: max(24, min(240, Int(duration * 6))))
        let envelope = smoothedEnvelope(rawEnvelope)
        let indicator = CALayer()
        let indicatorWidth = HoldOnSubtitleLayout.exportAudioMarkWidth(canvasWidth: size.width, ratio: cardRatio)
        let indicatorHeight = HoldOnSubtitleLayout.exportAudioMarkHeight(canvasWidth: size.width, ratio: cardRatio)
        // Title + meta + audio mark are one centered visual group at every card ratio.
        // Core Animation uses bottom-up coordinates, so place the mark just below the
        // title/meta block instead of using a ratio-sensitive absolute Y percentage.
        let ratioName = cardRatio
        let exportTitleSize = HoldOnSubtitleLayout.titleSize(canvasWidth: size.width, ratio: ratioName, storedSize: titleSize)
        let exportMetaSize = HoldOnSubtitleLayout.exportMetaSize(canvasWidth: size.width, ratio: ratioName)
        let textBlockHeight = exportTitleSize * 1.20 + exportMetaSize * 1.25 + max(5, size.height * 0.012)
        let markGap = max(5, size.height * 0.012)
        let markCenterY = size.height / 2 - textBlockHeight / 2 - markGap - indicatorHeight / 2
        indicator.frame = CGRect(
            x: (size.width - indicatorWidth) / 2,
            y: max(2, markCenterY - indicatorHeight / 2),
            width: indicatorWidth,
            height: indicatorHeight
        )
        let barCount = 10
        let gap = indicatorWidth * 0.035
        let barWidth = (indicatorWidth - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let samples = envelope.isEmpty ? Array(repeating: Float(0.22), count: max(24, Int(duration * 6))) : envelope
        let keyTimes: [NSNumber] = samples.indices.map { index in
            NSNumber(value: samples.count <= 1 ? 0 : Double(index) / Double(samples.count - 1))
        }
        for index in 0..<barCount {
            let bar = CALayer()
            let scales: [NSNumber] = samples.enumerated().map { sampleIndex, sample in
                let neighbor = samples[(sampleIndex + index * 2) % samples.count]
                // Lift quiet speech while preserving peaks; the static card still compresses efficiently.
                let audible = pow(Double(max(sample, neighbor)), 0.55)
                let level = 0.12 + min(0.88, audible * 0.88)
                return NSNumber(value: max(0.12, level))
            }
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: indicatorHeight)
            bar.position = CGPoint(x: barWidth / 2 + CGFloat(index) * (barWidth + gap), y: indicatorHeight / 2)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.82).cgColor
            bar.setAffineTransform(CGAffineTransform(scaleX: 1, y: CGFloat(truncating: scales.first ?? NSNumber(value: 0.22))))

            let pulse = CAKeyframeAnimation(keyPath: "transform.scale.y")
            pulse.values = scales
            pulse.keyTimes = keyTimes
            pulse.calculationMode = .linear
            pulse.duration = max(duration, 0.1)
            pulse.beginTime = AVCoreAnimationBeginTimeAtZero
            pulse.isRemovedOnCompletion = false
            pulse.fillMode = .both
            bar.add(pulse, forKey: "holdon.audioEnvelopeScale.\(index)")
            indicator.addSublayer(bar)
        }
        parent.addSublayer(indicator)

        // Burn subtitle cues into the exported movie.
        for cue in subtitles where cue.end > cue.start {
            let subtitleRatioName = HoldOnSubtitleLayout.ratioName(for: size)
            let captionImage = try await renderCaption(cue, width: size.width, ratio: subtitleRatioName)
            let boxW = captionImage.size.width
            let boxH = captionImage.size.height
            let x = size.width * CGFloat(min(max(cue.x, 0.06), 0.94)) - boxW / 2
            // Core Animation video coordinates are bottom-up.
            let y = size.height * (1 - CGFloat(min(max(cue.y, 0.08), 0.92))) - boxH / 2
            let container = CALayer()
            container.frame = CGRect(x: x, y: y, width: boxW, height: boxH)
            container.contents = captionImage.cgImage
            container.contentsGravity = .resize
            container.opacity = 0
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 1; show.toValue = 1
            show.beginTime = AVCoreAnimationBeginTimeAtZero + cue.start
            show.duration = max(0.05, cue.end - cue.start)
            show.isRemovedOnCompletion = false
            container.add(show, forKey: "holdon.subtitle.\(cue.id)")
            parent.addSublayer(container)
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        exporter.videoComposition = videoComposition

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        try? fm.removeItem(at: silentURL)
        guard exporter.status == .completed else { throw exporter.error ?? NSError(domain: "HoldOnExport", code: 5) }
        exportSucceeded = true
        return finalURL
    }

    @MainActor
    private static func renderCaption(_ cue: HoldOnSubtitleCue, width: CGFloat, ratio: String) throws -> UIImage {
        let view = HoldOnSubtitleLabel(cue: cue, canvasWidth: width, ratio: ratio)
            .environment(\.displayScale, 1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width * 0.88, height: nil)
        guard let image = renderer.uiImage else { throw NSError(domain: "HoldOnExport", code: 6) }
        return image
    }

    private static func audioEnvelope(url: URL, duration: Double, points: Int) -> [Float] {
        guard points > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let totalFrames = max(Int64(1), file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return [] }
        var sums = [Float](repeating: 0, count: points)
        var counts = [Int](repeating: 0, count: points)
        var absoluteFrame: Int64 = 0
        while absoluteFrame < totalFrames {
            buffer.frameLength = 0
            do { try file.read(into: buffer) } catch { break }
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<count {
                let globalFrame = absoluteFrame + Int64(frame)
                let bin = min(points - 1, Int(globalFrame * Int64(points) / totalFrames))
                var value: Float = 0
                for channel in 0..<Int(format.channelCount) {
                    value = max(value, abs(channels[channel][frame]))
                }
                sums[bin] += value
                counts[bin] += 1
            }
            absoluteFrame += Int64(count)
        }
        let raw: [Float] = (0..<points).map { index in
            counts[index] > 0 ? sums[index] / Float(counts[index]) : 0
        }
        // Normalize to this recording instead of a fixed loudness threshold. Quiet family speech
        // should visibly move too, while a single clap must not flatten the rest of the waveform.
        let sorted = raw.sorted()
        let p90 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.90))]
        let reference = max(p90, 0.008)
        return raw.map { min(1, max(0.06, $0 / reference)) }
    }

    private static func smoothedEnvelope(_ values: [Float]) -> [Float] {
        guard values.count > 2 else { return values }
        return values.indices.map { index in
            let a = values[max(0, index - 1)]
            let b = values[index]
            let c = values[min(values.count - 1, index + 1)]
            return min(1, max(0.04, (a + b * 2 + c) / 4))
        }
    }

    static func saveToPhotos(_ url: URL) async throws {
        try await HoldOnPhotoLibrary.saveVideoToHoldOnAlbum(url)
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary, &buffer)
        }
        guard let buffer else { throw NSError(domain: "HoldOnExport", code: 7) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue), let cg = image.cgImage else {
            throw NSError(domain: "HoldOnExport", code: 8)
        }
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
