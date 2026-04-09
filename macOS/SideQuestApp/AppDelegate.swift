import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var apiClient: APIClient?
    var windowManager: WindowManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app as background-only (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Initialize API client with hardcoded values for now
        // (will be replaced with user auth flow in Phase 2)
        let apiBase = "https://bd5x085yt3.execute-api.us-east-1.amazonaws.com"
        let testToken = "0000000000000000000000000000000000000000000000000000000000000000"  // Placeholder 64-char token

        apiClient = APIClient(apiBaseURL: apiBase, bearerToken: testToken)

        // Initialize WindowManager
        windowManager = WindowManager()
        windowManager?.setAPIClient(apiClient!)

        print("SideQuest app launched with WindowManager")
    }
}

extension AppDelegate {
    func showTestQuest() {
        let testQuest = QuestData(
            quest_id: "test-123",
            display_text: "Test Quest: Explore New Features",
            tracking_url: "https://example.com",
            reward_amount: 250,
            brand_name: "Test Corp",
            category: "DevTool"
        )
        windowManager?.showQuest(testQuest)
    }

    func fetchAndShowQuest() {
        guard let apiClient = apiClient else { return }
        Task {
            do {
                let quest = try await apiClient.fetchQuest()
                await MainActor.run {
                    windowManager?.showQuest(quest)
                }
            } catch {
                // Silent failure — quest simply won't display
            }
        }
    }
}