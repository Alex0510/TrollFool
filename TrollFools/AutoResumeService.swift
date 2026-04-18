//
//  AutoResumeService.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import CocoaLumberjackSwift
import Foundation
import UIKit

struct SavedAppState: Identifiable {
    let id: String
    let bid: String
    let appName: String
    let pluginNames: [String]
    let pluginPaths: [String]
}

final class AutoResumeService: ObservableObject {
    static let shared = AutoResumeService()
    
    private let userDefaults = UserDefaults.standard
    private let enabledPlugInsKey = "AutoResume_EnabledPlugIns"
    private let appVersionsKey = "AutoResume_AppVersions"
    private var isProcessing = false
    private var pendingRetry: [String: Int] = [:]  // 记录跳过注入的应用及重试次数
    
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
        // 启动后立即检查（延迟 0.5 秒确保 UI 就绪）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAndResumePlugIns(ignoreForegroundCheck: false)
        }
    }
    
    @objc private func applicationWillEnterForeground() {
        // 从后台进入前台时立即检查
        DispatchQueue.main.async {
            self.checkAndResumePlugIns(ignoreForegroundCheck: false)
        }
    }
    
    // 手动触发检查（用于高级设置中的按钮）
    func forceCheck() {
        checkAndResumePlugIns(ignoreForegroundCheck: true)
    }
    
    // 核心检查方法
    private func checkAndResumePlugIns(ignoreForegroundCheck: Bool = false) {
        guard !isProcessing else { return }
        isProcessing = true
        
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
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
        var skippedApps: [String] = []
        
        for app in apps {
            guard let savedPaths = savedState[app.bid] else { continue }
            
            let currentVersion = getAppVersionIdentifier(app)
            let savedVersion = savedVersions[app.bid] ?? ""
            
            let needResume = (currentVersion != savedVersion && savedVersion != "")
            
            if needResume {
                // 检查目标应用是否在前台（避免杀死正在使用的应用）
                if !ignoreForegroundCheck && isAppInForeground(bundleID: app.bid) {
                    DDLogWarn("应用 \(app.bid) 正在前台运行，跳过自动注入以避免杀死进程")
                    skippedApps.append(app.bid)
                    // 记录重试次数，稍后重试
                    pendingRetry[app.bid] = (pendingRetry[app.bid] ?? 0) + 1
                    if pendingRetry[app.bid]! <= 3 {
                        // 延迟 10 秒后重试
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                            self?.checkAndResumePlugIns(ignoreForegroundCheck: false)
                        }
                    }
                    continue
                }
                
                // 清除重试计数
                pendingRetry.removeValue(forKey: app.bid)
                
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
                        
                        // 关键：使用 shouldPersist: false 只注入不持久化，避免不必要的杀进程
                        // 注意：inject 方法内部可能仍然会杀进程，但至少我们不在前台应用时执行
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
                        "skippedApps": skippedApps
                    ]
                )
            }
        }
        
        if !skippedApps.isEmpty {
            DDLogInfo("跳过了 \(skippedApps.count) 个应用（前台运行），稍后将重试")
        }
    }
    
    // 检查指定 Bundle ID 的应用是否在前台
    private func isAppInForeground(bundleID: String) -> Bool {
        guard let frontmostApp = UIApplication.shared.frontMostAppBundleID() else {
            return false
        }
        return frontmostApp == bundleID
    }
    
    // 获取应用的版本标识符
    private func getAppVersionIdentifier(_ app: App) -> String {
        let infoPlistPath = app.url.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: infoPlistPath) as? [String: Any] else {
            return "0"
        }
        let version = dict["CFBundleShortVersionString"] as? String ?? "0"
        let build = dict["CFBundleVersion"] as? String ?? "0"
        return "\(version)_\(build)"
    }
    
    // 保存应用版本信息
    private func saveAppVersion(_ app: App, version: String) {
        var versions = loadAppVersions()
        versions[app.bid] = version
        userDefaults.set(versions, forKey: appVersionsKey)
        userDefaults.synchronize()
    }
    
    // 加载保存的版本信息
    private func loadAppVersions() -> [String: String] {
        return userDefaults.dictionary(forKey: appVersionsKey) as? [String: String] ?? [:]
    }
    
    // 加载保存的插件状态
    private func loadAllEnabledPlugIns() -> [String: [String]] {
        return userDefaults.dictionary(forKey: enabledPlugInsKey) as? [String: [String]] ?? [:]
    }
    
    // 保存插件状态（原有方法保持不变）
    func saveEnabledPlugIns(for app: App, enabledURLs: [URL]) {
        var allEnabled = loadAllEnabledPlugIns()
        let enabledPaths = enabledURLs.map { $0.path }
        allEnabled[app.bid] = enabledPaths
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("AutoResumeStateChanged"), object: nil)
        }
    }
    
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
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("AutoResumeStateChanged"), object: nil)
        }
    }
    
    func removeEnabledPlugIns(for app: App) {
        var allEnabled = loadAllEnabledPlugIns()
        allEnabled.removeValue(forKey: app.bid)
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("AutoResumeStateChanged"), object: nil)
        }
    }
    
    func clearAllSavedStates() -> Int {
        let allEnabled = loadAllEnabledPlugIns()
        let count = allEnabled.count
        userDefaults.removeObject(forKey: enabledPlugInsKey)
        userDefaults.removeObject(forKey: appVersionsKey)
        userDefaults.synchronize()
        DDLogInfo("Cleared \(count) saved states from AutoResumeService")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("AutoResumeStateChanged"), object: nil)
        }
        return count
    }
    
    func getSavedStatesCount() -> Int {
        return loadAllEnabledPlugIns().count
    }
    
    func getSavedStatesList() -> [(bid: String, count: Int)] {
        let allEnabled = loadAllEnabledPlugIns()
        return allEnabled.map { ($0.key, $0.value.count) }.sorted { $0.bid < $1.bid }
    }
    
    func getSavedStatesDetail() -> [SavedAppState] {
        let allEnabled = loadAllEnabledPlugIns()
        var states: [SavedAppState] = []
        for (bid, paths) in allEnabled {
            let appName = getAppName(for: bid) ?? bid
            let pluginNames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            states.append(SavedAppState(
                id: bid,
                bid: bid,
                appName: appName,
                pluginNames: pluginNames,
                pluginPaths: paths
            ))
        }
        return states.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
    
    func removeSavedState(for bid: String) {
        var allEnabled = loadAllEnabledPlugIns()
        allEnabled.removeValue(forKey: bid)
        userDefaults.set(allEnabled, forKey: enabledPlugInsKey)
        userDefaults.synchronize()
        var versions = loadAppVersions()
        versions.removeValue(forKey: bid)
        userDefaults.set(versions, forKey: appVersionsKey)
        userDefaults.synchronize()
        DDLogInfo("Removed saved state for \(bid)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("AutoResumeStateChanged"), object: nil)
        }
    }
    
    private func getAppName(for bid: String) -> String? {
        guard let apps = LSApplicationWorkspace.default().allApplications() else { return nil }
        for proxy in apps {
            if proxy.applicationIdentifier() == bid {
                return proxy.localizedName()
            }
        }
        return nil
    }
}

// MARK: - UIApplication 扩展，获取前台应用 Bundle ID
extension UIApplication {
    func frontMostAppBundleID() -> String? {
        if let frontmostApp = self.value(forKey: "frontMostApp") as? NSObject,
           let bundleID = frontmostApp.value(forKey: "bundleIdentifier") as? String {
            return bundleID
        }
        return nil
    }
}