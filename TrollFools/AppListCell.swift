//
//  AppListCell.swift
//  TrollFool
//
//  Created by 82Flex on 2024/10/30.
//

import CocoaLumberjackSwift
import SwiftUI
import SQLite3

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
            message: "永久删除「\(app.name)」的用户数据（Documents/Library/Caches/tmp）及 Keychain 数据？\n应用组目录内容也会被清空。\n⚠️ 容器根目录及系统元数据文件将被保留。\n此操作不可逆！",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认清理", style: .destructive) { _ in performFullClean() })
        if let vc = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            vc.present(alert, animated: true)
        }
    }

    // MARK: - 安全清空目录（保留根目录及 .com.apple.mobile_container_manager.metadata.plist）
    private func performFullClean() {
        isCleaningData = true
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errors: [String] = []
            let fm = FileManager.default

            // 清空目录内容，但保留根目录本身以及特定的系统文件
            func clearDirectoryContentsPreservingRoot(at url: URL, name: String, preserveMetadata: Bool = true) -> Bool {
                guard fm.fileExists(atPath: url.path) else {
                    errors.append("\(name) 目录不存在: \(url.path)")
                    return false
                }
                do {
                    let items = try fm.contentsOfDirectory(atPath: url.path)
                    for item in items {
                        if preserveMetadata && item == ".com.apple.mobile_container_manager.metadata.plist" {
                            continue
                        }
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

            // 1. 数据容器：只清空标准子目录，根目录不动
            if let dataURL = app.dataContainerURL {
                let subdirs = ["Documents", "Library", "Caches", "tmp"]
                for sub in subdirs {
                    let subURL = dataURL.appendingPathComponent(sub)
                    if fm.fileExists(atPath: subURL.path) {
                        if !clearDirectoryContentsPreservingRoot(at: subURL, name: "数据目录/\(sub)", preserveMetadata: false) {
                            success = false
                        } else {
                            DDLogInfo("清空: \(subURL.path)")
                        }
                    } else {
                        DDLogDebug("目录不存在: \(subURL.path)")
                    }
                }
            }

            // 2. 应用组容器：清空所有内容，但保留根目录及 .com.apple.mobile_container_manager.metadata.plist
            if let groupURL = app.appGroupContainerURL {
                if !clearDirectoryContentsPreservingRoot(at: groupURL, name: "应用组目录", preserveMetadata: true) {
                    success = false
                } else {
                    DDLogInfo("应用组目录已清空: \(groupURL.path)")
                }
            }

            // 3. Keychain 清理（使用 SQLite 直接操作数据库）
            let keychainOK = clearKeychainUsingSQLite(bundleID: app.bid, teamID: app.teamID)
            if !keychainOK {
                errors.append("Keychain 清理失败（可能没有条目或权限不足）")
                success = false
            } else {
                DDLogInfo("Keychain 已清理: \(app.bid)")
            }

            DispatchQueue.main.async {
                isCleaningData = false
                if success {
                    cleanResultMessage = "清理完成！\n已清空应用数据（Documents/Library/Caches/tmp）及 Keychain。\n应用组目录内容已清空，容器结构完整。"
                    app.reload()
                } else {
                    cleanResultMessage = "清理部分失败：\n" + errors.joined(separator: "\n")
                }
            }
        }
    }

    // MARK: - Keychain 清理（使用 SQLite3）
    private func clearKeychainUsingSQLite(bundleID: String, teamID: String) -> Bool {
        let dbPath = "/var/Keychains/keychain-2.db"
        var db: OpaquePointer?

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            DDLogError("无法打开 Keychain 数据库: \(dbPath)")
            return false
        }
        defer { sqlite3_close(db) }

        // 构造可能的 access group 匹配条件
        let possiblePrefixes = [teamID, "\(teamID).\(bundleID)", bundleID]
        var conditions = possiblePrefixes.map { "agrp LIKE '\($0)%'" }
        conditions.append("agrp LIKE '%\(bundleID)%'")
        let whereClause = conditions.joined(separator: " OR ")

        let tables = ["genp", "cert", "keys", "idents", "classes"]
        var anySuccess = false

        for table in tables {
            let sql = "DELETE FROM \(table) WHERE \(whereClause);"
            var errMsg: UnsafeMutablePointer<CChar>? = nil
            if sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK {
                DDLogInfo("成功从表 \(table) 删除 Keychain 条目")
                anySuccess = true
            } else {
                let error = errMsg.map { String(cString: $0) } ?? "unknown error"
                DDLogDebug("从表 \(table) 删除失败: \(error)")
                sqlite3_free(errMsg)
            }
        }

        return anySuccess
    }
}