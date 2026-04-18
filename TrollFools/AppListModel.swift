//
//  AppListModel.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Combine
import OrderedCollections
import SwiftUI
import CocoaLumberjackSwift

enum FilzaOpenType {
    case root
    case dataContainer
    case appGroupContainer
}

final class AppListModel: ObservableObject {
    enum Scope: Int, CaseIterable {
        case all
        case user
        case troll
        case system

        var localizedShortName: String {
            switch self {
            case .all: return NSLocalizedString("All", comment: "")
            case .user: return NSLocalizedString("User", comment: "")
            case .troll: return NSLocalizedString("TrollStore", comment: "")
            case .system: return NSLocalizedString("System", comment: "")
            }
        }

        var localizedName: String {
            switch self {
            case .all: return NSLocalizedString("All Applications", comment: "")
            case .user: return NSLocalizedString("User Applications", comment: "")
            case .troll: return NSLocalizedString("TrollStore Applications", comment: "")
            case .system: return NSLocalizedString("Injectable System Applications", comment: "")
            }
        }
    }

    static let isLegacyDevice: Bool = { UIScreen.main.fixedCoordinateSpace.bounds.height <= 736.0 }()
    static let hasTrollStore: Bool = { LSApplicationProxy(forIdentifier: "com.opa334.TrollStore") != nil }()
    private var _allApplications: [App] = []

    let selectorURL: URL?
    var isSelectorMode: Bool { selectorURL != nil }

    @Published var filter = FilterOptions()
    @Published var activeScope: Scope = .all
    @Published var activeScopeApps: OrderedDictionary<String, [App]> = [:]

    @Published var unsupportedCount: Int = 0
    @Published var unsupportedApps: [App] = []

    var allSupportedApps: [App] { _allApplications }

    lazy var isFilzaInstalled: Bool = {
        if let filzaURL = URL(string: "filza://view") {
            return UIApplication.shared.canOpenURL(filzaURL)
        }
        return false
    }()

    @Published var isRebuildNeeded: Bool = false

    private let applicationChanged = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(selectorURL: URL? = nil) {
        self.selectorURL = selectorURL
        reload()

        Publishers.CombineLatest($filter, $activeScope)
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.performFilter() }
            .store(in: &cancellables)

