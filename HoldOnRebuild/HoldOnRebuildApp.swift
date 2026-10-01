import SwiftUI
import UserNotifications

final class HoldOnNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = HoldOnNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["holdonAction"] as? String == "routineOn" {
            Task { @MainActor in
                HoldOnRuntime.shared.engine.handleRoutineOnNotificationTap()
            }
        }
        completionHandler()
    }
}


@main
@MainActor
struct HoldOnRebuildApp: App {
    @StateObject private var engine = HoldOnRuntime.shared.engine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = HoldOnNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .onAppear { HoldOnFontManager.shared.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.recordAppPhase("active")
                engine.recoverIfNeeded(reason: "foreground")
                engine.evaluateRoutine()
            case .inactive:
                engine.recordAppPhase("inactive")
            case .background:
                engine.recordAppPhase("background")
            @unknown default:
                engine.recordAppPhase("unknown")
            }
        }
    }
}
