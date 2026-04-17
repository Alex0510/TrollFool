//
//  AutoResumeService.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import CocoaLumberjackSwift
import Foundation
import UIKit

final class AutoResumeService: ObservableObject {
    static let shared = AutoResumeService()
    
    private let userDefaults = UserDefaults.standard
    private let enabledPlugInsKey = "AutoResume_EnabledPlugIns"
    private let appVersionsKey = "AutoResume_AppVersions"
    private var isProcessing = false
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidFinishLaunching() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.checkAndResumePlugIns()
        }
    }
    
    @objc private func applicationWillEnterForeground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAndResumePlugIns()
        }
    }
    
    // 保存需要自动启用的插件状态
    func saveEnabledPlugIns(for app: App, enabledURLs: [URL]) {
        var allEnabled = loadAllEnabledPlugIns()
        let enabledPaths = enabledURLs.map { $0.path }
        allEnabled[app.bid] = enabledPaths
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
    }
    
    // 保存单个插件状态
    func savePlugInState(for app: App, plugInURL: URL, isEnabled: Bool) {
        var allEnabled = loadAllEnabledPlugIns()
        var enabledPaths = allEnabled[app.bid] ?? []
        
        let plugInPath = plugInURL.path
        if isEnabled {
            if !enabledPaths.contains(plugInPath) {
                enabledPaths.append(plugInPath)
            }
        } else {
            enabledPaths.removeAll { $0 == plugInPath }
        }
        
        if enabledPaths.isEmpty {
            allEnabled.removeValue(forKey: app.bid)
        } else {
            allEnabled[app.bid] = enabledPaths
        }
        
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
    }
    
    // 移除应用的保存状态
    func removeEnabledPlugIns(for app: App) {
        var allEnabled = loadAllEnabledPlugIns()
        allEnabled.removeValue(forKey: app.bid)
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
    }
    
    // 清除所有保存状态
    func clearAllSavedStates() -> Int {
        let allEnabled = loadAllEnabledPlugIns()
        let count = allEnabled.count
        userDefaults.removeObject(forKey: enabledPlugInsKey)
        userDefaults.removeObject(forKey: appVersionsKey)
        userDefaults.synchronize()
        DDLogInfo("Cleared \(count) saved states from AutoResumeService")
        return count
    }
    
    // 获取保存状态的应用数量
    func getSavedStatesCount() -> Int {
        return loadAllEnabledPlugIns().count
    }
    
    // 获取保存状态的应用列表
    func getSavedStatesList() -> [(bid: String, count: Int)] {
        let allEnabled = loadAllEnabledPlugIns()
        return allEnabled.map { ($0.key, $0.value.count) }.sorted { $0.bid < $1.bid }
    }
    
    // 加载所有保存的插件状态
    private func loadAllEnabledPlugIns() -> [String: [String]] {
        return userDefaults.dictionary(forKey: enabledPlugInsKey) as? [String: [String]] ?? [:]
    }
    
    // 加载保存的应用版本信息
    private func loadAppVersions() -> [String: String] {
        return userDefaults.dictionary(forKey: appVersionsKey) as? [String: String] ?? [:]
    }
    
    // 保存应用版本信息
    private func saveAppVersion(_ app: App, version: String) {
        var versions = loadAppVersions()
        versions[app.bid] = version
        userDefaults.set(versions, forKey: appVersionsKey)
        userDefaults.synchronize()
    }
    
    // 检查并恢复插件
    func checkAndResumePlugIns() {
        guard !isProcessing else { return }
        isProcessing = true
        
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.isProcessing = false
            }
        }
        
        var unsupportedCount = 0
        var unsupportedApps: [App] = []
        let apps = AppListModel.fetchApplications(&unsupportedCount, &unsupportedApps)
        let savedState = loadAllEnabledPlugIns()
        let savedVersions = loadAppVersions()
        
        guard !savedState.isEmpty else { return }
        
        var resumedCount = 0
        var failedApps: [String] = []
        var updatedApps: [String] = []
        
        for app in apps {
            guard let savedPaths = savedState[app.bid] else { continue }
            
            let currentVersion = getAppVersionIdentifier(app)
            let savedVersion = savedVersions[app.bid] ?? ""
            
            // 检查应用是否需要恢复插件
            let needResume = (currentVersion != savedVersion && savedVersion != "")
            
            if needResume {
                updatedApps.append(app.bid)
                let savedURLs = savedPaths.compactMap { URL(fileURLWithPath: $0) }
                let existingURLs = savedURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
                
                if !existingURLs.isEmpty {
                    do {
                        let injector = try InjectorV3(app.url)
                        if injector.appID.isEmpty {
                            injector.appID = app.bid
                        }
                        if injector.teamID.isEmpty {
                            injector.teamID = app.teamID
                        }
                        
                        try injector.inject(existingURLs, shouldPersist: false)
                        resumedCount += existingURLs.count
                        DDLogInfo("Auto resumed \(existingURLs.count) plugins for \(app.bid)")
                    } catch {
                        DDLogError("Auto resume failed for \(app.bid): \(error)")
                        failedApps.append(app.bid)
                    }
                }
            }
            
            // 更新保存的版本信息
            if currentVersion != savedVersion {
                saveAppVersion(app, version: currentVersion)
            }
        }
        
        if resumedCount > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("AutoResumeCompleted"),
                    object: nil,
                    userInfo: [
                        "count": resumedCount,
                        "failedApps": failedApps,
                        "updatedApps": updatedApps
                    ]
                )
            }
        }
    }
    
    // 获取应用的版本标识符（使用构建号，因为应用更新时构建号会变）
    private func getAppVersionIdentifier(_ app: App) -> String {
        let infoPlistPath = app.url.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: infoPlistPath) as? [String: Any] else {
            return "0"
        }
        let version = dict["CFBundleShortVersionString"] as? String ?? "0"
        let build = dict["CFBundleVersion"] as? String ?? "0"
        return "\(version)_\(build)"
    }
    
    // 手动触发检查
    func forceCheck() {
        checkAndResumePlugIns()
    }
}
