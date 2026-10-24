import SwiftUI

@main
struct EAgent2App: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var bridge = WebBridge()
    @StateObject private var gate = SecurityGate()
    @StateObject private var log = AgentLogStore()
    @StateObject private var engine: AgentEngine

    init() {
        let settings = AppSettings()
        let bridge = WebBridge()
        let gate = SecurityGate()
        let log = AgentLogStore()
        _settings = StateObject(wrappedValue: settings)
        _bridge = StateObject(wrappedValue: bridge)
        _gate = StateObject(wrappedValue: gate)
        _log = StateObject(wrappedValue: log)
        _engine = StateObject(wrappedValue: AgentEngine(bridge: bridge, gate: gate, log: log, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(bridge)
                .environmentObject(gate)
                .environmentObject(log)
                .environmentObject(engine)
        }
    }
}
