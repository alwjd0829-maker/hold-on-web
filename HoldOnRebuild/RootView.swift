import SwiftUI

struct RootView: View {
    @State private var tab: RootTab = .home
    @AppStorage("holdon.tutorial.completed.v2") private var tutorialCompleted = false
    @State private var showTutorial = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView()
                case .memories: MemoriesView()
                case .settings: SettingsView()
                }
            }
            FloatingTabBar(selection: $tab)
        }
        .onAppear { showTutorial = !tutorialCompleted }
        .sheet(isPresented: $showTutorial) {
            HoldOnTutorialView {
                tutorialCompleted = true
                showTutorial = false
            }
            .interactiveDismissDisabled()
        }
    }
}
