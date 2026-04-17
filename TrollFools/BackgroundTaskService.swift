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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            DDLogInfo("Background refresh scheduled")
        } catch {
            DDLogError("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleAppRefresh()
            }
            task.setTaskCompleted(success: false)
        }
        
        DispatchQueue.global(qos: .background).async {
            AutoInjectService.shared.checkAndAutoInjectAll()
            
            DispatchQueue.main.async {
                self.scheduleAppRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }
}