import SwiftUI
import AVFAudio


@MainActor
final class MemoryPreviewPlaybackCoordinator: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false

    private var player: HoldOnBoostedAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func toggle(moment: SavedMoment, from requestedTime: Double, engine: AudioHoldEngine) {
        if activeID == moment.id, isPlaying {
            pause()
            return
        }
        play(moment: moment, from: requestedTime, engine: engine)
    }

    func play(moment: SavedMoment, from requestedTime: Double, engine: AudioHoldEngine) {
        stop(resetTime: false)
        guard FileManager.default.fileExists(atPath: moment.audioURL.path) else {
            activeID = nil
            isPlaying = false
            return
        }

        engine.prepareForMemoryPlayback()
        do {
            let newPlayer = HoldOnBoostedAudioPlayer()
            try newPlayer.load(url: moment.audioURL)
            newPlayer.gainFactor = moment.playbackGain ?? 1.0
            let duration = max(0, newPlayer.duration)
            let start = requestedTime >= max(0, duration - 0.05) ? 0 : min(max(0, requestedTime), duration)
            try newPlayer.play(from: start)
            player = newPlayer
            activeID = moment.id
            currentTime = start
            isPlaying = true
            startProgressLoop(for: moment.id)
        } catch {
            player = nil
            activeID = nil
            isPlaying = false
        }
    }

    func pause() {
        guard let player else { return }
        player.pause()
        currentTime = player.currentTime
        isPlaying = false
        progressTask?.cancel()
        progressTask = nil
    }

    func seek(id: UUID, to value: Double) {
        guard activeID == id else { return }
        let clamped = min(max(0, value), player?.duration ?? value)
        try? player?.seek(to: clamped)
        currentTime = clamped
    }

    func stopIfActive(_ id: UUID) {
        guard activeID == id else { return }
        stop(resetTime: true)
    }

    func stop(resetTime: Bool = true) {
        progressTask?.cancel()
        progressTask = nil
        player?.stop(resetTime: resetTime)
        player = nil
        isPlaying = false
        activeID = nil
        if resetTime { currentTime = 0 }
    }

    private func startProgressLoop(for id: UUID) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self, self.activeID == id, let player = self.player else { return }
                self.currentTime = player.currentTime
                if self.currentTime >= max(0, player.duration - 0.03) || !player.isPlaying {
                    self.isPlaying = false
                    self.activeID = nil
                    self.player = nil
                    return
                }
            }
        }
    }
}

struct MemoriesView: View {
    @StateObject private var playbackCoordinator = MemoryPreviewPlaybackCoordinator()
    @EnvironmentObject private var engine: AudioHoldEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var oldestFirst = false
    @State private var selectionMode = false
    @State private var selected = Set<UUID>()
    @State private var showTrash = false
    @State private var openID: UUID?
    @State private var pendingDelete: SavedMoment?
    @State private var showFolderPicker = false
    @State private var activeFolder: String? = nil

    private var filteredMoments: [SavedMoment] {
        guard let activeFolder else { return engine.savedMoments }
        return engine.savedMoments.filter { $0.folderName == activeFolder }
    }
    private var moments: [SavedMoment] { oldestFirst ? Array(filteredMoments.reversed()) : filteredMoments }

