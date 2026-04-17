//
//  TrollFoolsApp.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import SwiftUI

@main
struct TrollFoolsApp: SwiftUI.App {

    @AppStorage("isDisclaimerHiddenV2")
    var isDisclaimerHidden: Bool = false

    init() {
        try? FileManager.default.removeItem(at: InjectorV3.temporaryRoot)
       
        if #available(iOS 13.0, *) {
            BackgroundTaskService.shared.registerBackgroundTask()
            BackgroundTaskService.shared.scheduleAppRefresh()
        }
        // 启动后台自动注入监控服务
        AutoInjectService.shared.startMonitoring()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isDisclaimerHidden {
                    AppListView()
                        .environmentObject(AppListModel())
                        .transition(.opacity)
                } else {
                    DisclaimerView(isDisclaimerHidden: $isDisclaimerHidden)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: isDisclaimerHidden)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoInjectCompleted"))) { _ in
                // 注入完成后刷新视图
                NotificationCenter.default.post(name: NSNotification.Name("com.apple.LaunchServices.ApplicationsChanged"), object: nil)
            }
        }
    }
}