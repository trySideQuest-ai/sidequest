import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("SideQuest", systemImage: "bell") {
            VStack {
                Text("SideQuest Running")

                Button("Show Test Quest") {
                    appDelegate.showTestQuest()
                }

                Button("Fetch Real Quest") {
                    appDelegate.fetchAndShowQuest()
                }

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
    }
}