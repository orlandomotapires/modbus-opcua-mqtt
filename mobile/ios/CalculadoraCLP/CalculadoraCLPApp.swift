import SwiftUI

@main
struct CalculadoraCLPApp: App {
    @StateObject private var mqtt = MQTTService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mqtt)
        }
    }
}
