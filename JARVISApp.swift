import SwiftUI

@main
struct JARVISApp: App {
    @StateObject private var callManager = CallManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(callManager)
                .preferredColorScheme(.dark)
        }
    }
}

