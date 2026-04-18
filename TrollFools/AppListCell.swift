//
//  AppListCell.swift
//  TrollFool
//
//  Created by 82Flex on 2024/10/30.
//

import CocoaLumberjackSwift
import SwiftUI

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
            Image(uiImage: app.alternateIcon ?? app.icon ?? UIImage())
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))

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
                    }
                }
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
                Text(version)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu { if !appList.isSelectorMode { cellContextMenuWrapper } }
        .background(cellBackground)
        .alert(isPresented: .constant(cleanResultMessage != nil)) {
            Alert(
                title: Text("清理数据"),
                message: Text(cleanResultMessage ?? ""),
                dismissButton: .default(Text("确定")) { cleanResultMessage = nil }
            )
        }
    }

    @ViewBuilder
    var cellContextMenu: some View {
        Button { launch() } label: { Label(NSLocalizedString("Launch", comment: ""), systemImage: "command") }

        if AppListModel.hasTrollStore && app.isAllowedToAttachOrDetach {
            if app.isDetached {
                Button {
                    do {
                        try InjectorV3(app.url).setMetadataDetached(false)
                        app.reload()
                        appList.isRebuildNeeded = true
                    } catch { DDLogError("\(error)") }
                } label: { Label(NSLocalizedString("Unlock Version", comment: ""), systemImage: "lock.open") }
            } else {
                Button {
                    do {
                        try InjectorV3(app.url).setMetadataDetached(true)
                        app.reload()
                        appList.isRebuildNeeded = true
                    } catch { DDLogError("\(error)") }
                } label: { Label(NSLocalizedString("Lock Version", comment: ""), systemImage: "lock") }
            }
        }

        Button {
            openInFilza(app.url, type: .root)
        } label: {
            if appList.isFilzaInstalled {
                Label("应用目录", systemImage: "scope")
            } else {
                Label("应用目录 (Filza未安装)", systemImage: "xmark.octagon")
            }
        }
        .disabled(!appList.isFilzaInstalled)

        if let dataURL = app.dataContainerURL {
            Button {
                openInFilza(dataURL, type: .dataContainer)
            } label: {
                Label("数据目录", systemImage: "folder")
            }
        }

        if let groupURL = app.appGroupContainerURL {
            Button {
                openInFilza(groupURL, type: .appGroupContainer)
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
                        .foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder
    var cellContextMenuWrapper: some View {
        if #available(iOS 16, *) { cellContextMenu } else { cellContextMenu }
    }

    @ViewBuilder
    var cellBackground: some View {
        if #available(iOS 15, *) {
            if #available(iOS 16, *) {} else {
                Color.clear.contextMenu { if !appList.isSelectorMode { cellContextMenu } }.id(app.isDetached)
            }
        }
    }

    private func launch() {
        LSApplicationWorkspace.default().openApplication(withBundleID: app.bid)
    }

    private func openInFilza(_ url: URL, type: FilzaOpenType) {
        appList.openInFilza(url, type: type)
    }

    private func confirmCleanData() {
        let alert = UIAlertController(
            title: "彻底清理",
            message: "永久删除「\(app.name)」的数据目录、应用组目录内的所有文件，以及 Keychain 数据？\n⚠️ 目录本身不会被删除，仅清空内部内容。\n此操作不可逆！",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认清理", style: .destructive) { _ in performFullClean() })
        if let vc = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            vc.present(alert, animated: true)
        }
    }

    private func performFullClean() {
        isCleaningData = true
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errors: [String] = []
            let fm = FileManager.default

            // 安全地清空目录内容（保留目录本身）
            func emptyDirectory(at url: URL, name: String) -> Bool {
                guard fm.fileExists(atPath: url.path) else {
                    errors.append("\(name) 目录不存在: \(url.path)")
                    return false
                }
                do {
                    let items = try fm.contentsOfDirectory(atPath: url.path)
                    for item in items {
                        // 跳过 . 和 .. 防止意外
                        if item == "." || item == ".." { continue }
                        let itemURL = url.appendingPathComponent(item)
                        try fm.removeItem(at: itemURL)
                    }
                    return true
                } catch {
                    errors.append("清空 \(name) 失败: \(error.localizedDescription)")
                    return false
                }
            }

            // 1. 清空数据目录
            if let dataURL = app.dataContainerURL {
                if !emptyDirectory(at: dataURL, name: "数据目录") {
                    success = false
                } else {
                    DDLogInfo("数据目录已清空: \(dataURL.path)")
                }
            }

            // 2. 清空应用组目录
            if let groupURL = app.appGroupContainerURL {
                if !emptyDirectory(at: groupURL, name: "应用组目录") {
                    success = false
                } else {
                    DDLogInfo("应用组目录已清空: \(groupURL.path)")
                }
            }

            // 3. 清理 Keychain
            let keychainOK = clearKeychainForApp(bundleID: app.bid, teamID: app.teamID)
            if !keychainOK {
                errors.append("Keychain 清理失败（可能没有条目或权限不足）")
                success = false
            } else {
                DDLogInfo("Keychain 已清理: \(app.bid)")
            }

            DispatchQueue.main.async {
                isCleaningData = false
                if success {
                    cleanResultMessage = "清理完成！\n数据目录、应用组目录已清空，Keychain 已清理。"
                    app.reload()
                } else {
                    cleanResultMessage = "清理部分失败：\n" + errors.joined(separator: "\n")
                }
            }
        }
    }

    // MARK: - Keychain 清理（增强版）
    private func clearKeychainForApp(bundleID: String, teamID: String) -> Bool {
        // 可能的 access group 精确值
        let possibleGroups = [
            "\(teamID).\(bundleID)",
            teamID,
            bundleID
        ].filter { !$0.isEmpty }

        let secClasses: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]

        var anyDeleted = false

        // 尝试精确匹配
        for secClass in secClasses {
            for group in possibleGroups {
                let query: [CFString: Any] = [
                    kSecClass: secClass,
                    kSecAttrAccessGroup: group,
                    kSecMatchLimit: kSecMatchLimitAll,
                    kSecReturnAttributes: true
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let items = result as? [[CFString: Any]] {
                    for item in items {
                        var delQuery: [CFString: Any] = [kSecClass: secClass]
                        if let acc = item[kSecAttrAccount] as? String { delQuery[kSecAttrAccount] = acc }
                        if let svc = item[kSecAttrService] as? String { delQuery[kSecAttrService] = svc }
                        delQuery[kSecAttrAccessGroup] = group
                        if SecItemDelete(delQuery as CFDictionary) == errSecSuccess {
                            anyDeleted = true
                            DDLogDebug("删除 Keychain 条目: group=\(group), class=\(secClass)")
                        }
                    }
                }
            }
        }

        // 如果精确匹配没有删除任何内容，则尝试模糊匹配（遍历所有条目）
        if !anyDeleted {
            DDLogDebug("精确匹配未找到条目，尝试模糊匹配...")
            for secClass in secClasses {
                let query: [CFString: Any] = [
                    kSecClass: secClass,
                    kSecMatchLimit: kSecMatchLimitAll,
                    kSecReturnAttributes: true
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let items = result as? [[CFString: Any]] {
                    for item in items {
                        if let group = item[kSecAttrAccessGroup] as? String,
                           group.contains(bundleID) || group.contains(teamID) {
                            var delQuery: [CFString: Any] = [kSecClass: secClass]
                            if let acc = item[kSecAttrAccount] as? String { delQuery[kSecAttrAccount] = acc }
                            if let svc = item[kSecAttrService] as? String { delQuery[kSecAttrService] = svc }
                            if SecItemDelete(delQuery as CFDictionary) == errSecSuccess {
                                anyDeleted = true
                                DDLogDebug("模糊匹配删除 Keychain 条目: group=\(group)")
                            }
                        }
                    }
                }
            }
        }

        return anyDeleted
    }
}