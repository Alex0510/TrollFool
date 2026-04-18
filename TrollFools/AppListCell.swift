//
//  AppListCell.swift
//  TrollFool
//
//  Created by 82Flex on 2024/10/30.
//

import CocoaLumberjackSwift
import SwiftUI
import LocalAuthentication

struct AppListCell: View {
    @EnvironmentObject var appList: AppListModel

    @StateObject var app: App

    @State private var isCleaningData = false
    @State private var cleanResultMessage: String?

    @available(iOS 15, *)
    var highlightedName: AttributedString {
        let name = app.name
        var attributedString = AttributedString(name)
        if let range = attributedString.range(of: appList.filter.searchKeyword, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributedString[range].foregroundColor = .accentColor
        }
        return attributedString
    }

    @available(iOS 15, *)
    var highlightedId: AttributedString {
        let bid = app.bid
        var attributedString = AttributedString(bid)
        if let range = attributedString.range(of: appList.filter.searchKeyword, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributedString[range].foregroundColor = .accentColor
        }
        return attributedString
    }

    var body: some View {
        HStack(spacing: 12) {
            if #available(iOS 15, *) {
                Image(uiImage: app.alternateIcon ?? app.icon ?? UIImage())
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(uiImage: app.alternateIcon ?? app.icon ?? UIImage())
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if #available(iOS 15, *) {
                        Text(highlightedName)
                            .font(.headline)
                            .lineLimit(1)
                    } else {
                        Text(app.name)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if app.isInjected || app.hasPersistedAssets {
                        Image(systemName: app.isInjected ? "bandage" : "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .accessibilityLabel(app.isInjected ? NSLocalizedString("Patched", comment: "") : NSLocalizedString("Includes Disabled PlugIns", comment: ""))
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut, value: combines(
                    app.isInjected,
                    app.hasPersistedAssets
                ))

                if #available(iOS 15, *) {
                    Text(highlightedId)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text(app.bid)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let version = app.version {
                if app.isUser && app.isDetached {
                    HStack(spacing: 4) {
                        Image(systemName: "lock")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .accessibilityLabel(NSLocalizedString("Pinned Version", comment: ""))

                        Text(version)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(version)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contextMenu {
            if !appList.isSelectorMode {
                cellContextMenuWrapper
            }
        }
        .background(cellBackground)
        .alert(isPresented: .constant(cleanResultMessage != nil)) {
            Alert(
                title: Text("清理数据"),
                message: Text(cleanResultMessage ?? ""),
                dismissButton: .default(Text("确定")) {
                    cleanResultMessage = nil
                }
            )
        }
    }

    @ViewBuilder
    var cellContextMenu: some View {
        Button {
            launch()
        } label: {
            Label(NSLocalizedString("Launch", comment: ""), systemImage: "command")
        }

        if AppListModel.hasTrollStore && app.isAllowedToAttachOrDetach {
            if app.isDetached {
                Button {
                    do {
                        try InjectorV3(app.url).setMetadataDetached(false)
                        app.reload()
                        appList.isRebuildNeeded = true
                    } catch { DDLogError("\(error)", ddlog: InjectorV3.main.logger) }
                } label: {
                    Label(NSLocalizedString("Unlock Version", comment: ""), systemImage: "lock.open")
                }
            } else {
                Button {
                    do {
                        try InjectorV3(app.url).setMetadataDetached(true)
                        app.reload()
                        appList.isRebuildNeeded = true
                    } catch { DDLogError("\(error)", ddlog: InjectorV3.main.logger) }
                } label: {
                    Label(NSLocalizedString("Lock Version", comment: ""), systemImage: "lock")
                }
            }
        }

        Button {
            openInFilza(app.url)
        } label: {
            if isFilzaInstalled {
                Label("应用目录", systemImage: "scope")
            } else {
                Label("应用目录 (Filza未安装)", systemImage: "xmark.octagon")
            }
        }
        .disabled(!isFilzaInstalled)

        if let dataURL = app.dataContainerURL {
            Button {
                openInFilza(dataURL)
            } label: {
                Label("数据目录", systemImage: "folder")
            }
        }

        if let groupURL = app.appGroupContainerURL {
            Button {
                openInFilza(groupURL)
            } label: {
                Label("应用组目录", systemImage: "folder.badge.gear")
            }
        }

        if app.dataContainerURL != nil || app.appGroupContainerURL != nil {
            if #available(iOS 15, *) {
                Button(role: .destructive) {
                    confirmCleanData()
                } label: {
                    Label("彻底清理 (数据+Keychain)", systemImage: "trash.slash")
                }
            } else {
                Button {
                    confirmCleanData()
                } label: {
                    Label("彻底清理 (数据+Keychain)", systemImage: "trash.slash")
                }
            }
        }
    }

    @ViewBuilder
    var cellContextMenuWrapper: some View {
        if #available(iOS 16, *) {
            cellContextMenu
        } else {
            if #available(iOS 15, *) { }
            else {
                cellContextMenu
            }
        }
    }

    @ViewBuilder
    var cellBackground: some View {
        if #available(iOS 15, *) {
            if #available(iOS 16, *) { }
            else {
                Color.clear
                    .contextMenu {
                        if !appList.isSelectorMode {
                            cellContextMenu
                        }
                    }
                    .id(app.isDetached)
            }
        }
    }

    private func launch() {
        LSApplicationWorkspace.default().openApplication(withBundleID: app.bid)
    }

    var isFilzaInstalled: Bool { appList.isFilzaInstalled }

    private func openInFilza(_ url: URL) {
        appList.openInFilza(url)
    }

    // 确认清理弹窗
    private func confirmCleanData() {
        let alert = UIAlertController(
            title: "彻底清理",
            message: "此操作将永久删除应用「\(app.name)」的以下数据：\n• 数据目录\n• 应用组目录\n• Keychain 中的所有条目\n\n此操作不可逆，确定要继续吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认清理", style: .destructive) { _ in
            performFullClean()
        })

        if let viewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }

    // 执行彻底清理
    private func performFullClean() {
        isCleaningData = true
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errorMessages: [String] = []
            let fileManager = FileManager.default

            // 1. 清理数据目录（绝对路径）
            if let dataURL = app.dataContainerURL {
                let dataPath = dataURL.path
                DDLogDebug("Data container path: \(dataPath)")
                if fileManager.fileExists(atPath: dataPath) {
                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: dataPath)
                        for item in contents {
                            let itemURL = URL(fileURLWithPath: dataPath).appendingPathComponent(item)
                            try fileManager.removeItem(at: itemURL)
                        }
                        DDLogInfo("Cleaned data directory for \(app.bid)")
                    } catch {
                        success = false
                        errorMessages.append("数据目录清理失败: \(error.localizedDescription)")
                        DDLogError("Failed to clean data directory: \(error)")
                    }
                } else {
                    success = false
                    errorMessages.append("数据目录不存在: \(dataPath)")
                    DDLogError("Data directory does not exist: \(dataPath)")
                }
            } else {
                DDLogWarn("No data container URL for \(app.bid)")
            }

