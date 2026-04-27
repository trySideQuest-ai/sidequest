import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appDelegate: appDelegate)
        } label: {
            Image("menubar-icon")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .help("SideQuest — Quest notifications")
        }
        .menuBarExtraStyle(.menu)
    }
}
