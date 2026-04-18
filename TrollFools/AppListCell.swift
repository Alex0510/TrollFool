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
            // iOS 14 兼容：不使用 role 参数
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
            message: "永久删除「\(app.name)」的数据目录、应用组目录及 Keychain 数据？\n此操作不可逆！",
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

            // Data container
            if let dataURL = app.dataContainerURL {
                let dataPath = dataURL.path
                if fm.fileExists(atPath: dataPath) {
                    do {
                        let items = try fm.contentsOfDirectory(atPath: dataPath)
                        for item in items {
                            try fm.removeItem(at: dataURL.appendingPathComponent(item))
                        }
                        DDLogInfo("Cleaned data container for \(app.bid)")
                    } catch {
                        errors.append("数据目录清理失败: \(error.localizedDescription)")
                        success = false
                    }
                } else {
                    errors.append("数据目录不存在: \(dataPath)")
                }
            }

            // App group container
            if let groupURL = app.appGroupContainerURL {
                let groupPath = groupURL.path
                if fm.fileExists(atPath: groupPath) {
                    do {
                        let items = try fm.contentsOfDirectory(atPath: groupPath)
                        for item in items {
                            try fm.removeItem(at: groupURL.appendingPathComponent(item))
                        }
                        DDLogInfo("Cleaned app group container for \(app.bid)")
                    } catch {
                        errors.append("应用组目录清理失败: \(error.localizedDescription)")
                        success = false
                    }
                } else {
                    errors.append("应用组目录不存在: \(groupPath)")
                }
            }

            // Keychain
            let keychainOK = clearKeychainForApp(bundleID: app.bid, teamID: app.teamID)
            if !keychainOK {
                errors.append("Keychain 清理失败")
                success = false
            } else {
                DDLogInfo("Cleaned keychain for \(app.bid)")
            }

            DispatchQueue.main.async {
                isCleaningData = false
                if success {
                    cleanResultMessage = "清理完成！\n已删除数据目录、应用组目录及 Keychain 数据。"
                    app.reload()
                } else {
                    cleanResultMessage = "清理部分失败：\n" + errors.joined(separator: "\n")
                }
            }
        }
    }

    private func clearKeychainForApp(bundleID: String, teamID: String) -> Bool {
        let secClasses: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        var any = false
        for secClass in secClasses {
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
                    if let group = item[kSecAttrAccessGroup] as? String,
                       group.contains(bundleID) || group.contains(teamID) {
                        var delQuery: [CFString: Any] = [kSecClass: secClass]
                        if let account = item[kSecAttrAccount] as? String { delQuery[kSecAttrAccount] = account }
                        if let service = item[kSecAttrService] as? String { delQuery[kSecAttrService] = service }
                        if let generic = item[kSecAttrGeneric] as? Data { delQuery[kSecAttrGeneric] = generic }
                        if SecItemDelete(delQuery as CFDictionary) == errSecSuccess {
                            any = true
                        }
                    }
                }
            }
        }
        return any
    }
}