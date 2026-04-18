import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appDelegate: appDelegate)
        } label: {
            Image(systemName: "bell")
                .help("SideQuest — Quest notifications")
        }
        .menuBarExtraStyle(.menu)
    }
}