    var body: some View {
        NavigationStack {
            ZStack {
                HoldOnTheme.ambientBackground
                VStack(spacing: 0) {
                    header
                    if selectionMode { selectionActionBar }
                    if moments.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "waveform").font(.system(size: 32)).foregroundStyle(HoldOnTheme.faint)
                            Text("아직 저장한 기억이 없어요").font(.system(size: 15, weight: .semibold))
                            Text("홈에서 순간잡기를 눌러 첫 기억을 남겨보세요.")
                                .font(.system(size: 11)).foregroundStyle(HoldOnTheme.muted)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(moments) { moment in
                                MemoryCard(
                                    moment: moment,
                                    selected: selected.contains(moment.id),
                                    selectionMode: selectionMode,
                                    showsPlayback: !selectionMode,
                                    onOpen: {
                                        playbackCoordinator.stop(resetTime: true)
                                        openID = moment.id
                                    },
                                    onToggleSelection: { toggle(moment.id) },
                                    onRequestDelete: { pendingDelete = moment }
                                )
                                .environmentObject(playbackCoordinator)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !selectionMode {
                                        Button(role: .destructive) {
                                            pendingDelete = moment
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            Color.clear
                                .frame(height: 110)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showTrash) { DeletedItemsView().environmentObject(playbackCoordinator) }
            .sheet(isPresented: $showFolderPicker) {
                MemoryFolderPickerSheet(
                    existingFolders: engine.memoryFolderNames,
                    onChoose: { folder in
                        engine.assignFolder(momentIDs: selected, folderName: folder)
                        selected.removeAll()
                        selectionMode = false
                        showFolderPicker = false
                    },
                    onCancel: { showFolderPicker = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: Binding(get: { openID.map { MomentID(id: $0) } }, set: { openID = $0?.id })) { wrapper in
                MemoryDetailView(momentID: wrapper.id)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { playbackCoordinator.stop(resetTime: true) }
            }
            .alert("이 기억을 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("취소", role: .cancel) { pendingDelete = nil }
                Button("삭제", role: .destructive) {
                    if let m = pendingDelete { engine.moveToTrash(m) }
                    pendingDelete = nil
                }
            } message: {
                Text("삭제된 항목에서 다시 복원할 수 있어요.")
            }
        }
    }

    private var header: some View {
        Group {
            if selectionMode {
                HStack(spacing: 10) {
                    Text("\(selected.count)개 선택")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button("완료") {
                        selectionMode = false
                        selected.removeAll()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HoldOnTheme.ink)
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    Text("기억").font(.system(size: 31, weight: .bold))

                    Button { oldestFirst.toggle() } label: {
                        HStack(spacing: 4) {
                            Text(oldestFirst ? "오래된 순" : "최신순")
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HoldOnTheme.ink.opacity(0.72))
                    .buttonStyle(.plain)

                    Menu {
                        Button("전체 기억") { activeFolder = nil }
                        if !engine.memoryFolderNames.isEmpty { Divider() }
                        ForEach(engine.memoryFolderNames, id: \.self) { folder in
                            Button(folder) { activeFolder = folder }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                            Text(activeFolder ?? "폴더")
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(HoldOnTheme.purple.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Button("선택") { selectionMode = true }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(HoldOnTheme.ink)
                        .buttonStyle(.plain)
                        .fixedSize()

                    Button { showTrash = true } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(HoldOnTheme.ink.opacity(0.72))
                            .frame(width: 34, height: 30)
                            .background(HoldOnTheme.ink.opacity(0.055), in: Capsule())
                    }
                    .accessibilityLabel("지운기억함")
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var selectionActionBar: some View {
        HStack(spacing: 8) {
            Button {
                if selected.count == moments.count && !moments.isEmpty {
                    selected.removeAll()
                } else {
                    selected = Set(moments.map(\.id))
                }
            } label: {
                selectionActionLabel(
                    selected.count == moments.count && !moments.isEmpty ? "선택 해제" : "전체 선택",
                    symbol: selected.count == moments.count && !moments.isEmpty ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(HoldOnTheme.ink)

            Button {
                showFolderPicker = true
            } label: {
                selectionActionLabel("폴더로 이동", symbol: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(HoldOnTheme.ink)
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.35 : 1)

            Button(role: .destructive) { deleteSelection() } label: {
                selectionActionLabel("삭제", symbol: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.78))
        .overlay(alignment: .bottom) { Divider().opacity(0.28) }
    }

    private func selectionActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(HoldOnTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func deleteSelection() {
        let targets = engine.savedMoments.filter { selected.contains($0.id) }
        engine.moveToTrash(targets)
        selected.removeAll()
    }
}

private struct MemoryFolderPickerSheet: View {
    let existingFolders: [String]
    let onChoose: (String?) -> Void
    let onCancel: () -> Void
    @State private var newFolder = ""

    var body: some View {
        NavigationStack {
            List {
                Section("새 폴더") {
                    HStack {
                        TextField("폴더 이름", text: $newFolder)
                            .textInputAutocapitalization(.never)
                        Button("만들기") {
                            let clean = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            onChoose(clean)
                        }
                        .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !existingFolders.isEmpty {
                    Section("기존 폴더") {
                        ForEach(existingFolders, id: \.self) { folder in
                            Button {
                                onChoose(folder)
                            } label: {
                                Label(folder, systemImage: "folder")
                            }
                        }
                    }
                }
                Section {
                    Button("폴더에서 빼기") { onChoose(nil) }
                }
            }
            .navigationTitle("폴더로 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("취소", action: onCancel) } }
        }
    }
}

private struct MomentID: Identifiable { let id: UUID }

struct DeletedItemsView: View {
    @EnvironmentObject private var engine: AudioHoldEngine
    @EnvironmentObject private var playbackCoordinator: MemoryPreviewPlaybackCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var pendingPermanentDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                HoldOnTheme.ambientBackground
                if engine.trashedMoments.isEmpty {
                    ContentUnavailableView("지운 기억이 없어요", systemImage: "tray.full")
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 5) {
                            ForEach(engine.trashedMoments) { moment in
                                VStack(spacing: 5) {
                                    MemoryCard(
                                        moment: moment,
                                        selected: selected.contains(moment.id),
                                        selectionMode: true,
                                        showsPlayback: false,
                                        onToggleSelection: { toggle(moment.id) }
                                    )
                                    HStack {
                                        Text("\(engine.trashDaysRemaining(for: moment))일 후 자동 삭제")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(HoldOnTheme.muted)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                        .padding(.bottom, 90)
                    }
                }
            }
            .navigationTitle("삭제된 항목")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selected.count == engine.trashedMoments.count ? "선택 해제" : "전체 선택") {
                        if selected.count == engine.trashedMoments.count { selected.removeAll() }
                        else { selected = Set(engine.trashedMoments.map(\.id)) }
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("복원") {
                        engine.trashedMoments.filter { selected.contains($0.id) }.forEach(engine.restoreMoment)
                        selected.removeAll()
                    }.disabled(selected.isEmpty)
                    Spacer()
                    Button("영구 삭제", role: .destructive) { pendingPermanentDelete = true }.disabled(selected.isEmpty)
                }
            }
            .alert("선택한 기억을 영구 삭제할까요?", isPresented: $pendingPermanentDelete) {
                Button("취소", role: .cancel) {}
                Button("영구 삭제", role: .destructive) {
                    engine.trashedMoments.filter { selected.contains($0.id) }.forEach(engine.permanentlyDeleteMoment)
                    selected.removeAll()
                }
            } message: { Text("이 작업은 되돌릴 수 없어요.") }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