            // 2. 清理应用组目录（绝对路径）
            if let groupURL = app.appGroupContainerURL {
                let groupPath = groupURL.path
                DDLogDebug("App group container path: \(groupPath)")
                if fileManager.fileExists(atPath: groupPath) {
                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: groupPath)
                        for item in contents {
                            let itemURL = URL(fileURLWithPath: groupPath).appendingPathComponent(item)
                            try fileManager.removeItem(at: itemURL)
                        }
                        DDLogInfo("Cleaned app group directory for \(app.bid)")
                    } catch {
                        success = false
                        errorMessages.append("应用组目录清理失败: \(error.localizedDescription)")
                        DDLogError("Failed to clean app group directory: \(error)")
                    }
                } else {
                    success = false
                    errorMessages.append("应用组目录不存在: \(groupPath)")
                    DDLogError("App group directory does not exist: \(groupPath)")
                }
            } else {
                DDLogWarn("No app group container URL for \(app.bid)")
            }

            // 3. 清理 Keychain（使用 Security API）
            let keychainCleared = clearKeychainUsingSecurityAPI(bundleID: app.bid, teamID: app.teamID)
            if !keychainCleared {
                success = false
                errorMessages.append("Keychain 清理失败")
            } else {
                DDLogInfo("Cleaned keychain for \(app.bid)")
            }

            DispatchQueue.main.async {
                isCleaningData = false
                if success {
                    cleanResultMessage = "清理完成！\n已删除数据目录、应用组目录及 Keychain 数据。"
                    // 刷新应用状态
                    app.reload()
                } else {
                    cleanResultMessage = "清理部分失败：\n" + errorMessages.joined(separator: "\n")
                }
            }
        }
    }

    // 使用 Security API 删除属于该应用的 Keychain 条目
    private func clearKeychainUsingSecurityAPI(bundleID: String, teamID: String) -> Bool {
        // 方法：遍历所有 Keychain 类，删除匹配 access group 的条目
        let secClasses: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        
        var success = false
        for secClass in secClasses {
            // 查询所有条目
            let query: [CFString: Any] = [
                kSecClass: secClass,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecReturnAttributes: true,
                kSecReturnData: false
            ]
            
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let items = result as? [[CFString: Any]] {
                for item in items {
                    // 获取 access group
                    if let accessGroup = item[kSecAttrAccessGroup] as? String {
                        // 检查是否属于目标应用（access group 包含 bundleID 或 teamID）
                        if accessGroup.contains(bundleID) || accessGroup.contains(teamID) {
                            // 构建删除查询
                            var deleteQuery: [CFString: Any] = [kSecClass: secClass]
                            // 复制其他唯一标识属性
                            if let account = item[kSecAttrAccount] as? String {
                                deleteQuery[kSecAttrAccount] = account
                            }
                            if let service = item[kSecAttrService] as? String {
                                deleteQuery[kSecAttrService] = service
                            }
                            if let generic = item[kSecAttrGeneric] as? Data {
                                deleteQuery[kSecAttrGeneric] = generic
                            }
                            // 执行删除
                            let delStatus = SecItemDelete(deleteQuery as CFDictionary)
                            if delStatus == errSecSuccess {
                                success = true
                                DDLogDebug("Deleted keychain item for \(bundleID): \(accessGroup)")
                            } else {
                                DDLogDebug("Failed to delete keychain item: \(delStatus)")
                            }
                        }
                    }
                }
            } else if status != errSecItemNotFound {
                DDLogError("Failed to query keychain class \(secClass): \(status)")
            }
        }
        return success
    }
}