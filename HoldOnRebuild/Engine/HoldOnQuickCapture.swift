import Foundation

extension Notification.Name {
    static let holdOnQuickCaptureChanged = Notification.Name("holdon.quickCapture.changed")
}

@MainActor
enum HoldOnQuickCaptureResult: Int, Sendable {
    case failed = 0
    case startedWithHistory = 1
    case saved = 2
    case startedFromNow = 3
}

@MainActor
enum HoldOnQuickCaptureSource: Sendable {
    case inApp
    case externalQuickControl
}

@MainActor
enum HoldOnQuickCapture {
    private static let suppressNextCameraKey = "holdon.quickCapture.suppressNextCameraPrompt.v110"

    static func perform(
        engine: AudioHoldEngine,
        source: HoldOnQuickCaptureSource
    ) async -> HoldOnQuickCaptureResult {
        // Second press = save exactly once. No camera flow for external quick execution.
        if engine.isCapturing {
            let beforeCount = engine.savedMoments.count

            // Set suppression BEFORE finishCapture publishes lastSavedMomentID.
            // This removes the race where HomeView could show the camera prompt first.
            if source == .externalQuickControl {
                UserDefaults.standard.set(true, forKey: suppressNextCameraKey)
            }

            engine.finishCapture()
            let didSave = engine.savedMoments.count > beforeCount

            if !didSave, source == .externalQuickControl {
                UserDefaults.standard.removeObject(forKey: suppressNextCameraKey)
            }

            NotificationCenter.default.post(
                name: .holdOnQuickCaptureChanged,
                object: nil,
                userInfo: [
                    "saved": didSave,
                    "external": source == .externalQuickControl
                ]
            )
            return didSave ? .saved : .failed
        }

        // First press = ensure HOLD ON is ON, and KEEP it ON until the user explicitly turns it off.
        let hadRollingHistory = engine.isHoldOn && engine.isRecordingActive
        if !hadRollingHistory {
            do {
                try await engine.startHoldOn(persistIntent: true)
            } catch {
                return .failed
            }
        }

        guard engine.isHoldOn, engine.isRecordingActive else {
            return .failed
        }

        let preferredPre = min(350, max(0, engine.selectedPreSeconds))
        let effectivePre = hadRollingHistory ? preferredPre : 0
        engine.beginCapture(preSeconds: effectivePre)

        NotificationCenter.default.post(
            name: .holdOnQuickCaptureChanged,
            object: nil,
            userInfo: [
                "saved": false,
                "external": source == .externalQuickControl
            ]
        )

        return hadRollingHistory ? .startedWithHistory : .startedFromNow
    }

    static func consumeCameraPromptSuppression() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: suppressNextCameraKey) else { return false }
        defaults.removeObject(forKey: suppressNextCameraKey)
        return true
    }
}
