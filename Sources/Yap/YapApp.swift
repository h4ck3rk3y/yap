import SwiftUI

@main
struct YapApp: App {
    @StateObject private var engine = YapEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
