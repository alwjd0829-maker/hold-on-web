import AppIntents
import ActivityKit
import Foundation
import WidgetKit

struct HoldOnCaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var active: Bool
    }
    var startedAt: Date
}

enum HoldOnControlVisualState: String, Codable, Sendable {
    case idle
    case capturing
    case saved
    case failed
}

enum HoldOnControlStateStore {
    static let appGroupID = "group.com.soso.holdon"
    private static let stateKey = "holdon.control.visualState.v113"

    static func state() -> HoldOnControlVisualState {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return .idle }
        return HoldOnControlVisualState(rawValue: defaults.string(forKey: stateKey) ?? "") ?? .idle
    }

    static func set(_ state: HoldOnControlVisualState) {
        UserDefaults(suiteName: appGroupID)?.set(state.rawValue, forKey: stateKey)
    }
}

#if !CONTROL_EXTENSION
@MainActor
enum HoldOnCaptureActivity {
    static func startIfNeeded() -> Bool {
        if !Activity<HoldOnCaptureActivityAttributes>.activities.isEmpty {
            return true
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        let attributes = HoldOnCaptureActivityAttributes(startedAt: Date())
        let content = ActivityContent(
            state: HoldOnCaptureActivityAttributes.ContentState(active: true),
            staleDate: nil
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            return true
        } catch {
            return false
        }
    }

    static func endAll() async {
        let content = ActivityContent(
            state: HoldOnCaptureActivityAttributes.ContentState(active: false),
            staleDate: nil
        )
        for activity in Activity<HoldOnCaptureActivityAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
#endif

@available(iOS 26.0, *)
struct HoldOnControlIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "HOLD ON 순간 잡기"
    static var description = IntentDescription("한 번 누르면 잡고, 다시 누르면 바로 저장합니다.")
    static var openAppWhenRun: Bool = false
    // Lock Screen controls are the primary capture path. Make the default explicit so
    // the control never asks for Face ID/device unlock merely to run this intent.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var supportedModes: IntentModes { .background }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if CONTROL_EXTENSION
        // LiveActivityIntent causes the system to launch the host app process.
        // The extension copy intentionally owns no audio engine and no duplicate state machine.
        return .result()
        #else
        let engine = HoldOnRuntime.shared.engine
        let saving = engine.isCapturing

        if saving {
            // Second press: show check immediately, save exactly once, then return to idle quickly.
            HoldOnControlStateStore.set(.saved)
            ControlCenter.shared.reloadControls(ofKind: HoldOnCaptureControlKind.value)

            let result = await HoldOnQuickCapture.perform(
                engine: engine,
                source: .externalQuickControl
            )

            // HOLD ON keeps recording after the memory is saved, so its Live Activity must stay active.
            switch result {
            case .saved:
                try? await Task.sleep(for: .milliseconds(20))
                HoldOnControlStateStore.set(.idle)
            default:
                HoldOnControlStateStore.set(.failed)
                try? await Task.sleep(for: .milliseconds(350))
                HoldOnControlStateStore.set(.idle)
            }
            ControlCenter.shared.reloadControls(ofKind: HoldOnCaptureControlKind.value)
            return .result()
        }

        // First press: start the audio path first. On the Lock Screen, requesting ActivityKit
        // before the AudioRecordingIntent has established its recording session can race the
        // host-process launch. Keep the two operations sequential and fail closed.
        HoldOnControlStateStore.set(.capturing)
        ControlCenter.shared.reloadControls(ofKind: HoldOnCaptureControlKind.value)

        let result = await HoldOnQuickCapture.perform(
            engine: engine,
            source: .externalQuickControl
        )

        switch result {
        case .startedWithHistory, .startedFromNow:
            // AudioRecordingIntent requires a Live Activity while recording. Request it here,
            // but don't overwrite a successful capture with the red failure state if ActivityKit
            // reports a transient visibility/launch race; the next host pass can reconcile it.
            _ = HoldOnCaptureActivity.startIfNeeded()
            HoldOnControlStateStore.set(.capturing)
        case .saved:
            HoldOnControlStateStore.set(.saved)
        case .failed:
            await HoldOnCaptureActivity.endAll()
            HoldOnControlStateStore.set(.failed)
        }
        ControlCenter.shared.reloadControls(ofKind: HoldOnCaptureControlKind.value)
        return .result()
        #endif
    }
}

enum HoldOnCaptureControlKind {
    static let value = "com.soso.holdon.control.capture"
}
