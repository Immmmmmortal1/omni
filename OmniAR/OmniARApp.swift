import SwiftUI

// LookDebugBridge 源码直接编译进本 target（OmniAR/DebugBridge/），同模块无需 import。
// 仅 Debug 构建启动本地 HTTP 桥（端口 42671，在 lookdebug-mcp 扫描区间 42671-42770 内）。
// 用模块级单例而非 App.init 内新建：SwiftUI 可能重建 App 结构体，每次 new 会导致
// 第二个实例重复绑定同端口 → POSIX EADDRINUSE。37777 在本机 iOS 26 真机上也触发过同错误。
#if DEBUG
import UIKit

/// 模块级单例（@MainActor 隔离，惰性初始化一次）。
/// 不能放在 App.init 里新建：SwiftUI 可能重建 App 结构体，重复 new 会导致
/// 第二个实例重复绑定同端口 → POSIX EADDRINUSE。
@MainActor
private let lookDebugBridge = LookDebugBridge(port: 42_672) // 42671 被设备占用，用范围内下一个
#endif

@main
struct OmniARApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }

    init() {
        #if DEBUG
        Task { @MainActor in
            lookDebugBridge.startIfNeeded()
        }
        #endif
    }
}
