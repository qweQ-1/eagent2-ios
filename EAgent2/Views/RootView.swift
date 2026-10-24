import SwiftUI

struct RootView: View {
    @EnvironmentObject var gate: SecurityGate
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ChatTabView()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            LogTabView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .tag(1)
            SettingsTabView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        // 安全门（对应 PC 版「窗口_安全警告」）
        .sheet(isPresented: Binding(
            get: { gate.pending != nil },
            set: { if !$0 { gate.resolve(.skip) } }
        )) {
            if let req = gate.pending {
                SecuritySheet(request: req)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppSettings())
        .environmentObject(WebBridge())
        .environmentObject(SecurityGate())
        .environmentObject(AgentLogStore())
        .environmentObject(AgentEngine(bridge: WebBridge(), gate: SecurityGate(), log: AgentLogStore(), settings: AppSettings()))
}
