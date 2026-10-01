import Foundation
import AVFAudio
import AVFoundation
import AudioToolbox
import SwiftUI
import UserNotifications

@MainActor
final class AudioHoldEngine: ObservableObject {
    @Published private(set) var isHoldOn = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isRecordingActive = false
    @Published private(set) var segmentCount = 0
    @Published private(set) var rollingSeconds: TimeInterval = 0
    @Published private(set) var captureSeconds: TimeInterval = 0
    @Published private(set) var savedMoments: [SavedMoment] = []
    @Published private(set) var trashedMoments: [SavedMoment] = []
    @Published private(set) var lastSavedMomentID: UUID?
    @Published var selectedPreSeconds: Int = 300
    @Published var statusText = "Hold On을 켜면 최근 5분 50초까지 잠시 품고 있어요."
    @Published private(set) var routineEnabled = false
    @Published private(set) var routineOnMinutes = 8 * 60
    @Published private(set) var routineOffMinutes = 22 * 60

    private var engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let diagnostics = DiagnosticsStore()
    private let audioFileLock = NSLock()
    private let callbackStateLock = NSLock()

    private let maxRollingSeconds: TimeInterval = 5 * 60 + 50
    private let maxCaptureSeconds: TimeInterval = 60 * 60
    private let captureWarningSeconds: TimeInterval = 55 * 60
    private let captureWarningNotificationID = "holdon.capture.warning.v1"
    private let routineOnNotificationID = "holdon.routine.on.v1"
    private let standbyStoppedNotificationID = "holdon.standby.stopped.v1"
    private let standbyHeartbeatGraceSeconds: TimeInterval = 240
    private let segmentSeconds: TimeInterval = 15
    private let preferredPreSecondsKey = "holdon.preferredPreSeconds.v110"

    private var currentFile: AVAudioFile?
    private var currentSegmentStart: Date?
    private var currentFormat: AVAudioFormat?
    private var segments: [AudioSegment] = []
    private var captureStartedAt: Date?
    private var captureAnchor: Date?
    private var activeCapturePreSeconds: Int = 0
    private var protectedSegmentIDs = Set<UUID>()
    private var tapInstalled = false
    private var heartbeatTask: Task<Void, Never>?
    private var interruptionActive = false
    private var interruptionRecoveryTask: Task<Void, Never>?
    private var recoveryRetryTask: Task<Void, Never>?
    // Every audio edit render gets a revision. If the user changes/restores another
    // segment before an older export finishes, only the newest revision may replace
    // the playable file. This prevents overlapping autosaves from fighting each other.
    private var audioEditRevision: [UUID: Int] = [:]
    private var standbyStoppedNotificationSent = false
    private var lastRecoveryAttemptAt = Date.distantPast
    private var lastCallbackPublishAt = Date.distantPast
    private var lastAudioCallbackAt: Date?
    private var lastEngineStartAt = Date.distantPast
    private let desiredStateKey = "holdon.desiredOn.v6"
    private let routineEnabledKey = "holdon.routine.enabled.v1"
    private let routineOnMinutesKey = "holdon.routine.onMinutes.v1"
    private let routineOffMinutesKey = "holdon.routine.offMinutes.v1"
    private let routineLastActionKey = "holdon.routine.lastAction.v1"
    private let routineManualOffAtKey = "holdon.routine.manualOffAt.v1"
    private var routineTask: Task<Void, Never>?

