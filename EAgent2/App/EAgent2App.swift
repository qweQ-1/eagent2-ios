import SwiftUI
import UIKit

@main
struct EAgent2App: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var bridge = WebBridge()
    @StateObject private var gate = SecurityGate()
    @StateObject private var log = AgentLogStore()
    @StateObject private var engine: AgentEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 崩溃取证 + 内存告警降载（必须在最早期安装）
        CrashGuard.install()
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
                .onReceive(NotificationCenter.default.publisher(for: CrashGuard.memoryWarning)) { _ in
                    // 内存告警：立刻让网页降载，避免 WebContent 进程被系统杀掉
                    bridge.handleMemoryWarning()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 进入后台属于正常收尾（不算闪退）
            if phase == .background { CrashGuard.markCleanExit() }
        }
    }
}
