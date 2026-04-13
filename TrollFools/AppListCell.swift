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

        // 数据目录
        if let dataURL = app.dataContainerURL {
            Button {
                openInFilza(dataURL)
            } label: {
                Label("数据目录", systemImage: "folder")
            }
        }

        // 应用组目录
        if let groupURL = app.appGroupContainerURL {
            Button {
                openInFilza(groupURL)
            } label: {
                Label("应用组目录", systemImage: "folder.badge.gear")
            }
        }

        // 清理数据（兼容 iOS 14）
        if app.dataContainerURL != nil {
            if #available(iOS 15, *) {
                Button(role: .destructive) {
                    confirmCleanData()
                } label: {
                    Label("清理数据", systemImage: "trash")
                }
            } else {
                Button {
                    confirmCleanData()
                } label: {
                    Label("清理数据", systemImage: "trash")
                }
            }
        }

        Button {
            openInFilza(app.url)
        } label: {
            if isFilzaInstalled {
                Label(NSLocalizedString("Show in Filza", comment: ""), systemImage: "scope")
            } else {
                Label(NSLocalizedString("Filza (URL Scheme) Not Installed", comment: ""), systemImage: "xmark.octagon")
            }
        }
        .disabled(!isFilzaInstalled)
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

    // MARK: - 清理数据
    private func confirmCleanData() {
        guard let dataURL = app.dataContainerURL else { return }

        let alert = UIAlertController(
            title: "清理数据",
            message: "此操作将删除应用「\(app.name)」的所有用户数据（包括文档、缓存等），此操作不可撤销。是否继续？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认清理", style: .destructive) { _ in
            performCleanData(at: dataURL)
        })

        if let viewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }

    private func performCleanData(at directory: URL) {
        isCleaningData = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var success = true
            var errorMessage: String?

            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
                for item in contents {
                    let itemURL = directory.appendingPathComponent(item)
                    try fileManager.removeItem(at: itemURL)
                }
            } catch {
                success = false
                errorMessage = error.localizedDescription
            }

            DispatchQueue.main.async {
                isCleaningData = false
                if success {
                    cleanResultMessage = "数据已清理完成。"
                } else {
                    cleanResultMessage = "清理失败：\(errorMessage ?? "未知错误")"
                }
            }
        }
    }
}