    private lazy var rollingURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("HoldOnRolling", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private lazy var savedURL: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("HoldOnSaved", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private lazy var indexURL: URL = {
        savedURL.appendingPathComponent("moments.json")
    }()

    private lazy var trashIndexURL: URL = {
        savedURL.appendingPathComponent("trash.json")
    }()

    private lazy var indexBackupURL: URL = {
        savedURL.appendingPathComponent("moments.backup.json")
    }()

    private lazy var globalCardImageURL: URL = {
        savedURL.appendingPathComponent("global_card_background.jpg")
    }()

    private struct TrashRecord: Codable {
        let moment: SavedMoment
        let deletedAt: Date
    }

    // Single backing store for deleted memories. `trashedMoments` is the published projection.
    private var trashRecords: [TrashRecord] = []


    var globalCardPhotoPreviewURL: URL? {
        FileManager.default.fileExists(atPath: globalCardImageURL.path) ? globalCardImageURL : nil
    }

    var rollingDurationText: String { format(rollingSeconds) }
    var captureDurationText: String { format(captureSeconds) }
    var captureHasHistory: Bool { isCapturing && activeCapturePreSeconds > 0 }

    private func resetAudioCallbackState() {
        callbackStateLock.lock()
        defer { callbackStateLock.unlock() }
        lastCallbackPublishAt = .distantPast
        lastAudioCallbackAt = nil
    }

    private func snapshotLastAudioCallbackAt() -> Date? {
        callbackStateLock.lock()
        defer { callbackStateLock.unlock() }
        return lastAudioCallbackAt
    }

    init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: preferredPreSecondsKey) as? Int {
            selectedPreSeconds = min(350, max(0, stored))
        } else {
            // One-time migration. A legacy 0 is treated as the old regression, not as the new default.
            // After v110, an intentional 0 is stored in preferredPreSecondsKey and is preserved.
            let legacy = defaults.object(forKey: "holdon.preSeconds.v9") as? Int
            let migrated = (legacy ?? 0) > 0 ? min(350, max(0, legacy ?? 300)) : 300
            selectedPreSeconds = migrated
            defaults.set(migrated, forKey: preferredPreSecondsKey)
        }
        clearRollingCacheOnLaunch()
        loadSavedMoments()
        loadTrash()
        purgeExpiredTrash()
        loadRoutineSettings()
        registerForAudioEvents()
        startRoutineMonitor()
        if UserDefaults.standard.bool(forKey: desiredStateKey) {
            isHoldOn = true
            statusText = "HOLD ON 상태를 복구하고 있어요."
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.refreshStandbyFallbackNotification(reason: "launchRestore")
                self.recoverIfNeeded(reason: "launchRestore", allowInterruptedRetry: true)
                self.startHeartbeat()
            }
        }
    }

    func setRoutineEnabled(_ enabled: Bool) {
        routineEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: routineEnabledKey)
        // Changing routine settings should not retroactively fire an event that already passed.
        if enabled {
            acknowledgeCurrentRoutineBoundary()
            requestNotificationPermissionAndScheduleRoutineOnReminder()
        } else {
            UserDefaults.standard.removeObject(forKey: routineLastActionKey)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [routineOnNotificationID])
        }
    }

    func setRoutineOnMinutes(_ minutes: Int) {
        routineOnMinutes = min(1439, max(0, minutes))
        UserDefaults.standard.set(routineOnMinutes, forKey: routineOnMinutesKey)
        if routineEnabled {
            acknowledgeCurrentRoutineBoundary()
            requestNotificationPermissionAndScheduleRoutineOnReminder()
        }
    }

    func setRoutineOffMinutes(_ minutes: Int) {
        routineOffMinutes = min(1439, max(0, minutes))
        UserDefaults.standard.set(routineOffMinutes, forKey: routineOffMinutesKey)
        if routineEnabled { acknowledgeCurrentRoutineBoundary() }
    }

    func evaluateRoutine(at date: Date = Date()) {
        guard routineEnabled else { return }
        let defaults = UserDefaults.standard
        let onEvent = mostRecentRoutineEvent(minutes: routineOnMinutes, at: date)
        let offEvent = mostRecentRoutineEvent(minutes: routineOffMinutes, at: date)

        // Resolve the schedule from the most recent boundary, not from exact-minute equality.
        // That makes the routine recover correctly after a delayed timer/foreground return.
        // If ON/OFF are identical, ON wins by product rule.
        let shouldBeOn = routineOnMinutes == routineOffMinutes || onEvent >= offEvent
        let boundary = shouldBeOn ? onEvent : offEvent
        let action = shouldBeOn ? "on" : "off"
        let marker = "\(Int(boundary.timeIntervalSince1970))-\(action)"

        // Apply each schedule boundary at most once. This lets a manual ON/OFF made after
        // that boundary remain authoritative until the next scheduled boundary.
        guard defaults.string(forKey: routineLastActionKey) != marker else { return }
        defaults.set(marker, forKey: routineLastActionKey)

        if shouldBeOn {
            // iOS does not guarantee that a suspended app can wake at an exact time and
            // start a new microphone session. Build 139 therefore treats the ON boundary
            // as a reminder-only event. The repeating local notification is the user-facing
            // trigger, and tapping it calls handleRoutineOnNotificationTap().
            // Do NOT catch up by silently turning HOLD ON on when the app later returns.
            return
        } else {
            guard isHoldOn else {
                defaults.set(false, forKey: desiredStateKey)
                return
            }
            // Routine OFF is a real desired-state change and must survive relaunch.
            defaults.set(false, forKey: desiredStateKey)
            stopHoldOn(userInitiated: false, reason: "routineOff")
        }
    }

    private func mostRecentRoutineEvent(minutes: Int, at date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let todayEvent = calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? startOfDay
        if todayEvent <= date { return todayEvent }
        return calendar.date(byAdding: .day, value: -1, to: todayEvent) ?? todayEvent
    }

    private func acknowledgeCurrentRoutineBoundary(at date: Date = Date()) {
        guard routineEnabled else { return }
        let onEvent = mostRecentRoutineEvent(minutes: routineOnMinutes, at: date)
        let offEvent = mostRecentRoutineEvent(minutes: routineOffMinutes, at: date)
        let shouldBeOn = routineOnMinutes == routineOffMinutes || onEvent >= offEvent
        let boundary = shouldBeOn ? onEvent : offEvent
        let action = shouldBeOn ? "on" : "off"
        UserDefaults.standard.set("\(Int(boundary.timeIntervalSince1970))-\(action)", forKey: routineLastActionKey)
    }

    private func loadRoutineSettings() {
        let defaults = UserDefaults.standard
        routineEnabled = defaults.bool(forKey: routineEnabledKey)
        if defaults.object(forKey: routineOnMinutesKey) != nil {
            routineOnMinutes = min(1439, max(0, defaults.integer(forKey: routineOnMinutesKey)))
        }
        if defaults.object(forKey: routineOffMinutesKey) != nil {
            routineOffMinutes = min(1439, max(0, defaults.integer(forKey: routineOffMinutesKey)))
        }
        if routineEnabled {
            scheduleRoutineOnReminderIfAuthorized()
        }
    }

    func handleRoutineOnNotificationTap() {
        guard routineEnabled else { return }
        // A notification tap is an explicit user action. Turn HOLD ON on immediately rather than
        // waiting for the 15-second routine monitor loop.
        UserDefaults.standard.removeObject(forKey: routineManualOffAtKey)
        Task { [weak self] in
            try? await self?.startHoldOn(persistIntent: true)
        }
    }

    private func requestNotificationPermissionAndScheduleRoutineOnReminder() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self.scheduleRoutineOnReminder() }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in self.scheduleRoutineOnReminder() }
                }
            default:
                break
            }
        }
    }

    private func scheduleRoutineOnReminderIfAuthorized() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else { return }
            Task { @MainActor in self.scheduleRoutineOnReminder() }
        }
    }

    private func scheduleRoutineOnReminder() {
        guard routineEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [routineOnNotificationID])

        let content = UNMutableNotificationContent()
        content.title = "HOLD ON을 켤 시간이에요"
        content.body = "탭하면 바로 HOLD ON을 켤게요."
        content.sound = .default
        content.userInfo = ["holdonAction": "routineOn"]

        var components = DateComponents()
        components.hour = routineOnMinutes / 60
        components.minute = routineOnMinutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: routineOnNotificationID, content: content, trigger: trigger))
    }

    private func startRoutineMonitor() {
        routineTask?.cancel()
        routineTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluateRoutine()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func startHoldOn(persistIntent: Bool = true) async throws {
        if isHoldOn {
            if persistIntent { UserDefaults.standard.set(true, forKey: desiredStateKey) }
            requestStandbyNotificationPermissionIfNeeded()
            refreshStandbyFallbackNotification(reason: "startWhileDesiredOn")
            recoverIfNeeded(reason: "startWhileDesiredOn", allowInterruptedRetry: true)
            return
        }

        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            UserDefaults.standard.set(false, forKey: desiredStateKey)
            isHoldOn = false
            statusText = "마이크 권한이 필요합니다."
            return
        }

        resetAudioCallbackState()
        isHoldOn = true
        standbyStoppedNotificationSent = false
        requestStandbyNotificationPermissionIfNeeded()
        refreshStandbyFallbackNotification(reason: "start")
        if persistIntent {
            UserDefaults.standard.set(true, forKey: desiredStateKey)
            UserDefaults.standard.removeObject(forKey: routineManualOffAtKey)
        }
        diagnostics.beginSession()
        startHeartbeat()
        do {
            try configureAndStartEngine()
            statusText = "최근 5분 50초까지 덮어쓰기 중 · 저장은 잡기로 해요."
        } catch {
            isRecordingActive = false
            statusText = "오디오 연결을 다시 시도하고 있어요."
            diagnostics.record("initialStartFailed", ["error": error.localizedDescription])
            scheduleRecoveryRetries(reason: "initialStart")
            throw error
        }
    }

    func stopHoldOn(userInitiated: Bool = true, reason: String = "userStop") {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        interruptionRecoveryTask?.cancel()
        interruptionRecoveryTask = nil
        recoveryRetryTask?.cancel()
        recoveryRetryTask = nil
        standbyStoppedNotificationSent = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [standbyStoppedNotificationID])

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        closeCurrentSegment()
        clearRollingBuffer()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        isHoldOn = false
        if userInitiated {
            UserDefaults.standard.set(false, forKey: desiredStateKey)
            if routineEnabled {
                UserDefaults.standard.set(Date(), forKey: routineManualOffAtKey)
            }
        }
        isRecordingActive = false
        isCapturing = false
        captureStartedAt = nil
        captureAnchor = nil
        protectedSegmentIDs.removeAll()
        diagnostics.endSession(reason: reason)
        statusText = "지금은 아무 소리도 기억하고 있지 않아요."
        Task { await HoldOnCaptureActivity.endAll() }
    }

    func prepareForMemoryPlayback() {
        do {
            if isHoldOn {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
                )
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            if isHoldOn { try? session.overrideOutputAudioPort(.speaker) }
        } catch {
            diagnostics.record("memoryPlaybackSessionFailed", ["error": error.localizedDescription])
        }
    }

    func updateCapturePreSeconds(_ seconds: Int) {
        let clamped = min(max(seconds, 0), 350)
        selectedPreSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: preferredPreSecondsKey)
        guard isCapturing, let anchor = captureAnchor else { return }
        activeCapturePreSeconds = clamped
        let cutoff = anchor.addingTimeInterval(TimeInterval(-clamped))
        protectedSegmentIDs = Set(segments.filter { $0.endDate >= cutoff }.map(\.id))
        diagnostics.record("capturePreSecondsChanged", ["preSeconds": String(clamped)])
    }

    func beginCapture(preSeconds: Int) {
        guard isHoldOn, !isCapturing else { return }

        activeCapturePreSeconds = min(max(preSeconds, 0), 350)
        isCapturing = true
        let now = Date()
        captureStartedAt = now
        captureAnchor = now

        let cutoff = now.addingTimeInterval(TimeInterval(-activeCapturePreSeconds))
        protectedSegmentIDs = Set(
            segments.filter { $0.endDate >= cutoff }.map(\.id)
        )

        diagnostics.record("captureStarted", ["preSeconds": String(activeCapturePreSeconds), "selectedPreSeconds": String(selectedPreSeconds)])
        statusText = "잡는 중 · 다시 누르면 저장"
        scheduleCaptureLimitWarning()

    }

    func cancelCapture() {
        guard isCapturing else { return }
        diagnostics.record("captureCancelled", ["elapsedSeconds": String(format: "%.1f", captureSeconds)])
        cancelCaptureLimitWarning()
        isCapturing = false
        captureStartedAt = nil
        captureAnchor = nil
        captureSeconds = 0
        protectedSegmentIDs.removeAll()
        activeCapturePreSeconds = 0
        statusText = "저장하지 않고 중단했어요."
        pruneRollingWindow()
    }

    private func scheduleCaptureLimitWarning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [captureWarningNotificationID])

        Task {
            let settings = await center.notificationSettings()
            var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            guard allowed else {
                diagnostics.record("captureLimitWarningUnavailable")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "HOLD ON"
            content.body = "순간잡기가 5분 뒤 자동으로 중단돼요. 남길 순간이라면 지금 저장해 주세요."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: captureWarningSeconds, repeats: false)
            let request = UNNotificationRequest(identifier: captureWarningNotificationID, content: content, trigger: trigger)
            do {
                try await center.add(request)
                diagnostics.record("captureLimitWarningScheduled", ["afterSeconds": String(Int(captureWarningSeconds))])
            } catch {
                diagnostics.record("captureLimitWarningScheduleFailed", ["error": error.localizedDescription])
            }
        }
    }

    private func cancelCaptureLimitWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [captureWarningNotificationID])
    }

    private func automaticSkyFile(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .day, .minute], from: date)
        let h = c.hour ?? 12, seed = ((c.day ?? 1) * 37 + (c.minute ?? 0))
        let pool: [String]
        switch h {
        case 0..<5, 21..<24: pool = ["sky_01.jpg","sky_02.jpg","sky_14.jpg","sky_15.jpg","sky_22.png","sky_23.png"]
        case 5..<8: pool = ["sky_03.jpg","sky_04.jpg","sky_17.jpg","sky_21.jpg"]
        case 8..<17: pool = ["sky_05.jpg","sky_06.jpg","sky_07.png","sky_08.jpg","sky_10.jpg","sky_12.jpg","sky_19.jpg"]
        default: pool = ["sky_09.png","sky_11.jpg","sky_13.jpg","sky_16.png","sky_18.jpg","sky_20.png","sky_21.jpg"]
        }
        return pool[abs(seed) % pool.count]
    }

    func finishCapture() {
        guard isCapturing else { return }

        // 현재 열려 있는 조각도 저장 대상에 확실히 포함시키기 위해 여기서 한 번 회전합니다.
        if let format = currentFormat {
            closeCurrentSegment()
            openNewSegment(format: format)
        }

        cancelCaptureLimitWarning()
        let finishTime = Date()
        let anchor = captureAnchor ?? finishTime
        let cutoff = anchor.addingTimeInterval(TimeInterval(-activeCapturePreSeconds))
        let snapshot = segments.filter { $0.endDate >= cutoff && $0.startDate <= finishTime }

        isCapturing = false
        captureStartedAt = nil
        captureAnchor = nil

        do {
            let desiredStart = anchor.addingTimeInterval(TimeInterval(-activeCapturePreSeconds))
            var moment = try makeSavedMoment(
                from: snapshot,
                desiredStart: desiredStart,
                desiredEnd: finishTime,
                preSeconds: activeCapturePreSeconds
            )
            // New memories inherit the current global card defaults once, then become independent.
            let defaults = UserDefaults.standard
            moment.cardRatio = defaults.string(forKey: "holdon.card.global.ratio") ?? "4:1"
            moment.cardBackgroundKind = defaults.string(forKey: "holdon.card.global.backgroundKind") ?? "sky"
            let configuredBackground = defaults.string(forKey: "holdon.card.global.backgroundValue") ?? "auto"
            moment.cardBackgroundValue = (moment.cardBackgroundKind == "sky" && configuredBackground == "auto") ? automaticSkyFile(for: moment.createdAt) : configuredBackground
            moment.titleFont = defaults.string(forKey: "holdon.card.global.titleFont") ?? "serif"
            moment.titleSize = defaults.object(forKey: "holdon.card.global.titleSize") as? Double
            moment.inkHex = defaults.string(forKey: "holdon.card.global.inkHex") ?? "#FFFFFF"
            moment.showsHoldOnMark = defaults.object(forKey: "holdon.card.global.showsHoldOnMark") as? Bool ?? true
            if moment.cardBackgroundKind == "album", FileManager.default.fileExists(atPath: globalCardImageURL.path) {
                try? FileManager.default.removeItem(at: moment.cardImageURL)
                try? FileManager.default.copyItem(at: globalCardImageURL, to: moment.cardImageURL)
            }
            savedMoments.insert(moment, at: 0)
                lastSavedMomentID = moment.id
            saveIndex()
            diagnostics.record("captureSaved", ["durationSeconds": String(format: "%.1f", moment.durationSeconds), "preSeconds": String(moment.preSeconds)])
            statusText = "저장했어요 ✓"
        } catch {
            diagnostics.record("captureSaveFailed", ["error": error.localizedDescription])
            statusText = "저장 실패: \(error.localizedDescription)"
        }

        protectedSegmentIDs.removeAll()
        activeCapturePreSeconds = 0
        pruneRollingWindow()
    }

    /// Saves the selected history immediately using the standard time title.
    func captureNow(preSeconds: Int) {
        guard isHoldOn, isRecordingActive, !isCapturing else { return }
        beginCapture(preSeconds: preSeconds)
        finishCapture()
    }

    func deleteMoment(_ moment: SavedMoment) {
        moveToTrash(moment)
    }

    func moveToTrash(_ moment: SavedMoment) {
        guard savedMoments.contains(where: { $0.id == moment.id }) else { return }
        savedMoments.removeAll { $0.id == moment.id }
        trashRecords.removeAll { $0.moment.id == moment.id }
        trashRecords.insert(TrashRecord(moment: moment, deletedAt: Date()), at: 0)
        syncTrashPublished()
        saveIndex()
        saveTrash()
    }

    func moveToTrash(_ moments: [SavedMoment]) {
        for moment in moments { moveToTrash(moment) }
    }

    func restoreMoment(_ moment: SavedMoment) {
        guard trashRecords.contains(where: { $0.moment.id == moment.id }) else { return }
        trashRecords.removeAll { $0.moment.id == moment.id }
        if !savedMoments.contains(where: { $0.id == moment.id }) {
            savedMoments.append(moment)
            savedMoments.sort { $0.createdAt > $1.createdAt }
        }
        syncTrashPublished()
        saveIndex()
        saveTrash()
    }

    func permanentlyDeleteMoment(_ moment: SavedMoment) {
        deleteMomentFiles(moment)
        trashRecords.removeAll { $0.moment.id == moment.id }
        savedMoments.removeAll { $0.id == moment.id }
        syncTrashPublished()
        saveIndex()
        saveTrash()
    }

    func trashDaysRemaining(for moment: SavedMoment) -> Int {
        guard let record = trashRecords.first(where: { $0.moment.id == moment.id }) else { return 0 }
        let elapsed = Calendar.current.dateComponents([.day], from: record.deletedAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }

    func renameMoment(_ moment: SavedMoment, title: String) {
        guard let index = savedMoments.firstIndex(where: { $0.id == moment.id }) else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        savedMoments[index].title = clean
        saveIndex()
    }

    func assignFolder(momentIDs: Set<UUID>, folderName: String?) {
        let clean = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (clean?.isEmpty == false) ? clean : nil
        var changed = false
        for index in savedMoments.indices where momentIDs.contains(savedMoments[index].id) {
            savedMoments[index].folderName = normalized
            changed = true
        }
        if changed { saveIndex() }
    }

    var memoryFolderNames: [String] {
        Array(Set(savedMoments.compactMap { moment in
            let name = moment.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Storage management

    func markMomentExportedToPhotos(id: UUID) {
        guard let index = savedMoments.firstIndex(where: { $0.id == id }) else { return }
        savedMoments[index].exportedToPhotosAt = Date()
        saveIndex()
    }

    func holdOnDataBytes() -> Int64 {
        directoryBytes(savedURL) + directoryBytes(rollingURL)
    }

    func momentStorageBytes(_ moment: SavedMoment) -> Int64 {
        let originalURL = savedURL.appendingPathComponent("original_\(moment.id.uuidString).m4a")
        return fileBytes(moment.audioURL) + fileBytes(moment.cardImageURL) + fileBytes(originalURL)
    }

    func trashStorageBytes() -> Int64 {
        trashedMoments.reduce(0) { $0 + momentStorageBytes($1) }
    }

    func emptyTrash() {
        for record in trashRecords { deleteMomentFiles(record.moment) }
        trashRecords.removeAll()
        syncTrashPublished()
        saveTrash()
        saveIndex()
    }

    private func fileBytes(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func directoryBytes(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func deleteMomentFiles(_ moment: SavedMoment) {
        try? FileManager.default.removeItem(at: moment.audioURL)
        try? FileManager.default.removeItem(at: moment.cardImageURL)
        let originalURL = savedURL.appendingPathComponent("original_\(moment.id.uuidString).m4a")
        try? FileManager.default.removeItem(at: originalURL)
    }

    func updateMomentCardAppearance(
        id: UUID,
        ratio: String? = nil,
        backgroundKind: String? = nil,
        backgroundValue: String? = nil,
        titleFont: String? = nil,
        titleSize: Double? = nil,
        inkHex: String? = nil,
        showsHoldOnMark: Bool? = nil
    ) {
        guard let index = savedMoments.firstIndex(where: { $0.id == id }) else { return }
        if let ratio { savedMoments[index].cardRatio = ratio }
        if let backgroundKind { savedMoments[index].cardBackgroundKind = backgroundKind }
        if let backgroundValue { savedMoments[index].cardBackgroundValue = backgroundValue }
        if let titleFont { savedMoments[index].titleFont = titleFont }
        if let titleSize { savedMoments[index].titleSize = titleSize }
        if let inkHex { savedMoments[index].inkHex = inkHex }
        if let showsHoldOnMark { savedMoments[index].showsHoldOnMark = showsHoldOnMark }
        saveIndex()
    }

    func setMomentCardPhoto(id: UUID, jpegData: Data) {
        guard let index = savedMoments.firstIndex(where: { $0.id == id }) else { return }
        do {
            try jpegData.write(to: savedMoments[index].cardImageURL, options: .atomic)
            savedMoments[index].cardBackgroundKind = "album"
            savedMoments[index].cardBackgroundValue = nil
            savedMoments[index].cardImageRevision = (savedMoments[index].cardImageRevision ?? 0) + 1
            saveIndex()
        } catch {
            diagnostics.record("cardPhotoWriteFailed", ["momentID": id.uuidString, "error": error.localizedDescription])
        }
    }

    func setPlaybackGain(momentID: UUID, gain: Double) {
        guard let index = savedMoments.firstIndex(where: { $0.id == momentID }) else { return }
        let clamped = min(5.0, max(1.0, gain))
        savedMoments[index].playbackGain = clamped
        saveIndex()
        diagnostics.record("playbackGainChanged", [
            "momentID": momentID.uuidString,
            "gain": String(format: "%.1f", clamped)
        ])
    }

    func setGlobalCardPhoto(jpegData: Data) {
        do {
            try jpegData.write(to: globalCardImageURL, options: .atomic)
            UserDefaults.standard.set("album", forKey: "holdon.card.global.backgroundKind")
            UserDefaults.standard.removeObject(forKey: "holdon.card.global.backgroundValue")
        } catch {
            diagnostics.record("globalCardPhotoWriteFailed", ["error": error.localizedDescription])
        }
    }

    func hasGlobalCardPhoto() -> Bool {
        FileManager.default.fileExists(atPath: globalCardImageURL.path)
    }

    func applyAudioEdit(
        momentID: UUID,
        trimStart: Double,
        trimEnd: Double,
        deletedRanges: [[Double]],
        splitPoints: [Double]? = nil
    ) async throws {
        guard let index = savedMoments.firstIndex(where: { $0.id == momentID }) else { return }
        var normalized = HoldOnAudioEditState(
            trimStart: min(max(trimStart, 0), 1),
            trimEnd: min(max(trimEnd, max(trimStart, 0) + 0.001), 1),
            deletedRanges: deletedRanges,
            sourceDuration: savedMoments[index].audioEdit?.sourceDuration,
            splitPoints: splitPoints ?? savedMoments[index].audioEdit?.splitPoints
        )
        if normalized.sourceDuration == nil {
            let originalURL = savedURL.appendingPathComponent("original_\(momentID.uuidString).m4a")
            if let file = try? AVAudioFile(forReading: originalURL), file.processingFormat.sampleRate > 0 {
                normalized.sourceDuration = Double(file.length) / file.processingFormat.sampleRate
            } else {
                normalized.sourceDuration = savedMoments[index].durationSeconds
            }
        }
        let revision = (audioEditRevision[momentID] ?? 0) + 1
        audioEditRevision[momentID] = revision
        savedMoments[index].audioEdit = normalized
        try await renderAudioEdit(momentIndex: index, revision: revision)
        saveIndex()
    }

    func updateAudioSplitPoints(momentID: UUID, splitPoints: [Double]) {
        guard let index = savedMoments.firstIndex(where: { $0.id == momentID }) else { return }
        if savedMoments[index].audioEdit == nil {
            savedMoments[index].audioEdit = HoldOnAudioEditState(
                trimStart: 0,
                trimEnd: 1,
                deletedRanges: [],
                sourceDuration: savedMoments[index].durationSeconds,
                splitPoints: splitPoints
            )
        } else {
            savedMoments[index].audioEdit?.splitPoints = splitPoints
        }
        saveIndex()
    }

    func resetAudioEdit(momentID: UUID) throws {
        guard let index = savedMoments.firstIndex(where: { $0.id == momentID }) else { return }
        // Invalidate any render that was already in flight before restoring the original.
        audioEditRevision[momentID] = (audioEditRevision[momentID] ?? 0) + 1
        let moment = savedMoments[index]
        let originalURL = savedURL.appendingPathComponent("original_\(moment.id.uuidString).m4a")
        if FileManager.default.fileExists(atPath: originalURL.path) {
            try? FileManager.default.removeItem(at: moment.audioURL)
            try FileManager.default.copyItem(at: originalURL, to: moment.audioURL)
            if let file = try? AVAudioFile(forReading: moment.audioURL), file.processingFormat.sampleRate > 0 {
                savedMoments[index].durationSeconds = Double(file.length) / file.processingFormat.sampleRate
            }
        }
        savedMoments[index].audioEdit = nil
        saveIndex()
        diagnostics.record("audioEditReset", ["momentID": moment.id.uuidString])
    }

    func sourceAudioURL(for momentID: UUID) -> URL? {
        guard let moment = savedMoments.first(where: { $0.id == momentID }) else { return nil }
        let originalURL = savedURL.appendingPathComponent("original_\(momentID.uuidString).m4a")
        return FileManager.default.fileExists(atPath: originalURL.path) ? originalURL : moment.audioURL
    }

    func updateSubtitles(momentID: UUID, cues: [HoldOnSubtitleCue]) {
        guard let index = savedMoments.firstIndex(where: { $0.id == momentID }) else { return }
        savedMoments[index].subtitles = cues
            .filter { $0.end > $0.start }
            .map { cue in
                var c = cue
                c.start = max(0, c.start)
                c.end = max(c.start + 0.05, c.end)
                c.x = min(0.95, max(0.05, c.x))
                c.y = min(0.95, max(0.05, c.y))
                c.scale = min(3, max(0.35, c.scale))
                c.backgroundAlpha = min(1, max(0, c.backgroundAlpha))
                return c
            }
        saveIndex()
    }

    private func renderAudioEdit(momentIndex index: Int, revision: Int) async throws {
        let moment = savedMoments[index]
        let originalURL = savedURL.appendingPathComponent("original_\(moment.id.uuidString).m4a")
        if !FileManager.default.fileExists(atPath: originalURL.path) {
            try FileManager.default.copyItem(at: moment.audioURL, to: originalURL)
        }
        let edit = moment.audioEdit ?? HoldOnAudioEditState()
        let asset = AVURLAsset(url: originalURL)
        let duration = try await asset.load(.duration)
        let total = max(0.001, CMTimeGetSeconds(duration))
        if savedMoments[index].audioEdit?.sourceDuration == nil {
            savedMoments[index].audioEdit?.sourceDuration = total
        }
        let startF = min(max(edit.trimStart, 0), 1)
        let endF = min(max(edit.trimEnd, startF + 0.001), 1)
        let cuts: [(Double, Double)] = edit.deletedRanges.compactMap { r in
            guard r.count >= 2 else { return nil }
            let a = min(max(r[0], startF), endF)
            let b = min(max(r[1], a), endF)
            return b > a ? (a,b) : nil
        }.sorted { $0.0 < $1.0 }
        var keep: [(Double, Double)] = []
        var cursor = startF
        for (a,b) in cuts {
            if a > cursor { keep.append((cursor,a)) }
            cursor = max(cursor,b)
        }
        if cursor < endF { keep.append((cursor,endF)) }
        if keep.isEmpty { keep = [(startF,endF)] }

        let composition = AVMutableComposition()
        guard let dst = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let src = try await asset.loadTracks(withMediaType: .audio).first else { throw HoldOnError.noAudioInput }
        var at = CMTime.zero
        for (a,b) in keep {
            let aTime = CMTime(seconds: total * a, preferredTimescale: 600)
            let len = CMTime(seconds: total * (b-a), preferredTimescale: 600)
            try dst.insertTimeRange(CMTimeRange(start: aTime, duration: len), of: src, at: at)
            at = CMTimeAdd(at, len)
        }
        let temp = savedURL.appendingPathComponent("edit_\(moment.id.uuidString)_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: temp)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw HoldOnError.noAudioInput }
        export.outputURL = temp
        export.outputFileType = .m4a
        await withCheckedContinuation { continuation in export.exportAsynchronously { continuation.resume() } }
        guard export.status == .completed else { throw export.error ?? HoldOnError.noAudioInput }

        // A newer edit may have been requested while this export was running. In that
        // case this result is stale: discard it rather than overwriting the newer edit.
        guard audioEditRevision[moment.id] == revision else {
            try? FileManager.default.removeItem(at: temp)
            diagnostics.record("audioEditDiscardedStaleRender", ["momentID": moment.id.uuidString])
            return
        }

        try? FileManager.default.removeItem(at: moment.audioURL)
        try FileManager.default.moveItem(at: temp, to: moment.audioURL)
        savedMoments[index].durationSeconds = max(0, CMTimeGetSeconds(at))
        diagnostics.record("audioEdited", ["momentID": moment.id.uuidString, "durationSeconds": String(format: "%.1f", CMTimeGetSeconds(at))])
    }

    private func configureAndStartEngine() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw HoldOnError.noAudioInput
        }
        currentFormat = format

        if currentFile == nil {
            openNewSegment(format: format)
        }

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let now = Date()
            var shouldPublish = false
            var detectedGap: TimeInterval?

            self.callbackStateLock.lock()
            if let previous = self.lastAudioCallbackAt {
                let gap = now.timeIntervalSince(previous)
                if gap > 3.0 { detectedGap = gap }
            }
            self.lastAudioCallbackAt = now
            if now.timeIntervalSince(self.lastCallbackPublishAt) >= 1.0 {
                self.lastCallbackPublishAt = now
                shouldPublish = true
            }
            self.callbackStateLock.unlock()

            do {
                self.audioFileLock.lock()
                defer { self.audioFileLock.unlock() }
                try self.currentFile?.write(from: buffer)
            } catch {
                Task { @MainActor in
                    self.diagnostics.record("audioWriteFailed", ["error": error.localizedDescription])
                    self.statusText = "오디오 쓰기 오류: \(error.localizedDescription)"
                }
            }

            guard shouldPublish || detectedGap != nil else { return }
            Task { @MainActor in
                if let detectedGap {
                    self.diagnostics.record("audioGapDetected", ["gapSeconds": String(format: "%.2f", detectedGap)])
                }
                if shouldPublish {
                    self.rotateSegmentIfNeeded(format: format)
                    self.refreshDurations()
                }
            }
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        lastEngineStartAt = Date()
        isRecordingActive = engine.isRunning && tapInstalled
    }

    private func rotateSegmentIfNeeded(format: AVAudioFormat) {
        guard let start = currentSegmentStart else { return }
        if Date().timeIntervalSince(start) >= segmentSeconds {
            closeCurrentSegment()
            openNewSegment(format: format)
            pruneRollingWindow()
        }
    }

    private func openNewSegment(format: AVAudioFormat) {
        let id = UUID()
        let now = Date()
        let url = rollingURL.appendingPathComponent("\(id.uuidString).m4a")
        do {
            audioFileLock.lock()
            defer { audioFileLock.unlock() }
            currentFile = try AVAudioFile(forWriting: url, settings: aacSettings(for: format))
            currentSegmentStart = now
            segments.append(AudioSegment(id: id, url: url, startDate: now, endDate: now))
            segmentCount = segments.count
        } catch {
            diagnostics.record("segmentCreateFailed", ["error": error.localizedDescription])
            statusText = "세그먼트 생성 오류: \(error.localizedDescription)"
        }
    }

    private func closeCurrentSegment() {
        guard !segments.isEmpty else { return }
        let end = Date()
        segments[segments.count - 1].endDate = end
        audioFileLock.lock()
        currentFile = nil
        audioFileLock.unlock()
        currentSegmentStart = nil
    }

    private func clearRollingBuffer() {
        for segment in segments {
            try? FileManager.default.removeItem(at: segment.url)
        }
        segments.removeAll()
        protectedSegmentIDs.removeAll()
        currentFile = nil
        currentSegmentStart = nil
        segmentCount = 0
        rollingSeconds = 0
        captureSeconds = 0
    }

    private func clearRollingCacheOnLaunch() {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("HoldOnRolling", isDirectory: true)
        if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for file in files { try? fm.removeItem(at: file) }
        }
    }

    private func pruneRollingWindow() {
        let cutoff = Date().addingTimeInterval(-maxRollingSeconds)
        var keep: [AudioSegment] = []

        let captureCutoff = captureAnchor?.addingTimeInterval(TimeInterval(-activeCapturePreSeconds))
        for segment in segments {
            let protected = protectedSegmentIDs.contains(segment.id) || (isCapturing && captureCutoff != nil && segment.endDate >= captureCutoff!)
            let recent = segment.endDate >= cutoff
            if protected || recent {
                keep.append(segment)
            } else {
                try? FileManager.default.removeItem(at: segment.url)
            }
        }

        segments = keep
        segmentCount = segments.count
        refreshDurations()
    }

    private func refreshDurations() {
        if var last = segments.last, currentSegmentStart != nil {
            last.endDate = Date()
            segments[segments.count - 1].endDate = last.endDate
        }

        guard let first = segments.first else {
            rollingSeconds = 0
            captureSeconds = 0
            return
        }

        rollingSeconds = min(maxRollingSeconds, Date().timeIntervalSince(first.startDate))
        if let captureStartedAt {
            captureSeconds = Date().timeIntervalSince(captureStartedAt)
        } else {
            captureSeconds = 0
        }
    }


    private func aacSettings(for format: AVAudioFormat) -> [String: Any] {
        let channels = max(1, Int(format.channelCount))
        // Voice-first rolling audio: keep quality adequate for conversation while avoiding
        // the sustained ~128 kbps disk-write rate that triggered diskwrites_resource reports.
        let bitrate = channels == 1 ? 48_000 : 80_000
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate
        ]
    }

    private func makeSavedMoment(
        from sourceSegments: [AudioSegment],
        desiredStart: Date,
        desiredEnd: Date,
        preSeconds: Int
    ) throws -> SavedMoment {
        let valid = sourceSegments.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard let firstSegment = valid.first else {
            throw HoldOnError.noSegmentsToSave
        }

        let firstFile = try AVAudioFile(forReading: firstSegment.url)
        let outputFormat = firstFile.processingFormat
        let outputName = "\(UUID().uuidString).m4a"
        let outputURL = savedURL.appendingPathComponent(outputName)
        let output = try AVAudioFile(forWriting: outputURL, settings: aacSettings(for: outputFormat))
        var totalFrames: AVAudioFramePosition = 0

        for segment in valid {
            let overlapStart = max(segment.startDate, desiredStart)
            let overlapEnd = min(segment.endDate, desiredEnd)
            guard overlapEnd > overlapStart else { continue }

            let input = try AVAudioFile(forReading: segment.url)
            let inputFormat = input.processingFormat
            guard inputFormat.sampleRate == outputFormat.sampleRate,
                  inputFormat.channelCount == outputFormat.channelCount else {
                diagnostics.record("saveSkippedFormatChange", [
                    "sampleRate": String(inputFormat.sampleRate),
                    "channels": String(inputFormat.channelCount)
                ])
                continue
            }

            let startOffset = max(0, overlapStart.timeIntervalSince(segment.startDate))
            let endOffset = max(startOffset, overlapEnd.timeIntervalSince(segment.startDate))
            let startFrame = min(input.length, AVAudioFramePosition((startOffset * inputFormat.sampleRate).rounded()))
            let endFrame = min(input.length, AVAudioFramePosition((endOffset * inputFormat.sampleRate).rounded()))
            guard endFrame > startFrame else { continue }

            input.framePosition = startFrame
            var remaining = endFrame - startFrame
            let chunk: AVAudioFrameCount = 16_384

            while remaining > 0 {
                let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: count) else { break }
                try input.read(into: buffer, frameCount: count)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
                totalFrames += AVAudioFramePosition(buffer.frameLength)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
        }

        guard totalFrames > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw HoldOnError.noSegmentsToSave
        }

        let duration = outputFormat.sampleRate > 0 ? Double(totalFrames) / outputFormat.sampleRate : 0
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"

        return SavedMoment(
            id: UUID(),
            createdAt: Date(),
            title: formatter.string(from: Date()),
            audioFileName: outputName,
            preSeconds: preSeconds,
            durationSeconds: duration
        )
    }

    private func loadSavedMoments() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode([SavedMoment].self, from: data) {
            savedMoments = decoded.sorted { $0.createdAt > $1.createdAt }
            return
        }
        // Never fall back to mock/sample memories. Recover only from our last valid native index.
        if let data = try? Data(contentsOf: indexBackupURL),
           let decoded = try? decoder.decode([SavedMoment].self, from: data) {
            savedMoments = decoded.sorted { $0.createdAt > $1.createdAt }
            diagnostics.record("momentIndexRecoveredFromBackup")
            return
        }
        savedMoments = []
    }

    private func saveIndex() {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: indexURL.path),
               let current = try? Data(contentsOf: indexURL),
               (try? JSONDecoder().decode([SavedMoment].self, from: current)) != nil {
                try? current.write(to: indexBackupURL, options: .atomic)
            }
            let data = try JSONEncoder().encode(savedMoments)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            statusText = "목록 저장 오류: \(error.localizedDescription)"
        }
    }

    private func loadTrash() {
        guard let data = try? Data(contentsOf: trashIndexURL),
              let decoded = try? JSONDecoder().decode([TrashRecord].self, from: data) else {
            trashRecords = []
            trashedMoments = []
            return
        }
        trashRecords = decoded.sorted { $0.deletedAt > $1.deletedAt }
        syncTrashPublished()
    }

    private func saveTrash() {
        do {
            let data = try JSONEncoder().encode(trashRecords)
            try data.write(to: trashIndexURL, options: .atomic)
        } catch {
            statusText = "휴지통 저장 오류: \(error.localizedDescription)"
        }
    }

    private func syncTrashPublished() {
        trashedMoments = trashRecords.map { record in record.moment }
    }

    private func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let expired = trashRecords.filter { $0.deletedAt < cutoff }
        for record in expired { deleteMomentFiles(record.moment) }
        if !expired.isEmpty {
            trashRecords.removeAll { $0.deletedAt < cutoff }
            syncTrashPublished()
            saveTrash()
        }
    }

    private func registerForAudioEvents() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                self.handleInterruption(note)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                self.diagnostics.record("routeChanged", ["reason": String(reasonValue ?? 0)])
                guard self.isHoldOn else { return }
                self.statusText = "오디오 경로가 바뀌었어요 · Hold On 상태 확인 중"
                try? await Task.sleep(for: .milliseconds(350))
                if !self.interruptionActive && (!self.engine.isRunning || !self.tapInstalled) {
                    self.restartAudioEngine(reason: "routeChange", recreateEngine: false)
                } else {
                    self.isRecordingActive = self.engine.isRunning && self.tapInstalled
                }
            }
        }


        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.diagnostics.record("mediaServicesWereReset")
                guard self.isHoldOn else { return }
                self.restartAudioEngine(reason: "mediaServicesReset", recreateEngine: true)
            }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }

        switch type {
        case .began:
            interruptionRecoveryTask?.cancel()
            interruptionRecoveryTask = nil
            recoveryRetryTask?.cancel()
            recoveryRetryTask = nil
            interruptionActive = true
            if isHoldOn { UserDefaults.standard.set(true, forKey: desiredStateKey) }
            // A phone call is an expected iOS interruption, not a HOLD ON failure.
            // Cancel the watchdog fallback while the call owns the audio session so it cannot
            // fire a false "stopped" warning during a healthy interruption.
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [standbyStoppedNotificationID])
            diagnostics.record("interruptionBegan")
            statusText = "통화/오디오 중단 감지 · HOLD ON 일시중지"
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            isRecordingActive = false
            closeCurrentSegment()
        case .ended:
            interruptionActive = false
            guard isHoldOn else { return }
            // Preserve the user's HOLD ON intent across phone-call interruptions.
            UserDefaults.standard.set(true, forKey: desiredStateKey)
            statusText = "통화가 끝났어요 · HOLD ON 복구 중"
            diagnostics.record("interruptionEnded")

            // The input route can still be settling when interruptionEnded arrives.
            // Recreating AVAudioEngine synchronously here was brittle on physical devices after calls.
            // Give iOS a short route-settle window, then rebuild the graph; existing retry logic
            // remains as a fallback if the first delayed attempt still cannot start.
            interruptionRecoveryTask?.cancel()
            interruptionRecoveryTask = Task { [weak self] in
                // Calls can leave AVAudioSession in a half-restored route for a short period.
                // Explicitly deactivate after the interruption, let the route settle, then rebuild
                // the engine and reactivate our mixed recording session.
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self, self.isHoldOn else { return }
                try? self.session.setActive(false, options: .notifyOthersOnDeactivation)
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, self.isHoldOn else { return }
                self.restartAudioEngine(reason: "interruptionEndedRebuild", recreateEngine: true)
                if !self.isRecordingActive {
                    self.scheduleRecoveryRetries(reason: "interruptionEndedRebuild")
                }
            }
        @unknown default:
            break
        }
    }


    func recoverIfNeeded(reason: String = "foreground", allowInterruptedRetry: Bool = false) {
        let desiredOn = UserDefaults.standard.bool(forKey: desiredStateKey)
        guard isHoldOn || desiredOn else { return }

        if !isHoldOn && desiredOn {
            isHoldOn = true
            diagnostics.beginSession()
            startHeartbeat()
            diagnostics.record("desiredStateRestored", ["reason": reason])
        }


        if interruptionActive {
            guard allowInterruptedRetry || reason == "foreground" || reason == "launchRestore" else { return }
            interruptionActive = false
            diagnostics.record("staleInterruptionCleared", ["reason": reason])
        }
        if !engine.isRunning || !tapInstalled || !isRecordingActive {
            restartAudioEngine(reason: reason, recreateEngine: false)
            if !isRecordingActive { scheduleRecoveryRetries(reason: reason) }
        } else {
            isRecordingActive = true
            standbyStoppedNotificationSent = false
        }
    }

    private func scheduleRecoveryRetries(reason: String) {
        recoveryRetryTask?.cancel()
        recoveryRetryTask = Task { [weak self] in
            for (attempt, delay) in [1.0, 3.0, 8.0, 20.0].enumerated() {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                guard UserDefaults.standard.bool(forKey: self.desiredStateKey) else { return }
                guard self.isHoldOn, !self.isRecordingActive else { return }


                if self.interruptionActive && attempt < 2 { continue }
                if self.interruptionActive { self.interruptionActive = false }
                self.restartAudioEngine(reason: "\(reason)-retry\(attempt + 1)", recreateEngine: attempt >= 1)
                if self.isRecordingActive { return }
            }

            guard let self,
                  UserDefaults.standard.bool(forKey: self.desiredStateKey),
                  self.isHoldOn,
                  !self.isRecordingActive,
                  !self.interruptionActive else { return }
            self.markStandbyUnavailableAndNotify(reason: reason)
        }
    }

    func recordAppPhase(_ phase: String) {
        diagnostics.record("appPhase", ["phase": phase])
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                ticks += 1

                if ticks % 6 == 0,
                   self.isHoldOn,
                   UserDefaults.standard.bool(forKey: self.desiredStateKey) {
                    self.refreshStandbyFallbackNotification(reason: "heartbeat")
                }

                if self.isCapturing,
                   let startedAt = self.captureStartedAt,
                   Date().timeIntervalSince(startedAt) >= self.maxCaptureSeconds {
                    self.diagnostics.record("captureAutoCancelledAtLimit", ["limitSeconds": String(Int(self.maxCaptureSeconds))])
                    self.cancelCapture()
                    self.statusText = "순간잡기가 1시간이 되어 저장 없이 자동 중단됐어요."
                }

                let lastAudio = self.snapshotLastAudioCallbackAt()

                if ticks % 6 == 0 {
                    self.diagnostics.recordHeartbeat(
                        lastAudioAt: lastAudio,
                        segmentCount: self.segmentCount,
                        rollingSeconds: self.rollingSeconds
                    )
                }

                guard self.isHoldOn, !self.interruptionActive else { continue }

                if lastAudio == nil {
                    let sinceStart = Date().timeIntervalSince(self.lastEngineStartAt)
                    if sinceStart > 12.0 && Date().timeIntervalSince(self.lastRecoveryAttemptAt) > 30.0 {
                        self.lastRecoveryAttemptAt = Date()
                        self.diagnostics.record("watchdogNoCallbacks")
                        self.restartAudioEngine(reason: "watchdogNoCallbacks", recreateEngine: true)
                    }
                    continue
                }
                let age = Date().timeIntervalSince(lastAudio!)
                guard age > 5.0,
                      Date().timeIntervalSince(self.lastRecoveryAttemptAt) > 30.0 else { continue }

                self.lastRecoveryAttemptAt = Date()
                self.diagnostics.record("watchdogDetectedStall", ["lastAudioAgeSeconds": String(format: "%.2f", age)])
                self.restartAudioEngine(reason: "watchdog", recreateEngine: false)
            }
        }
    }

    private func refreshStandbyFallbackNotification(reason: String) {
        guard UserDefaults.standard.bool(forKey: desiredStateKey), isHoldOn else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [standbyStoppedNotificationID])

        Task {
            let settings = await center.notificationSettings()
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            guard allowed else { return }

            let content = UNMutableNotificationContent()
            // This is a heartbeat fallback, not proof that the microphone has stopped.
            // iOS can delay background Swift tasks even while the audio session remains alive.
            content.title = "HOLD ON 상태를 확인해 주세요."
            content.body = "대기 상태 확인이 잠시 끊겼어요. 앱을 열어 상태를 확인해 주세요."
            content.sound = .default
            content.userInfo = ["holdonAction": "standbyRecovery", "fallback": true]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: standbyHeartbeatGraceSeconds, repeats: false)
            let request = UNNotificationRequest(identifier: standbyStoppedNotificationID, content: content, trigger: trigger)
            do {
                try await center.add(request)
                diagnostics.record("standbyFallbackRefreshed", ["reason": reason])
            } catch {
                diagnostics.record("standbyFallbackRefreshFailed", ["reason": reason, "error": error.localizedDescription])
            }
        }
    }

    private func requestStandbyNotificationPermissionIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                diagnostics.record(allowed ? "standbyNotificationPermissionGranted" : "standbyNotificationPermissionDenied")
            }
        }
    }

    private func markStandbyUnavailableAndNotify(reason: String) {
        guard UserDefaults.standard.bool(forKey: desiredStateKey) else { return }
        recoveryRetryTask?.cancel()
        recoveryRetryTask = nil
        interruptionRecoveryTask?.cancel()
        interruptionRecoveryTask = nil

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        closeCurrentSegment()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isRecordingActive = false
        isHoldOn = false
        diagnostics.record("standbyUnavailable", ["reason": reason])
        statusText = "HOLD ON이 꺼졌어요. 다시 켜면 바로 복구를 시도해요."

        guard !standbyStoppedNotificationSent else { return }
        standbyStoppedNotificationSent = true

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            guard allowed else {
                diagnostics.record("standbyStoppedNotificationUnavailable")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "HOLD ON이 꺼졌어요."
            content.body = "필요한 순간이라면 대기 모드를 다시 켜주세요."
            content.sound = .default
            content.userInfo = ["holdonAction": "standbyRecovery"]
            let request = UNNotificationRequest(identifier: standbyStoppedNotificationID, content: content, trigger: nil)
            do {
                try await center.add(request)
                diagnostics.record("standbyStoppedNotificationSent")
            } catch {
                diagnostics.record("standbyStoppedNotificationFailed", ["error": error.localizedDescription])
            }
        }
    }

    private func restartAudioEngine(reason: String, recreateEngine: Bool) {
        diagnostics.record("recoveryStarted", ["reason": reason])
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        isRecordingActive = false
        closeCurrentSegment()
        if recreateEngine {
            engine = AVAudioEngine()
        }

        do {
            try configureAndStartEngine()
            isRecordingActive = engine.isRunning && tapInstalled
            if isRecordingActive {
                standbyStoppedNotificationSent = false
                refreshStandbyFallbackNotification(reason: "recoverySucceeded")
            }
            diagnostics.record("recoverySucceeded", ["reason": reason])
            statusText = isRecordingActive ? "최근 5분 50초까지 덮어쓰기 중 · 저장은 잡기로 해요." : "오디오 복구를 확인하고 있어요."
        } catch {
            isRecordingActive = false
            diagnostics.record("recoveryFailed", ["reason": reason, "error": error.localizedDescription])
            statusText = "오디오 연결을 다시 시도하고 있어요."
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

enum HoldOnError: LocalizedError {
    case noAudioInput
    case noSegmentsToSave

    var errorDescription: String? {
        switch self {
        case .noAudioInput:
            return "사용 가능한 마이크 입력을 찾지 못했습니다."
        case .noSegmentsToSave:
            return "저장할 오디오 조각이 없습니다."
        }
    }
}

// MARK: - Non-destructive boosted playback

/// Playback-only gain for quiet memories. The saved/original audio is never rewritten.
/// AVAudioUnitEQ provides up to +14 dB for the requested 5× amplitude boost.
@MainActor
final class HoldOnBoostedAudioPlayer {
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let gainUnit = AVAudioUnitEQ(numberOfBands: 0)
    private var file: AVAudioFile?
    private var baseTime: Double = 0

    private(set) var duration: Double = 0
    private(set) var isPlaying: Bool = false

    var gainFactor: Double = 1.0 {
        didSet { applyGain() }
    }

    init() {
        playbackEngine.attach(playerNode)
        playbackEngine.attach(gainUnit)
        playbackEngine.connect(playerNode, to: gainUnit, format: nil)
        playbackEngine.connect(gainUnit, to: playbackEngine.mainMixerNode, format: nil)
        applyGain()
    }

    func load(url: URL) throws {
        playerNode.stop()
        isPlaying = false
        baseTime = 0
        let opened = try AVAudioFile(forReading: url)
        file = opened
        duration = opened.processingFormat.sampleRate > 0
            ? Double(opened.length) / opened.processingFormat.sampleRate
            : 0
    }

    func play(from seconds: Double) throws {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        baseTime = min(max(0, seconds), duration)
        playerNode.stop()
        if !playbackEngine.isRunning {
            playbackEngine.prepare()
            try playbackEngine.start()
        }

        let startFrame = AVAudioFramePosition(baseTime * sampleRate)
        let remaining = max(0, file.length - startFrame)
        guard remaining > 0 else {
            isPlaying = false
            baseTime = duration
            return
        }
        let frameCount = AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max)))
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
        playerNode.play()
        isPlaying = true
    }

    func pause() {
        baseTime = currentTime
        playerNode.stop()
        isPlaying = false
    }

    func stop(resetTime: Bool = true) {
        if !resetTime { baseTime = currentTime }
        playerNode.stop()
        isPlaying = false
        if resetTime { baseTime = 0 }
    }

    func seek(to seconds: Double) throws {
        let target = min(max(0, seconds), duration)
        let resume = isPlaying
        baseTime = target
        playerNode.stop()
        isPlaying = false
        if resume { try play(from: target) }
    }

    var currentTime: Double {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return min(duration, max(0, baseTime)) }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(duration, max(0, baseTime + elapsed))
    }

    private func applyGain() {
        let factor = min(5.0, max(1.0, gainFactor))
        gainUnit.globalGain = Float(20.0 * log10(factor))
    }
}

