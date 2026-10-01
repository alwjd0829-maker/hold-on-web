import SwiftUI
import AVFAudio
import UIKit

struct AudioSubtitleEditorView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let momentID: UUID

    @State private var player: HoldOnBoostedAudioPlayer?
    @State private var isPlaying = false
    @State private var position: Double = 0
    @State private var timer: Timer?
    @State private var deletedRanges: [[Double]] = []
    @State private var splitPoints: [Double] = []
    @State private var subtitles: [HoldOnSubtitleCue] = []
    @State private var selectedSubtitleID: UUID?
    @State private var history: [EditSnapshot] = []
    @State private var future: [EditSnapshot] = []
    @State private var waveform: [Float] = []
    @State private var pixelsPerSecond: CGFloat = 44
    @State private var dragStartPosition: Double?
    @State private var zoomStart: CGFloat?
    @State private var draggingSplitIndex: Int?
    @State private var draggingSplitStart: Double?
    @State private var subtitleText = ""
    @State private var editingSubtitleID: UUID?
    @FocusState private var subtitleTextFocused: Bool
    @State private var toast: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var draggingSubtitleID: UUID?
    @State private var draggingSubtitleMode: SubtitleTimelineDragMode?
    @State private var draggingSubtitleStart: HoldOnSubtitleCue?
    @State private var draggingSubtitleDraft: HoldOnSubtitleCue?
    @State private var subtitlePinchStartScale: Double?
    @State private var editorMode: EditorMode = .audio
    @State private var showSubtitleStyleSheet = false
    @State private var editorTitle = ""

    private var moment: SavedMoment? { engine.savedMoments.first { $0.id == momentID } }
    private var duration: Double { max(0.01, moment?.audioEdit?.sourceDuration ?? moment?.durationSeconds ?? 0.01) }
    private var capturePointSeconds: Double {
        min(duration, max(0, Double(moment?.preSeconds ?? 0)))
    }

    private var selectedCue: HoldOnSubtitleCue? {
        guard let id = selectedSubtitleID else { return subtitles.first }
        return subtitles.first(where: { $0.id == id }) ?? subtitles.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HoldOnTheme.ambientBackground
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissAllKeyboards() }
                GeometryReader { proxy in
                    VStack(spacing: 4) {
                        videoPreview
                            .frame(height: previewHeight(for: proxy.size.height))

                        transport
                            .simultaneousGesture(TapGesture().onEnded { dismissSubtitleKeyboardIfNeeded() })
                        unifiedTimelineSection
                            .simultaneousGesture(TapGesture().onEnded { dismissSubtitleKeyboardIfNeeded() })
                        editorModePicker
                            .simultaneousGesture(TapGesture().onEnded { dismissSubtitleKeyboardIfNeeded() })

                        Group {
                            if editorMode == .audio {
                                audioEditSection
                            } else {
                                subtitleSection
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded { dismissSubtitleKeyboardIfNeeded() }
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.height > 35 { dismissAllKeyboards() }
                }
            )
            .navigationTitle("오디오 + 자막")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if editingSubtitleID != nil {
                        Spacer()
                        Button("완료") { endSubtitleTextEditing() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear(perform: load)
            .onDisappear {
                player?.stop()
                timer?.invalidate()
                saveTask?.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    player?.pause()
                    isPlaying = false
                    timer?.invalidate()
                    timer = nil
                }
            }
            .alert("HOLD ON", isPresented: Binding(
                get: { toast != nil },
                set: { if !$0 { toast = nil } }
            )) {
                Button("확인") { toast = nil }
            } message: {
                Text(toast ?? "")
            }
            .sheet(isPresented: $showSubtitleStyleSheet) {
                if let cue = selectedCue {
                    subtitleStyleSheet(cue)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .background(
                KeyboardOutsideTapDismissMonitor(
                    isEnabled: true,
                    onDismiss: { dismissAllKeyboards() }
                )
                .frame(width: 0, height: 0)
            )
        }
    }

    private var videoPreview: some View {
        GeometryReader { outer in
            if let moment {
                let ratioName = moment.cardRatio ?? "4:1"
                let ratio = previewAspectRatio(ratioName)
                let targetWidth = min(outer.size.width, outer.size.height * ratio)
                let targetHeight = max(1, targetWidth / ratio)

                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissSubtitleKeyboardIfNeeded() }
                    ZStack {
                        MomentBackgroundView(moment: moment)
                            .frame(width: targetWidth, height: targetHeight)
                            .clipped()

                        LinearGradient(
                            colors: [.black.opacity(0.03), .black.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(spacing: 4) {
                            HoldOnTitleEditor(
                                text: $editorTitle,
                                fontName: moment.titleFont ?? "serif",
                                storedSize: moment.titleSize ?? 18,
                                displaySize: HoldOnSubtitleLayout.titleSize(
                                    canvasWidth: targetWidth,
                                    ratio: ratioName,
                                    storedSize: moment.titleSize ?? 18
                                ),
                                inkHex: moment.inkHex ?? "#FFFFFF",
                                onCommit: { newTitle in
                                    let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !clean.isEmpty else { return }
                                    engine.renameMoment(moment, title: clean)
                                    editorTitle = clean
                                },
                                onFontChange: { font in
                                    engine.updateMomentCardAppearance(id: momentID, titleFont: font)
                                },
                                onSizeChange: { value in
                                    engine.updateMomentCardAppearance(id: momentID, titleSize: value)
                                }
                            )
                            .frame(maxWidth: targetWidth * 0.88)

                            Text(meta(moment.createdAt))
                                .font(.system(size: HoldOnSubtitleLayout.metaSize(canvasWidth: targetWidth), weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF").opacity(0.84))
                            PreviewAudioMark(samples: waveform, duration: duration, position: position)
                                .frame(width: HoldOnSubtitleLayout.audioMarkWidth(canvasWidth: targetWidth), height: HoldOnSubtitleLayout.audioMarkHeight(canvasWidth: targetWidth))
                                .foregroundStyle(Color(hex: moment.inkHex ?? "#FFFFFF").opacity(0.84))
                        }
                        .frame(width: targetWidth, height: targetHeight)

                        if editingSubtitleID != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { endSubtitleTextEditing() }
                                .zIndex(18)
                        }

                        ForEach(activeSubtitles) { cue in
                            Group {
                                if editingSubtitleID == cue.id {
                                    TextField("자막", text: subtitleLiveTextBinding(cue.id), axis: .vertical)
                                        .textFieldStyle(.plain)
                                        .focused($subtitleTextFocused)
                                } else {
                                    Text(cue.text)
                                }
                            }
                            .modifier(HoldOnSubtitleStyle(cue: cue, canvasWidth: targetWidth, ratio: ratioName))
                            .overlay {
                                if selectedSubtitleID == cue.id {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.88), lineWidth: 1)
                                }
                            }
                            .position(
                                x: targetWidth * min(max(cue.x, 0.06), 0.94),
                                y: targetHeight * min(max(cue.y, 0.08), 0.92)
                            )
                            .zIndex(editingSubtitleID == cue.id ? 30 : 20)
                            .onTapGesture(count: 2) { beginSubtitleTextEditing(cue) }
                            .onTapGesture(count: 1) { selectSubtitle(cue, revealOnTimeline: false) }
                            .gesture(
                                DragGesture(coordinateSpace: .named("videoPreview"))
                                    .onChanged { value in
                                        guard editingSubtitleID == nil else { return }
                                        selectedSubtitleID = cue.id
                                        moveSubtitle(id: cue.id,
                                            toX: value.location.x / max(targetWidth, 1),
                                            y: value.location.y / max(targetHeight, 1),
                                            commit: false
                                        )
                                    }
                                    .onEnded { value in
                                        guard editingSubtitleID == nil else { return }
                                        moveSubtitle(id: cue.id,
                                            toX: value.location.x / max(targetWidth, 1),
                                            y: value.location.y / max(targetHeight, 1),
                                            commit: true
                                        )
                                    }
                            )
                        }
                    }
                    .frame(width: targetWidth, height: targetHeight)
                    .coordinateSpace(name: "videoPreview")
                    // Pinch anywhere inside the actual preview to resize the selected subtitle.
                    // This avoids requiring two fingers to land on a very small Text hit target.
                    .simultaneousGesture(
                        MagnificationGesture(minimumScaleDelta: 0.005)
                            .onChanged { value in
                                guard let id = selectedSubtitleID else { return }
                                scaleSubtitle(id: id, magnification: value, commit: false)
                            }
                            .onEnded { value in
                                guard let id = selectedSubtitleID else { return }
                                scaleSubtitle(id: id, magnification: value, commit: true)
                            }
                    )
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text("미리보기 · \(ratioName)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(6)
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissSubtitleKeyboardIfNeeded() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func previewHeight(for availableHeight: CGFloat) -> CGFloat {
        guard let ratio = moment?.cardRatio else { return min(300, availableHeight * 0.46) }
        // Use the previously unused lower space for the actual result preview.
        // Keep enough room for the compact transport/timeline/subtitle toolbar below.
        switch ratio {
        case "9:16": return min(430, max(350, availableHeight * 0.54))
        case "1:1": return min(340, max(280, availableHeight * 0.43))
        case "3:2": return min(230, max(190, availableHeight * 0.29))
        default: return min(145, max(110, availableHeight * 0.18))
        }
    }

    private func previewAspectRatio(_ ratio: String) -> CGFloat {
        switch ratio {
        case "3:2": return 1.5
        case "1:1": return 1
        case "9:16": return 9.0 / 16.0
        default: return 4
        }
    }

    private func previewTitleSize(_ moment: SavedMoment, width: CGFloat, ratio: String) -> CGFloat {
        let base = CGFloat(moment.titleSize ?? 18)
        let reference: CGFloat
        switch ratio {
        case "9:16": reference = 180
        case "1:1": reference = 250
        case "3:2": reference = 320
        default: reference = 350
        }
        return max(10, base * width / reference)
    }

    private var effectiveSubtitles: [HoldOnSubtitleCue] {
        guard let draft = draggingSubtitleDraft, let id = draggingSubtitleID else { return subtitles }
        return subtitles.map { $0.id == id ? draft : $0 }
    }

    private var activeSubtitles: [HoldOnSubtitleCue] {
        effectiveSubtitles.filter { position >= $0.start && position < $0.end }
    }

    private func displayTitle(_ moment: SavedMoment) -> String {
        let raw = moment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: moment.createdAt)
    }

    private func meta(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd  ·  HH:mm  ·  'HOLD ON'"
        return f.string(from: date)
    }

    private var transport: some View {
        HStack(spacing: 10) {
            roundControl(isPlaying ? "pause.fill" : "play.fill", enabled: true) { togglePlay() }
            roundControl("arrow.uturn.backward", enabled: !history.isEmpty) { undo() }
            roundControl("arrow.uturn.forward", enabled: !future.isEmpty) { redo() }
            roundControl("arrow.counterclockwise", enabled: true) { reset() }

            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(time(position))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("/ \(time(duration))")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.muted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var editorModePicker: some View {
        HStack(spacing: 6) {
            Button {
                if editingSubtitleID != nil { endSubtitleTextEditing() }
                editorMode = .audio
            } label: {
                Label("오디오", systemImage: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(editorMode == .audio ? HoldOnTheme.purple.opacity(0.16) : Color.white.opacity(0.62), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(HoldOnTheme.ink)

            Button {
                editorMode = .subtitles
            } label: {
                Label("자막", systemImage: "captions.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(editorMode == .subtitles ? HoldOnTheme.purple.opacity(0.16) : Color.white.opacity(0.62), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(HoldOnTheme.ink)
        }
    }

    private var unifiedTimelineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("타임라인")
                    .font(.system(size: 13, weight: .bold))
                Text("밀기=탐색 · 두 손가락=확대")
                    .font(.system(size: 9))
                    .foregroundStyle(HoldOnTheme.muted)
                Spacer()
                Button {
                    seek(capturePointSeconds)
                } label: {
                    Label("잡은 순간", systemImage: "bookmark.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .foregroundStyle(HoldOnTheme.ink)
                .controlSize(.mini)
            }

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.76))

                    TimelineCanvas(
                        samples: waveform,
                        duration: duration,
                        position: position,
                        pixelsPerSecond: pixelsPerSecond,
                        deletedRanges: deletedRanges,
                        splitPoints: splitPoints,
                        capturePoint: capturePointSeconds
                    )
                    .frame(height: 38)
                    .position(x: geo.size.width / 2, y: 19)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ForEach(Array(splitPoints.enumerated()), id: \.offset) { index, split in
                        let splitX = geo.size.width / 2 + CGFloat(split * duration - position) * pixelsPerSecond
                        Capsule()
                            .fill(Color.white)
                            .overlay(Capsule().stroke(HoldOnTheme.purple, lineWidth: 1.3))
                            .frame(width: 9, height: 30)
                            .frame(width: 24, height: 44)
                            .contentShape(Rectangle())
                            .position(x: splitX, y: 20)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in moveSplit(index: index, translationX: value.translation.width) }
                                    .onEnded { _ in finishMovingSplit(index: index) }
                            )
                            .zIndex(30)
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: 42)

                    ForEach(subtitles.sorted { $0.start < $1.start }) { cue in
                        unifiedSubtitleClip(cue, size: geo.size)
                    }

                    Rectangle()
                        .fill(HoldOnTheme.purple)
                        .frame(width: 2)
                        .padding(.vertical, 5)
                        .allowsHitTesting(false)
                        .zIndex(40)

                    VStack {
                        Spacer()
                        Text(time(position))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(HoldOnTheme.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 3)
                    }
                    .allowsHitTesting(false)
                    .zIndex(41)
                }
                .clipped()
                .contentShape(Rectangle())
                .coordinateSpace(name: "unifiedTimeline")
                .gesture(timelinePanGesture)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if zoomStart == nil { zoomStart = pixelsPerSecond }
                            pixelsPerSecond = min(180, max(20, (zoomStart ?? 44) * value))
                        }
                        .onEnded { _ in zoomStart = nil }
                )
            }
            .frame(height: 68)
        }
        .padding(6)
        .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var timelinePanGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("unifiedTimeline"))
            .onChanged { value in
                if editingSubtitleID != nil { endSubtitleTextEditing() }
                if dragStartPosition == nil { dragStartPosition = position }
                let start = dragStartPosition ?? position
                seek(start - Double(value.translation.width / pixelsPerSecond))
            }
            .onEnded { value in
                let start = dragStartPosition ?? position
                let predicted = value.predictedEndTranslation.width
                let actual = value.translation.width
                let coast = (predicted - actual) * 0.30
                seek(start - Double((actual + coast) / pixelsPerSecond))
                dragStartPosition = nil
            }
    }

    @ViewBuilder
    private func unifiedSubtitleClip(_ cue: HoldOnSubtitleCue, size: CGSize) -> some View {
        let shownCue = (draggingSubtitleID == cue.id ? draggingSubtitleDraft : nil) ?? cue
        let startX = size.width / 2 + CGFloat(shownCue.start - position) * pixelsPerSecond
        let endX = size.width / 2 + CGFloat(shownCue.end - position) * pixelsPerSecond
        let width = max(40, endX - startX)
        let centerX = (startX + endX) / 2
        let laneY: CGFloat = shownCue.lane % 2 == 0 ? 46 : 59
        let selected = selectedSubtitleID == cue.id

        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? HoldOnTheme.purple.opacity(0.28) : HoldOnTheme.purple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.25), lineWidth: selected ? 1.4 : 0.7)
                )

            Text(shownCue.text)
                .font(.system(size: 8.5, weight: selected ? .bold : .semibold))
                .lineLimit(1)
                .padding(.horizontal, selected ? 26 : 9)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                Capsule()
                    .fill(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.55))
                    .frame(width: 4, height: 18)
                    .frame(width: 16, height: 25)
                    .contentShape(Rectangle())
                    .highPriorityGesture(subtitleTimelineGesture(id: cue.id, mode: .trimStart, coordinateSpace: "unifiedTimeline"))

                Color.clear

                Capsule()
                    .fill(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.55))
                    .frame(width: 4, height: 18)
                    .frame(width: 16, height: 25)
                    .contentShape(Rectangle())
                    .highPriorityGesture(subtitleTimelineGesture(id: cue.id, mode: .trimEnd, coordinateSpace: "unifiedTimeline"))
            }

            if selected {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(HoldOnTheme.purple, in: Capsule())
                    .contentShape(Capsule())
                    .highPriorityGesture(subtitleTimelineGesture(id: cue.id, mode: .move, coordinateSpace: "unifiedTimeline"))
            }
        }
        .frame(width: width, height: 25)
        .position(x: centerX, y: laneY)
        .zIndex(selected ? 25 : 12)
        .onTapGesture {
            selectSubtitle(cue, revealOnTimeline: true)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오디오 타임라인")
                        .font(.system(size: 14, weight: .bold))
                    Text("좌우 이동 · 두 손가락 확대")
                        .font(.system(size: 9))
                        .foregroundStyle(HoldOnTheme.muted)
                }
                Spacer()
                Button {
                    seek(capturePointSeconds)
                } label: {
                    Label("잡은 순간으로", systemImage: "bookmark.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .foregroundStyle(HoldOnTheme.ink)
                .controlSize(.mini)

                Text("\(Int(pixelsPerSecond))×")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.purple)
            }

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.78))

                    TimelineCanvas(
                        samples: waveform,
                        duration: duration,
                        position: position,
                        pixelsPerSecond: pixelsPerSecond,
                        deletedRanges: deletedRanges,
                        splitPoints: splitPoints,
                        capturePoint: capturePointSeconds
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    ForEach(Array(splitPoints.enumerated()), id: \.offset) { index, split in
                        let splitX = geo.size.width / 2 + CGFloat(split * duration - position) * pixelsPerSecond
                        ZStack {
                            Color.clear
                            Capsule()
                                .fill(Color.white)
                                .overlay(Capsule().stroke(HoldOnTheme.purple, lineWidth: 1.5))
                                .frame(width: 10, height: 38)
                        }
                        .frame(width: 28, height: 54)
                        .contentShape(Rectangle())
                        .position(x: splitX, y: geo.size.height / 2)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    moveSplit(index: index, translationX: value.translation.width)
                                }
                                .onEnded { _ in finishMovingSplit(index: index) }
                        )
                        .zIndex(12)
                    }

                    Rectangle()
                        .fill(HoldOnTheme.purple)
                        .frame(width: 2)
                        .padding(.vertical, 12)

                    VStack {
                        Spacer()
                        Text(time(position))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(HoldOnTheme.purple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartPosition == nil { dragStartPosition = position }
                            let start = dragStartPosition ?? position
                            seek(start - Double(value.translation.width / pixelsPerSecond))
                        }
                        .onEnded { value in
                            // Use a damped predicted end so long audio can be scanned with a natural flick,
                            // while the center playhead still remains the source of truth.
                            let start = dragStartPosition ?? position
                            let predicted = value.predictedEndTranslation.width
                            let actual = value.translation.width
                            let coast = (predicted - actual) * 0.35
                            seek(start - Double((actual + coast) / pixelsPerSecond))
                            dragStartPosition = nil
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if zoomStart == nil { zoomStart = pixelsPerSecond }
                            pixelsPerSecond = min(180, max(20, (zoomStart ?? 44) * value))
                        }
                        .onEnded { _ in zoomStart = nil }
                )
            }
            .frame(height: 92)
        }
        .padding(9)
        .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var audioEditSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("오디오 편집")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    resetToOriginalAudio()
                } label: {
                    Label("원본으로 복구", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HoldOnTheme.purple)
                .accessibilityLabel("오디오 편집을 원본으로 복구")
            }

            // Keep all four edit tools in one compact row so new features never
            // increase the editor's vertical footprint on smaller iPhones.
            HStack(spacing: 6) {
                editButton("나누기", "scissors") {
                    splitHere()
                }
                .accessibilityLabel("나누기")

                editButton(currentSegmentExcluded ? "복원" : "제외",
                           currentSegmentExcluded ? "arrow.uturn.backward.circle" : "minus.circle") {
                    toggleCurrentSegment()
                }
                .accessibilityLabel(currentSegmentExcluded ? "현재 구간 복원" : "현재 구간 제외")

                editButton("무음 제거", "speaker.slash") {
                    tidyQuietSections()
                }
                .accessibilityLabel("무음 제거")

                Menu {
                    ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { gain in
                        Button {
                            engine.setPlaybackGain(momentID: momentID, gain: gain)
                            player?.gainFactor = gain
                        } label: {
                            if abs((moment?.playbackGain ?? 1.0) - gain) < 0.01 {
                                Label("\(Int(gain))×", systemImage: "checkmark")
                            } else {
                                Text("\(Int(gain))×")
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "speaker.wave.3")
                            .font(.system(size: 14, weight: .semibold))
                        Text("음량 \(Int(moment?.playbackGain ?? 1.0))×")
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(HoldOnTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("재생 음량")
                .accessibilityValue("\(Int(moment?.playbackGain ?? 1.0))배")
            }

            let segment = currentSegment
            Text("현재 구간  \(time(segment.start)) — \(time(segment.end))")
                .font(.system(size: 11, weight: .semibold))

            if !splitPoints.isEmpty {
                Text("나눈 지점 \(splitPoints.count)개 · 회색 구간은 재생에서 건너뛰어요.")
                    .font(.system(size: 10))
                    .foregroundStyle(HoldOnTheme.muted)
            }
        }
        .padding(9)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("자막 편집")
                        .font(.system(size: 13, weight: .bold))
                    Text("이동 · 두 손가락 크기조절 · 더블탭 글자수정")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(HoldOnTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button { addSubtitleAtCurrentPosition() } label: {
                    Label("추가", systemImage: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(HoldOnTheme.purple.opacity(0.86))

                Button {
                    if let cue = selectedCue { duplicateSubtitle(cue.id) }
                } label: {
                    Label("복제", systemImage: "plus.square.on.square")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(HoldOnTheme.purple)
                .disabled(selectedCue == nil)
                .accessibilityLabel("선택한 자막과 스타일 복제")
            }

            if let cue = selectedCue {
                HStack(spacing: 4) {
                    subtitleCompactAction("나누기", symbol: "scissors") { splitSubtitle(cue.id) }
                    subtitleCompactAction("여기부터", symbol: "arrow.right.to.line") { setSubtitleStartHere(cue.id) }
                    subtitleCompactAction("여기까지", symbol: "arrow.left.to.line") { setSubtitleEndHere(cue.id) }
                    subtitleCompactAction("스타일", symbol: "slider.horizontal.3") { showSubtitleStyleSheet = true }
                    Button(role: .destructive) { deleteSubtitle(cue) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                Text("재생헤드를 원하는 곳에 두고 ‘추가’를 누르세요. 자막 블록을 누르면 바로 편집돼요.")
                    .font(.system(size: 10))
                    .foregroundStyle(HoldOnTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(7)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                if editingSubtitleID != nil { endSubtitleTextEditing() }
            }
        )
    }

    private func subtitleCompactAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(HoldOnTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .tint(HoldOnTheme.ink.opacity(0.18))
        .controlSize(.mini)
    }

    private func subtitleStyleSheet(_ cue: HoldOnSubtitleCue) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("자막 스타일").font(.headline); Spacer(); Button("완료") { showSubtitleStyleSheet = false } }
            Picker("글꼴", selection: subtitleFontBinding(cue.id)) { Text("고딕").tag("system"); Text("고운바탕").tag("serif") }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                Text("정렬")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HoldOnTheme.ink)
                HStack(spacing: 8) {
                    styleAlignmentButton("text.alignleft", "왼쪽", value: "left", cueID: cue.id)
                    styleAlignmentButton("text.aligncenter", "가운데", value: "center", cueID: cue.id)
                    styleAlignmentButton("text.alignright", "오른쪽", value: "right", cueID: cue.id)
                }
            }
            HStack { Text("크기"); Slider(value: subtitleScaleBinding(cue.id), in: 0.55...2.4, step: 0.05) }
            HStack(spacing: 18) {
                ColorPicker("글자색", selection: subtitleTextColorBinding(cue.id), supportsOpacity: false)
                ColorPicker("배경색", selection: subtitleBackgroundColorBinding(cue.id), supportsOpacity: false)
            }
            HStack { Text("배경 투명도"); Slider(value: subtitleBackgroundAlphaBinding(cue.id), in: 0...0.85, step: 0.05) }
        }
        .padding(18)
    }

    private var subtitleTimelineTrack: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.72))

                ForEach(subtitles.sorted { $0.start < $1.start }) { cue in
                    subtitleTimelineClip(cue, size: geo.size)
                }

                Rectangle()
                    .fill(HoldOnTheme.purple.opacity(0.88))
                    .frame(width: 2)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(name: "subtitleTimelineTrack")
        }
        .frame(height: 78)
    }

    @ViewBuilder
    private func subtitleTimelineClip(_ cue: HoldOnSubtitleCue, size: CGSize) -> some View {
        let shownCue = (draggingSubtitleID == cue.id ? draggingSubtitleDraft : nil) ?? cue
        let startX = size.width / 2 + CGFloat(shownCue.start - position) * pixelsPerSecond
        let endX = size.width / 2 + CGFloat(shownCue.end - position) * pixelsPerSecond
        let width = max(44, endX - startX)
        let centerX = (startX + endX) / 2
        let laneY: CGFloat = [15, 39, 63][max(0, shownCue.lane) % 3]
        let selected = selectedSubtitleID == cue.id

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? HoldOnTheme.purple.opacity(0.24) : HoldOnTheme.purple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.28), lineWidth: selected ? 1.5 : 0.7)
                )

            Text(shownCue.text)
                .font(.system(size: 9, weight: selected ? .bold : .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                Capsule()
                    .fill(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.55))
                    .frame(width: 5, height: 24)
                    .frame(width: 18, height: 32)
                    .contentShape(Rectangle())
                    .highPriorityGesture(subtitleTimelineGesture(id: cue.id, mode: .trimStart))

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(subtitleTimelineGesture(id: cue.id, mode: .move))

                Capsule()
                    .fill(selected ? HoldOnTheme.purple : HoldOnTheme.purple.opacity(0.55))
                    .frame(width: 5, height: 24)
                    .frame(width: 18, height: 32)
                    .contentShape(Rectangle())
                    .highPriorityGesture(subtitleTimelineGesture(id: cue.id, mode: .trimEnd))
            }
        }
        .frame(width: width, height: 32)
        .position(x: centerX, y: laneY)
        .zIndex(selected ? 20 : 10)
        .onTapGesture {
            selectSubtitle(cue, revealOnTimeline: true)
        }
    }

    private func subtitleTimelineGesture(id: UUID, mode: SubtitleTimelineDragMode, coordinateSpace: String = "subtitleTimelineTrack") -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                adjustSubtitleTimeline(id: id, mode: mode, translationX: value.translation.width)
            }
            .onEnded { _ in
                finishSubtitleTimelineDrag(id: id)
            }
    }

    private func selectSubtitle(_ cue: HoldOnSubtitleCue, revealOnTimeline: Bool) {
        if editingSubtitleID != nil && editingSubtitleID != cue.id { endSubtitleTextEditing() }
        selectedSubtitleID = cue.id
        editorMode = .subtitles
        if revealOnTimeline {
            seek(min(duration, max(0, (cue.start + cue.end) / 2)))
        }
    }

    private func beginSubtitleTextEditing(_ cue: HoldOnSubtitleCue) {
        selectedSubtitleID = cue.id
        editorMode = .subtitles
        editingSubtitleID = cue.id
        subtitleText = cue.text
        DispatchQueue.main.async {
            subtitleTextFocused = true
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
    }

    private func dismissSubtitleKeyboardIfNeeded() {
        guard editingSubtitleID != nil || subtitleTextFocused else { return }
        endSubtitleTextEditing()
    }

    private func dismissAllKeyboards() {
        if editingSubtitleID != nil || subtitleTextFocused { endSubtitleTextEditing() }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func endSubtitleTextEditing() {
        subtitleTextFocused = false
        if let id = editingSubtitleID, let index = subtitles.firstIndex(where: { $0.id == id }) {
            let clean = subtitles[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { subtitles[index].text = "새 자막" }
            engine.updateSubtitles(momentID: momentID, cues: subtitles)
        }
        editingSubtitleID = nil
        subtitleText = ""
    }

    private func subtitleLiveTextBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { currentCue(id)?.text ?? subtitleText },
            set: { value in
                subtitleText = value
                guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
                subtitles[index].text = value
                scheduleSubtitleSave()
            }
        )
    }

    private func setSubtitleAlignment(_ id: UUID, _ alignment: String) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        subtitles[index].alignment = alignment
        // In HOLD ON, alignment is spatial as well as typographic: make the action visible
        // even for a one-line subtitle, while keeping it safely inside the preview.
        switch alignment {
        case "left": subtitles[index].x = 0.22
        case "right": subtitles[index].x = 0.78
        default: subtitles[index].x = 0.50
        }
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func styleAlignmentButton(_ symbol: String, _ label: String, value: String, cueID: UUID) -> some View {
        let selected = (currentCue(cueID)?.alignment ?? "center") == value
        return Button {
            setSubtitleAlignment(cueID, value)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : HoldOnTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(selected ? HoldOnTheme.purple : HoldOnTheme.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }






    private func currentCue(_ id: UUID) -> HoldOnSubtitleCue? {
        subtitles.first(where: { $0.id == id })
    }

    private func addSubtitleAtCurrentPosition() {
        let start = min(duration, max(0, position))
        let end = min(duration, start + 10)
        guard end > start else { return }
        record()
        let overlapCount = subtitles.filter { start >= $0.start && start < $0.end }.count
        let lane = overlapCount % 2
        var cue = HoldOnSubtitleCue(start: start, end: end, text: "새 자막")
        cue.lane = lane
        cue.y = lane == 0 ? 0.66 : 0.78
        subtitles.append(cue)
        subtitles.sort { $0.start < $1.start }
        selectedSubtitleID = cue.id
        editorMode = .subtitles
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func subtitleTextColorBinding(_ id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: currentCue(id)?.textHex ?? "#FFFFFF") },
            set: { color in
                let hex = colorHex(color)
                updateSubtitleStyle(id) { $0.textHex = hex }
            }
        )
    }

    private func subtitleBackgroundColorBinding(_ id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: currentCue(id)?.backgroundHex ?? "#000000") },
            set: { color in
                let hex = colorHex(color)
                updateSubtitleStyle(id) { $0.backgroundHex = hex }
            }
        )
    }

    private func colorHex(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    private func subtitleFontBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { currentCue(id)?.font ?? "system" },
            set: { newValue in updateSubtitleStyle(id) { $0.font = newValue } }
        )
    }

    private func subtitleScaleBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { currentCue(id)?.scale ?? 1 },
            set: { newValue in updateSubtitleStyle(id) { $0.scale = newValue } }
        )
    }

    private func subtitleBackgroundAlphaBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { currentCue(id)?.backgroundAlpha ?? 0.35 },
            set: { newValue in updateSubtitleStyle(id) { $0.backgroundAlpha = newValue } }
        )
    }

    private func updateSubtitleStyle(_ id: UUID, change: (inout HoldOnSubtitleCue) -> Void) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        change(&subtitles[index])
        scheduleSubtitleSave()
    }

    private func subtitleColorDot(_ hex: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(selected ? HoldOnTheme.purple : Color.black.opacity(0.12), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func roundControl(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? HoldOnTheme.ink : HoldOnTheme.faint)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func editButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(HoldOnTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard let m = moment else { return }
        deletedRanges = m.audioEdit?.deletedRanges ?? []
        splitPoints = (m.audioEdit?.splitPoints ?? []).sorted()
        subtitles = m.subtitles ?? []
        editorTitle = displayTitle(m)
        selectedSubtitleID = subtitles.first?.id
        let sourceURL = engine.sourceAudioURL(for: momentID) ?? m.audioURL
        try? configurePlayer(sourceURL)
        loadWaveform(sourceURL)
    }

    private func configurePlayer(_ url: URL) throws {
        let boosted = HoldOnBoostedAudioPlayer()
        try boosted.load(url: url)
        boosted.gainFactor = moment?.playbackGain ?? 1.0
        player = boosted
    }

    private func loadWaveform(_ url: URL) {
        Task.detached(priority: .userInitiated) {
            let result = Self.readWaveform(url: url, points: 900)
            await MainActor.run { waveform = result }
        }
    }

    nonisolated private static func readWaveform(url: URL, points: Int) -> [Float] {
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

    private func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
            return
        }

        do {
            player.gainFactor = moment?.playbackGain ?? 1.0
            try player.play(from: min(player.duration, position))
        } catch {
            toast = "재생을 시작하지 못했어요.\n\(error.localizedDescription)"
            isPlaying = false
            return
        }
        isPlaying = true
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            Task { @MainActor in
                position = player.currentTime
                skipExcludedIfNeeded()
                if !player.isPlaying || position >= max(0, player.duration - 0.03) {
                    isPlaying = false
                    timer?.invalidate()
                }
            }
        }
    }

    private func seek(_ value: Double) {
        position = min(duration, max(0, value))
        try? player?.seek(to: min(player?.duration ?? duration, position))
    }

    private func skipExcludedIfNeeded() {
        let normalized = position / duration
        if let range = deletedRanges.first(where: {
            $0.count == 2 && normalized >= $0[0] && normalized < $0[1]
        }) {
            seek(range[1] * duration)
        }
    }

    private var normalizedPosition: Double {
        min(1, max(0, position / duration))
    }

    private var currentSegment: (start: Double, end: Double) {
        let points = [0.0] + splitPoints + [1.0]
        let n = normalizedPosition
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            if n >= a && (n < b || index == points.count - 2) {
                return (a * duration, b * duration)
            }
        }
        return (0, duration)
    }

    private var currentSegmentNormalized: (start: Double, end: Double) {
        let segment = currentSegment
        return (segment.start / duration, segment.end / duration)
    }

    private var currentSegmentExcluded: Bool {
        let segment = currentSegmentNormalized
        return deletedRanges.contains(where: { range in
            guard range.count >= 2 else { return false }
            let overlap = min(range[1], segment.end) - max(range[0], segment.start)
            return overlap > 0.0005
        })
    }

    private func moveSplit(index: Int, translationX: CGFloat) {
        guard splitPoints.indices.contains(index) else { return }
        if draggingSplitIndex != index {
            record()
            draggingSplitIndex = index
            draggingSplitStart = splitPoints[index]
        }
        let start = draggingSplitStart ?? splitPoints[index]
        let deltaSeconds = Double(translationX / pixelsPerSecond)
        let minGap = max(0.08 / duration, 0.001)
        let lower = index == 0 ? minGap : splitPoints[index - 1] + minGap
        let upper = index == splitPoints.count - 1 ? 1 - minGap : splitPoints[index + 1] - minGap
        let oldBoundary = splitPoints[index]
        let newBoundary = min(upper, max(lower, start + deltaSeconds / duration))

        // Exclusion belongs to the segment, not to a stale timestamp. If a shared
        // boundary moves, move the matching edge of every excluded segment with it.
        for rangeIndex in deletedRanges.indices where deletedRanges[rangeIndex].count >= 2 {
            if abs(deletedRanges[rangeIndex][0] - oldBoundary) < 0.0015 {
                deletedRanges[rangeIndex][0] = newBoundary
            }
            if abs(deletedRanges[rangeIndex][1] - oldBoundary) < 0.0015 {
                deletedRanges[rangeIndex][1] = newBoundary
            }
        }
        splitPoints[index] = newBoundary
    }

    private func finishMovingSplit(index: Int) {
        guard draggingSplitIndex == index else { return }
        draggingSplitIndex = nil
        draggingSplitStart = nil
        splitPoints.sort()
        engine.updateAudioSplitPoints(momentID: momentID, splitPoints: splitPoints)
        autosaveAudio()
    }

    private func splitHere() {
        let n = normalizedPosition
        guard n > 0.002, n < 0.998 else { return }
        guard !splitPoints.contains(where: { abs($0 - n) < 0.002 }) else { return }

        record()
        splitPoints.append(n)
        splitPoints.sort()
        engine.updateAudioSplitPoints(momentID: momentID, splitPoints: splitPoints)
    }

    private func toggleCurrentSegment() {
        let segment = currentSegmentNormalized
        guard segment.end - segment.start > 0.0005 else { return }
        record()

        if currentSegmentExcluded {
            // A quiet-cleanup pass can merge several adjacent excluded pieces into one
            // larger range. Restoring one selected segment must therefore subtract that
            // segment from the larger range instead of requiring exact boundary equality.
            var restored: [[Double]] = []
            let epsilon = 0.0005
            for range in deletedRanges where range.count >= 2 {
                let a = range[0]
                let b = range[1]
                let overlaps = min(b, segment.end) - max(a, segment.start) > epsilon
                if !overlaps {
                    restored.append([a, b])
                    continue
                }
                if a < segment.start - epsilon {
                    restored.append([a, min(b, segment.start)])
                }
                if b > segment.end + epsilon {
                    restored.append([max(a, segment.end), b])
                }
            }
            deletedRanges = restored
                .filter { $0.count >= 2 && $0[1] - $0[0] > epsilon }
                .sorted { $0[0] < $1[0] }
            toast = "선택한 구간을 다시 살렸어요."
        } else {
            deletedRanges.append([segment.start, segment.end])
            deletedRanges.sort { ($0.first ?? 0) < ($1.first ?? 0) }
        }
        autosaveAudio()
    }

    private func saveSubtitle() {
        let clean = subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        record()
        if let id = editingSubtitleID,
           let index = subtitles.firstIndex(where: { $0.id == id }) {
            subtitles[index].text = clean
            selectedSubtitleID = id
        } else {
            let start = min(duration, max(0, position))
            let end = min(duration, start + 10)
            guard end > start else { return }
            let overlapCount = subtitles.filter { start >= $0.start && start < $0.end }.count
            let lane = overlapCount % 3
            var cue = HoldOnSubtitleCue(start: start, end: end, text: clean)
            cue.lane = lane
            cue.y = [0.62, 0.76, 0.48][lane]
            subtitles.append(cue)
            selectedSubtitleID = cue.id
        }

        engine.updateSubtitles(momentID: momentID, cues: subtitles)
        editingSubtitleID = nil
        subtitleText = ""
    }

    private func duplicateSubtitle(_ id: UUID) {
        guard let source = subtitles.first(where: { $0.id == id }) else { return }
        record()
        let originalLength = max(0.2, source.end - source.start)
        var copy = source
        copy.id = UUID()
        let proposedStart = min(max(0, position), max(0, duration - 0.05))
        copy.start = proposedStart
        copy.end = min(duration, proposedStart + originalLength)
        if copy.end <= copy.start + 0.05 {
            copy.start = max(0, duration - min(originalLength, duration))
            copy.end = duration
        }
        subtitles.append(copy)
        subtitles.sort { $0.start < $1.start }
        selectedSubtitleID = copy.id
        editorMode = .subtitles
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func deleteSubtitle(_ cue: HoldOnSubtitleCue) {
        record()
        subtitles.removeAll { $0.id == cue.id }
        if selectedSubtitleID == cue.id { selectedSubtitleID = nil }
        if editingSubtitleID == cue.id { editingSubtitleID = nil; subtitleTextFocused = false }
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func moveSubtitle(id: UUID, toX x: Double, y: Double, commit: Bool) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        subtitles[index].x = min(0.94, max(0.06, x))
        subtitles[index].y = min(0.92, max(0.08, y))
        selectedSubtitleID = id
        if commit { engine.updateSubtitles(momentID: momentID, cues: subtitles) }
    }

    private func scaleSubtitle(id: UUID, magnification: CGFloat, commit: Bool) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        if subtitlePinchStartScale == nil {
            record()
            subtitlePinchStartScale = subtitles[index].scale
        }
        let base = subtitlePinchStartScale ?? subtitles[index].scale
        subtitles[index].scale = min(2.4, max(0.55, base * Double(magnification)))
        selectedSubtitleID = id
        if commit {
            subtitlePinchStartScale = nil
            engine.updateSubtitles(momentID: momentID, cues: subtitles)
        }
    }

    private func splitSubtitle(_ id: UUID) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        let cue = subtitles[index]
        let cut = min(cue.end, max(cue.start, position))
        guard cut > cue.start + 0.05, cut < cue.end - 0.05 else {
            toast = "재생헤드를 자막 안쪽에 놓고 나누기를 눌러주세요."
            return
        }
        record()
        subtitles[index].end = cut
        var right = cue
        right.id = UUID()
        right.start = cut
        subtitles.append(right)
        subtitles.sort { $0.start < $1.start }
        selectedSubtitleID = right.id
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func setSubtitleStartHere(_ id: UUID) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        let end = subtitles[index].end
        guard position < end - 0.05 else { toast = "재생헤드를 자막 끝보다 앞에 놓아주세요."; return }
        record()
        subtitles[index].start = max(0, position)
        selectedSubtitleID = id
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func setSubtitleEndHere(_ id: UUID) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        let start = subtitles[index].start
        guard position > start + 0.05 else { toast = "재생헤드를 자막 시작보다 뒤에 놓아주세요."; return }
        record()
        subtitles[index].end = min(duration, position)
        selectedSubtitleID = id
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func adjustSubtitleTimeline(id: UUID, mode: SubtitleTimelineDragMode, translationX: CGFloat) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
        if draggingSubtitleID != id || draggingSubtitleMode != mode {
            record()
            draggingSubtitleID = id
            draggingSubtitleMode = mode
            draggingSubtitleStart = subtitles[index]
            draggingSubtitleDraft = subtitles[index]
            selectedSubtitleID = id
        }
        guard let original = draggingSubtitleStart else { return }
        var draft = original
        let delta = Double(translationX / pixelsPerSecond)
        let minimumLength = min(0.25, max(0.05, duration * 0.002))

        switch mode {
        case .move:
            let length = max(minimumLength, original.end - original.start)
            let newStart = min(max(0, original.start + delta), max(0, duration - length))
            draft.start = newStart
            draft.end = min(duration, newStart + length)
        case .trimStart:
            draft.start = min(max(0, original.start + delta), original.end - minimumLength)
        case .trimEnd:
            draft.end = max(min(duration, original.end + delta), original.start + minimumLength)
        }
        // During a drag keep the persisted cue array frozen. Only this draft changes.
        // That prevents SwiftUI from relocating the gesture's own source view every frame,
        // which was the cause of the visible shiver/flicker. The preview still reads the draft
        // immediately, so the result remains WYSIWYG.
        draggingSubtitleDraft = draft
    }

    private func finishSubtitleTimelineDrag(id: UUID) {
        guard draggingSubtitleID == id else { return }
        if let draft = draggingSubtitleDraft, let index = subtitles.firstIndex(where: { $0.id == id }) {
            subtitles[index] = draft
        }
        draggingSubtitleID = nil
        draggingSubtitleMode = nil
        draggingSubtitleStart = nil
        draggingSubtitleDraft = nil
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
    }

    private func scheduleSubtitleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            engine.updateSubtitles(momentID: momentID, cues: subtitles)
        }
    }

    private func autosaveAudio() {
        let ranges = deletedRanges
        let points = splitPoints
        Task { @MainActor in
            do {
                try await engine.applyAudioEdit(
                    momentID: momentID,
                    trimStart: 0,
                    trimEnd: 1,
                    deletedRanges: ranges,
                    splitPoints: points
                )
                if let m = moment {
                    let sourceURL = engine.sourceAudioURL(for: momentID) ?? m.audioURL
                    try? configurePlayer(sourceURL)
                    loadWaveform(sourceURL)
                }
            } catch {
                toast = "자동 저장에 실패했어요.\n\(error.localizedDescription)"
            }
        }
    }

    private func tidyQuietSections() {
        guard waveform.count >= 8, duration > 0.5 else {
            toast = "파형을 불러온 뒤 다시 시도해 주세요."
            return
        }

        // Deliberately conservative: only long, near-silent stretches are suggested.
        // Speech pauses stay intact unless they remain close to the measured noise floor
        // for at least ~1.2 seconds. The result is still a normal excluded range, so
        // Undo/Redo and 편집 초기화 work exactly like a manual exclusion.
        let binSeconds = duration / Double(waveform.count)
        let threshold: Float = 0.052
        let minimumQuietSeconds = 1.2
        let speechSafetyPadding = 0.16

        var found: [[Double]] = []
        var startIndex: Int?

        func appendRange(start: Int, endExclusive: Int) {
            let rawStart = Double(start) * binSeconds + speechSafetyPadding
            let rawEnd = Double(endExclusive) * binSeconds - speechSafetyPadding
            guard rawEnd - rawStart >= minimumQuietSeconds else { return }
            let a = min(1, max(0, rawStart / duration))
            let b = min(1, max(a, rawEnd / duration))
            guard b - a > 0.0005 else { return }
            found.append([a, b])
        }

        for index in waveform.indices {
            if waveform[index] <= threshold {
                if startIndex == nil { startIndex = index }
            } else if let start = startIndex {
                appendRange(start: start, endExclusive: index)
                startIndex = nil
            }
        }
        if let start = startIndex { appendRange(start: start, endExclusive: waveform.count) }

        guard !found.isEmpty else {
            toast = "제거할 만큼 긴 무음 구간이 없어요."
            return
        }

        record()
        var all = deletedRanges + found
        all.sort { ($0.first ?? 0) < ($1.first ?? 0) }
        var merged: [[Double]] = []
        for range in all where range.count >= 2 {
            if let last = merged.last, last.count >= 2, range[0] <= last[1] + 0.0008 {
                merged[merged.count - 1][1] = max(last[1], range[1])
            } else {
                merged.append([range[0], range[1]])
            }
        }
        deletedRanges = merged

        let newBoundaries = found.flatMap { [$0[0], $0[1]] }
            .filter { $0 > 0.002 && $0 < 0.998 }
        splitPoints = Array(Set(splitPoints + newBoundaries)).sorted()
        engine.updateAudioSplitPoints(momentID: momentID, splitPoints: splitPoints)
        autosaveAudio()
        toast = "조용한 구간 \(found.count)곳을 표시했어요. 회색 구간을 확인한 뒤 Undo로 되돌릴 수 있어요."
    }

    private func reset() {
        resetToOriginalAudio()
    }

    private func resetToOriginalAudio() {
        record()
        player?.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        splitPoints = []
        deletedRanges = []
        position = 0
        do {
            try engine.resetAudioEdit(momentID: momentID)
            engine.setPlaybackGain(momentID: momentID, gain: 1.0)
            engine.updateAudioSplitPoints(momentID: momentID, splitPoints: [])
            if let m = moment {
                let sourceURL = engine.sourceAudioURL(for: momentID) ?? m.audioURL
                try? configurePlayer(sourceURL)
                player?.gainFactor = 1.0
                loadWaveform(sourceURL)
            }
            toast = "오디오 편집을 원본으로 복구했어요."
        } catch {
            toast = "원본 복구에 실패했어요.\n\(error.localizedDescription)"
        }
    }

    private func record() {
        history.append(EditSnapshot(
            deletedRanges: deletedRanges,
            splitPoints: splitPoints,
            subtitles: subtitles
        ))
        if history.count > 50 { history.removeFirst() }
        future.removeAll()
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        future.append(EditSnapshot(
            deletedRanges: deletedRanges,
            splitPoints: splitPoints,
            subtitles: subtitles
        ))
        restore(last)
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append(EditSnapshot(
            deletedRanges: deletedRanges,
            splitPoints: splitPoints,
            subtitles: subtitles
        ))
        restore(next)
    }

    private func restore(_ snapshot: EditSnapshot) {
        deletedRanges = snapshot.deletedRanges
        splitPoints = snapshot.splitPoints
        subtitles = snapshot.subtitles
        engine.updateSubtitles(momentID: momentID, cues: subtitles)
        engine.updateAudioSplitPoints(momentID: momentID, splitPoints: splitPoints)
        autosaveAudio()
    }

    private func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct TimelineCanvas: View {
    let samples: [Float]
    let duration: Double
    let position: Double
    let pixelsPerSecond: CGFloat
    let deletedRanges: [[Double]]
    let splitPoints: [Double]
    let capturePoint: Double

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            let midY = size.height * 0.42
            let waveHeight = size.height * 0.52
            let step: CGFloat = 3

            var x: CGFloat = 0
            while x < size.width {
                let time = position + Double((x - center) / pixelsPerSecond)
                if time >= 0 && time <= duration {
                    let normalized = duration > 0 ? time / duration : 0
                    let maxIndex = max(samples.count - 1, 0)
                    let index = min(max(0, Int(normalized * Double(maxIndex))), maxIndex)
                    let amp = samples.isEmpty
                        ? Float(0.16 + 0.08 * sin(time * 2.4))
                        : samples[index]
                    let height = max(2, CGFloat(amp) * waveHeight)
                    let path = Path(CGRect(x: x, y: midY - height / 2, width: 1.5, height: height))
                    let excluded = deletedRanges.contains {
                        $0.count == 2 && normalized >= $0[0] && normalized <= $0[1]
                    }
                    context.fill(
                        path,
                        with: .color(excluded ? Color.gray.opacity(0.25) : HoldOnTheme.purple.opacity(0.72))
                    )
                }
                x += step
            }

            let captureX = center + CGFloat(capturePoint - position) * pixelsPerSecond
            if captureX >= 0 && captureX <= size.width {
                let marker = Path(CGRect(x: captureX - 1, y: 5, width: 2, height: size.height - 10))
                context.fill(marker, with: .color(HoldOnTheme.purple.opacity(0.95)))
                let dot = Path(ellipseIn: CGRect(x: captureX - 4, y: 5, width: 8, height: 8))
                context.fill(dot, with: .color(HoldOnTheme.purple))
            }

            for split in splitPoints {
                let splitX = center + CGFloat(split * duration - position) * pixelsPerSecond
                if splitX >= 0 && splitX <= size.width {
                    let path = Path(CGRect(x: splitX, y: 12, width: 1, height: size.height * 0.60))
                    context.fill(path, with: .color(Color.black.opacity(0.28)))
                }
            }
        }
    }
}


private struct KeyboardOutsideTapDismissMonitor: UIViewRepresentable {
    let isEnabled: Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attachIfNeeded(to: view.window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onDismiss = onDismiss
        DispatchQueue.main.async { context.coordinator.attachIfNeeded(to: uiView.window) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        var onDismiss: () -> Void
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func attachIfNeeded(to window: UIWindow?) {
            guard let window else { return }
            if self.window === window, recognizer != nil { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.window = window
            recognizer = tap
        }

        func detach() {
            if let recognizer { window?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            window = nil
        }

        @objc private func handleTap() {
            guard isEnabled else { return }
            onDismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

private struct PreviewAudioMark: View {
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
        .accessibilityLabel("오디오가 있는 영상")
    }
}

private enum EditorMode: Equatable {
    case audio
    case subtitles
}

private enum SubtitleTimelineDragMode: Equatable {
    case move
    case trimStart
    case trimEnd
}

private struct EditSnapshot {
    let deletedRanges: [[Double]]
    let splitPoints: [Double]
    let subtitles: [HoldOnSubtitleCue]
}
