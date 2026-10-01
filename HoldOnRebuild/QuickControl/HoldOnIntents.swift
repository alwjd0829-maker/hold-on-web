import AppIntents

@MainActor
final class HoldOnRuntime {
    static let shared = HoldOnRuntime()
    let engine = AudioHoldEngine()
    private init() {}
}

struct HoldOnCaptureShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "HOLD ON 순간 잡기"
    static var description = IntentDescription("한 번 누르면 잡고, 다시 누르면 바로 저장합니다.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await HoldOnQuickCapture.perform(
            engine: HoldOnRuntime.shared.engine,
            source: .externalQuickControl
        )
        return .result()
    }
}

struct HoldOnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HoldOnCaptureShortcutIntent(),
            phrases: ["\(.applicationName) 순간 잡기"],
            shortTitle: "순간 잡기",
            systemImageName: "waveform"
        )
    }
}
