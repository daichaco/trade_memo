import SwiftUI

/// タブの骨組み。各画面はマイルストーン2以降で実装する。
struct ContentView: View {
    var body: some View {
        TabView {
            placeholder("新規トレード計画")
                .tabItem { Label("計画", systemImage: "square.and.pencil") }
            placeholder("保有中")
                .tabItem { Label("保有", systemImage: "briefcase") }
            placeholder("振り返り")
                .tabItem { Label("振り返り", systemImage: "chart.bar") }
            placeholder("設定")
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }

    private func placeholder(_ title: String) -> some View {
        NavigationStack {
            Text("準備中")
                .foregroundStyle(.secondary)
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}