        applicationChanged
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(darwinCenter, Unmanaged.passRetained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = Unmanaged<AppListModel>.fromOpaque(observer!).takeUnretainedValue() as AppListModel? else { return }
            observer.applicationChanged.send()
        }, "com.apple.LaunchServices.ApplicationsChanged" as CFString, nil, .coalesce)
    }

    deinit {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque(), nil, nil)
    }

    func reload() {
        let allApplications = Self.fetchApplications(&unsupportedCount, &unsupportedApps)
        allApplications.forEach { $0.appList = self }
        _allApplications = allApplications
        performFilter()
    }

    func performFilter() {
        var filteredApplications = _allApplications
        if !filter.searchKeyword.isEmpty {
            filteredApplications = filteredApplications.filter {
                $0.name.localizedCaseInsensitiveContains(filter.searchKeyword) ||
                $0.bid.localizedCaseInsensitiveContains(filter.searchKeyword) ||
                $0.latinName.localizedCaseInsensitiveContains(filter.searchKeyword.components(separatedBy: .whitespaces).joined())
            }
        }
        if filter.showPatchedOnly {
            filteredApplications = filteredApplications.filter { $0.isInjected || $0.hasPersistedAssets }
        }
        switch activeScope {
        case .all: activeScopeApps = Self.groupedAppList(filteredApplications)
        case .user: activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isUser })
        case .troll: activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isFromTroll })
        case .system: activeScopeApps = Self.groupedAppList(filteredApplications.filter { $0.isFromApple })
        }
    }

    static func fetchApplications(_ unsupportedCount: inout Int, _ unsupportedApps: inout [App]) -> [App] {
        let excludedIdentifiers: Set<String> = [
            "com.opa334.Dopamine",
            "org.coolstar.SileoStore",
            "xyz.willy.Zebra",
        ]
        let allApps: [App] = LSApplicationWorkspace.default()
            .allApplications()
            .compactMap { proxy in
                guard let id = proxy.applicationIdentifier(),
                      let url = proxy.bundleURL(),
                      let teamID = proxy.teamID(),
                      let appType = proxy.applicationType(),
                      let localizedName = proxy.localizedName()
                else { return nil }
                guard !id.hasPrefix("wiki.qaq.") && !id.hasPrefix("com.82flex.") && !id.hasPrefix("ch.xxtou.") else { return nil }
                guard !excludedIdentifiers.contains(id) else { return nil }
                let shortVersionString: String? = proxy.shortVersionString()
                let app = App(bid: id, name: localizedName, type: appType, teamID: teamID, url: url, version: shortVersionString)
                if app.isUser && app.isFromApple { return nil }
                guard app.isRemovable else { return nil }
                return app
            }
        let filteredApps = allApps
            .filter { $0.isSystem || InjectorV3.main.checkIsEligibleAppBundle($0.url) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        unsupportedCount = allApps.count - filteredApps.count
        let filteredSet = Set(filteredApps.map { $0.bid })
        unsupportedApps = allApps.filter { !filteredSet.contains($0.bid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return filteredApps
    }

    // MARK: - Filza Navigation
    func openInFilza(_ url: URL, type: FilzaOpenType = .root) {
        var targetURL = url
        let fm = FileManager.default

        switch type {
        case .dataContainer:
            let documents = url.appendingPathComponent("Documents")
            if fm.fileExists(atPath: documents.path) {
                targetURL = documents
            }
        case .appGroupContainer:
            do {
                let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                if let groupFolder = contents.first(where: { $0.lastPathComponent.hasPrefix("group.") }) {
                    targetURL = groupFolder
                }
            } catch {
                DDLogError("Failed to list app group dir: \(error)")
            }
        case .root:
            break
        }

        let resolvedPath = targetURL.resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix("/") else {
            DDLogError("Invalid path: \(resolvedPath)")
            return
        }
        guard let encodedPath = resolvedPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            DDLogError("Encoding failed: \(resolvedPath)")
            return
        }
        let filzaURLString = "filza://view" + encodedPath
        guard let filzaURL = URL(string: filzaURLString) else {
            DDLogError("Invalid Filza URL: \(filzaURLString)")
            return
        }
        if UIApplication.shared.canOpenURL(filzaURL) {
            UIApplication.shared.open(filzaURL) { success in
                if !success { DDLogError("Failed to open Filza: \(filzaURL)") }
            }
        } else {
            DDLogError("Filza not installed")
        }
    }

    func rebuildIconCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            LSApplicationWorkspace.default().openApplication(withBundleID: "com.opa334.TrollStore")
        }
    }
}

// MARK: - Grouping
extension AppListModel {
    static let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#"
    private static let allowedCharacterSet = CharacterSet(charactersIn: allowedCharacters)

    private static func groupedAppList(_ apps: [App]) -> OrderedDictionary<String, [App]> {
        var groupedApps = OrderedDictionary<String, [App]>()
        for app in apps {
            var key = app.name
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .applyingTransform(.stripCombiningMarks, reverse: false)?
                .applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .prefix(1).uppercased() ?? "#"
            if let scalar = UnicodeScalar(key), !allowedCharacterSet.contains(scalar) {
                key = "#"
            }
            if groupedApps[key] == nil { groupedApps[key] = [] }
            groupedApps[key]?.append(app)
        }
        groupedApps.sort { app1, app2 in
            if let c1 = app1.key.first, let c2 = app2.key.first,
               let idx1 = allowedCharacters.firstIndex(of: c1),
               let idx2 = allowedCharacters.firstIndex(of: c2) {
                return idx1 < idx2
            }
            return app1.key < app2.key
        }
        return groupedApps
    }
}