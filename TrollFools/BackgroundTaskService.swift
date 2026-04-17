// BackgroundTaskService.swift
//
//  BackgroundTaskService.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import BackgroundTasks
import CocoaLumberjackSwift
import Foundation

@available(iOS 13.0, *)
final class BackgroundTaskService: ObservableObject {
    static let shared = BackgroundTaskService()
    
    private let refreshTaskIdentifier = "com.82flex.TrollFools.refresh"
    
    private init() {}
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { [weak self] task in
            self?.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        DDLogInfo("BackgroundTaskService registered")
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15分钟后
        
        do {
            try BGTaskScheduler.shared.submit(request)
            DDLogInfo("Background refresh scheduled")
        } catch {
            DDLogError("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // 设置过期处理
        task.expirationHandler = { [weak self] in
            self?.scheduleAppRefresh()
            task.setTaskCompleted(success: false)
        }
        
        // 执行后台检查
        DispatchQueue.global(qos: .background).async {
            AutoInjectService.shared.checkAndAutoInjectAll()
            
            DispatchQueue.main.async {
                // 重新调度下一次刷新
                self.scheduleAppRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }
}