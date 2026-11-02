import SwiftUI

@main
struct ThreeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Three")
                .padding(40)
                .glassEffect()
        }
        MenuBarExtra("Three", systemImage: "timer") {
            Text("Three")
        }
    }
}
