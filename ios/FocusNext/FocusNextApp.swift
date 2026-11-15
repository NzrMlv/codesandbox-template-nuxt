import SwiftUI

@main
struct FocusNextApp: App {
    @StateObject private var store = CalendarStore()
    @StateObject private var session = FocusSession()

    var body: some Scene {
        WindowGroup {
            FocusScreen()
                .environmentObject(store)
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
