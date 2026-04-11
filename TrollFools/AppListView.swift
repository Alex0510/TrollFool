//
//  AppListView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import CocoaLumberjackSwift
import OrderedCollections
import SwiftUI
import SwiftUIIntrospect

typealias Scope = AppListModel.Scope

struct AppListView: View {
    let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad

    @StateObject var searchViewModel = AppListSearchModel()
    @EnvironmentObject var appList: AppListModel
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State var selectorOpenedURL: URLIdentifiable? = nil
    @State var selectedIndex: String? = nil

    @State var isWarningPresented = false
    @State var temporaryOpenedURL: URLIdentifiable? = nil

    @State var latestVersionString: String?

    @AppStorage("isWarningHidden")
    var isWarningHidden: Bool = false

    // 批量操作状态
    @State private var isBatchProcessing = false
    @State private var batchResultMessage: String?
    @State private var showingUnsupportedApps = false

    var appString: String {
        let appNameString = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "TrollFools"
        let appVersionString = String(
            format: "v%@ (%@)",
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        )

        let appStringFormat = """
        %@ %@
        %@ © 2024-%d %@
        """

        return String(
            format: appStringFormat,
            appNameString, appVersionString,
            NSLocalizedString("Copyright", comment: ""),
            Calendar.current.component(.year, from: Date()),
            NSLocalizedString("Lessica, huami1314, iosdump and other contributors", comment: "")
        )
    }

    var body: some View {
        if #available(iOS 15, *) {
            content
                .alert(
                    "提示",
                    isPresented: $isWarningPresented,
                    presenting: temporaryOpenedURL
                ) { result in
                    Button {
                        selectorOpenedURL = result
                    } label: {
                        Text("继续")
                    }
                    Button(role: .destructive) {
                        selectorOpenedURL = result
                        isWarningHidden = true
                    } label: {
                        Text("继续且不再提示")
                    }
                    Button(role: .cancel) {
                        temporaryOpenedURL = nil
                        isWarningPresented = false
                    } label: {
                        Text("取消")
                    }
                } message: {
                    Text(OptionView.warningMessage([$0.url]))
                }
                .alert(isPresented: .constant(batchResultMessage != nil)) {
                    Alert(
                        title: Text("批量操作"),
                        message: Text(batchResultMessage ?? ""),
                        dismissButton: .default(Text("确定")) {
                            batchResultMessage = nil
                        }
                    )
                }
        } else {
            content
        }
    }

    var content: some View {
        styledNavigationView
            .animation(.easeOut, value: appList.activeScopeApps.keys)
            .sheet(item: $selectorOpenedURL) { urlWrapper in
                AppListView()
                    .environmentObject(AppListModel(selectorURL: urlWrapper.url))
            }
            .sheet(isPresented: $showingUnsupportedApps) {
                UnsupportedAppsView(unsupportedApps: appList.unsupportedApps)
            }
            .onOpenURL { url in
                let ext = url.pathExtension.lowercased()
                guard url.isFileURL,
                      ext == "dylib" || ext == "deb" || ext == "zip"
                else {
                    return
                }

                let urlIdent = URLIdentifiable(url: preprocessURL(url))
                if #available(iOS 15, *) {
                    if !isWarningHidden && ext == "deb" {
                        temporaryOpenedURL = urlIdent
                        isWarningPresented = true
                        return
                    }
                }

                selectorOpenedURL = urlIdent
            }
            .onAppear {
                CheckUpdateManager.shared.checkUpdateIfNeeded { latestVersion, _ in
                    DispatchQueue.main.async {
                        withAnimation {
                            latestVersionString = latestVersion?.tagName
                        }
                    }
                }
            }
    }

    @ViewBuilder
    var styledNavigationView: some View {
        if isPad {
            navigationView
                .navigationViewStyle(.automatic)
        } else {
            navigationView
                .navigationViewStyle(.stack)
        }
    }

    var navigationView: some View {
        NavigationView {
            ScrollViewReader { reader in
                ZStack {
                    refreshableListView

                    if verticalSizeClass == .regular && appList.activeScopeApps.keys.count > 1 {
                        IndexableScroller(
                            indexes: appList.activeScopeApps.keys.elements,
                            currentIndex: $selectedIndex
                        )
                        .accessibilityHidden(true)
                    }
                }
                .onChange(of: selectedIndex) { index in
                    if let index {
                        reader.scrollTo("AppSection-\(index)", anchor: .center)
                    }
                }
            }

            // Detail view shown when nothing has been selected
            if !appList.isSelectorMode {
                PlaceholderView()
            }
        }
    }

    @ViewBuilder
    var refreshableListView: some View {
        if #available(iOS 15, *) {
            searchableListView
                .refreshable {
                    appList.reload()
                }
        } else {
            searchableListView
                .introspect(.list, on: .iOS(.v14)) { tableView in
                    if tableView.refreshControl == nil {
                        tableView.refreshControl = {
                            let refreshControl = UIRefreshControl()
                            refreshControl.addAction(UIAction { action in
                                appList.reload()
                                if let control = action.sender as? UIRefreshControl {
                                    control.endRefreshing()
                                }
                            }, for: .valueChanged)
                            return refreshControl
                        }()
                    }
                }
        }
    }

    var searchableListView: some View {
        listView
            .onChange(of: appList.filter.showPatchedOnly) { showPatchedOnly in
                if let searchBar = searchViewModel.searchController?.searchBar {
                    reloadSearchBarPlaceholder(searchBar, showPatchedOnly: showPatchedOnly)
                }
            }
            .onReceive(searchViewModel.$searchKeyword) {
                appList.filter.searchKeyword = $0
            }
            .onReceive(searchViewModel.$searchScopeIndex) {
                appList.activeScope = Scope(rawValue: $0) ?? .all
            }
            .introspect(.viewController, on: .iOS(.v14, .v15, .v16, .v17, .v18)) { viewController in
                viewController.navigationItem.hidesSearchBarWhenScrolling = true
                if searchViewModel.searchController == nil {
                    viewController.navigationItem.searchController = {
                        let searchController = UISearchController(searchResultsController: nil)
                        searchController.searchResultsUpdater = searchViewModel
                        searchController.obscuresBackgroundDuringPresentation = false
                        searchController.hidesNavigationBarDuringPresentation = true
                        searchController.automaticallyShowsScopeBar = false
                        if #available(iOS 16, *) {
                            searchController.scopeBarActivation = .manual
                        }
                        setupSearchBar(searchController: searchController)
                        return searchController
                    }()
                    searchViewModel.searchController = viewController.navigationItem.searchController
                }
            }
    }

    var listView: some View {
        List {
            topSection
            appSections
        }
        .animation(.easeOut, value: combines(
            appList.isRebuildNeeded,
            appList.activeScope,
            appList.filter,
            appList.unsupportedCount
        ))
        .listStyle(.insetGrouped)
        .navigationTitle(appList.isSelectorMode ?
            "选择要注入的应用" :
            "巨魔注入器"
        )
        .navigationBarTitleDisplayMode((AppListModel.isLegacyDevice || appList.isSelectorMode) ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if appList.isSelectorMode, let selectorURL = appList.selectorURL {
                    VStack {
                        Text(selectorURL.lastPathComponent).font(.headline)
                        Text("选择要注入的应用").font(.caption)
                    }
                }
            }

            // 原有“仅显示已注入”按钮
            ToolbarItem(placement: .navigationBarTrailing) {
                if !appList.isSelectorMode {
                    Button {
                        appList.filter.showPatchedOnly.toggle()
                    } label: {
                        if #available(iOS 15, *) {
                            Image(systemName: appList.filter.showPatchedOnly
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                        } else {
                            Image(systemName: appList.filter.showPatchedOnly
                                ? "eject.circle.fill"
                                : "eject.circle")
                        }
                    }
                    .accessibilityLabel("仅显示已注入")
                }
            }

            // 批量操作菜单（中文）
            ToolbarItem(placement: .navigationBarTrailing) {
                if !appList.isSelectorMode {
                    Menu {
                        Button(action: batchEnableAll) {
                            Label("启用所有插件", systemImage: "square.stack.3d.up")
                        }
                        .disabled(isBatchProcessing)

                        Button(action: batchDisableAll) {
                            Label("禁用所有插件", systemImage: "square.stack.3d.up.slash")
                        }
                        .disabled(isBatchProcessing)
                    } label: {
                        if isBatchProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    var topSection: some View {
        Section {
            if AppListModel.hasTrollStore && appList.isRebuildNeeded {
                rebuildButton
                    .transition(.opacity)
            }
        } header: {
            if AppListModel.hasTrollStore && appList.isRebuildNeeded {
                Text("")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if appList.activeScope == .all && latestVersionString != nil {
                    upgradeButton
                        .transition(.opacity)
                }

                if !appList.filter.isSearching && !appList.filter.showPatchedOnly && !appList.isRebuildNeeded {
                    if appList.activeScope == .system {
                        Text("仅列出可注入的系统应用")
                            .font(.footnote)
                    } else if appList.activeScope != .troll && appList.unsupportedCount > 0 {
                        Button {
                            showingUnsupportedApps = true
                        } label: {
                            Text(String(format: "另有 %d 个不支持的用户应用。点击查看", appList.unsupportedCount))
                                .font(.footnote)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .id("TopSection")
    }

    var rebuildButton: some View {
        Button {
            appList.rebuildIconCache()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("重建图标缓存")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("你需要在 TrollStore 中重建图标缓存以应用更改。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "timelapse")
                    .font(.title)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
    }

    var upgradeButton: some View {
        Button {
            CheckUpdateManager.shared.executeUpgrade()
        } label: {
            Text(String(format: "新版本 %@ 可用！", latestVersionString ?? "(null)"))
                .font(.footnote)
        }
    }

    var appSections: some View {
        ForEach(appList.activeScopeApps.isEmpty ? ["_"] : Array(appList.activeScopeApps.keys), id: \.self) { sectionKey in
            appSection(forKey: sectionKey)
        }
    }

    func appSection(forKey sectionKey: String) -> some View {
        Section {
            ForEach(appList.activeScopeApps[sectionKey] ?? [], id: \.bid) { app in
                NavigationLink {
                    if appList.isSelectorMode, let selectorURL = appList.selectorURL {
                        InjectView(app, urlList: [selectorURL])
                    } else {
                        OptionView(app)
                    }
                } label: {
                    if #available(iOS 16, *) {
                        AppListCell(app: app)
                    } else {
                        AppListCell(app: app)
                            .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            if sectionKey == "_" {
                Text("没有应用")
                    .font(.footnote)
                    .textCase(.none)
            } else {
                Text(sectionKey == selectedIndex ? "→ \(sectionKey)" : sectionKey)
                    .font(.footnote)
            }
        } footer: {
            if (sectionKey == "_" || sectionKey == appList.activeScopeApps.keys.last) && !appList.isSelectorMode && !appList.filter.isSearching {
                footer
            }
        }
        .id("AppSection-\(sectionKey)")
    }

    @ViewBuilder
    var footer: some View {
        if #available(iOS 16, *) {
            footerContent
                .padding(.vertical, 16)
        } else if #available(iOS 15, *) {
            footerContent
                .padding(.top, 10)
                .padding(.bottom, 16)
        } else {
            footerContent
                .padding(.all, 16)
        }
    }

    var footerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appString)
                .font(.footnote)

            Button {
                UIApplication.shared.open(URL(string: "https://github.com/Lessica/TrollFools")!)
            } label: {
                Text("源代码")
                    .font(.footnote)
            }
        }
    }

    private func preprocessURL(_ url: URL) -> URL {
        let isInbox = url.path.contains("/Documents/Inbox/")
        guard isInbox else {
            return url
        }
        let fileNameNoExt = url.deletingPathExtension().lastPathComponent
        let fileNameComps = fileNameNoExt.components(separatedBy: CharacterSet(charactersIn: "._- "))
        guard let lastComp = fileNameComps.last, fileNameComps.count > 1, lastComp.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return url
        }
        let newURL = url.deletingLastPathComponent()
            .appendingPathComponent(String(fileNameNoExt.prefix(fileNameNoExt.count - lastComp.count - 1)))
            .appendingPathExtension(url.pathExtension)
        do {
            try? FileManager.default.removeItem(at: newURL)
            try FileManager.default.copyItem(at: url, to: newURL)
            return newURL
        } catch {
            return url
        }
    }

    private func setupSearchBar(searchController: UISearchController) {
        if let searchBarDelegate = searchController.searchBar.delegate, (searchBarDelegate as? NSObject) != searchViewModel {
            searchViewModel.forwardSearchBarDelegate = searchBarDelegate
        }

        searchController.searchBar.delegate = searchViewModel
        searchController.searchBar.showsScopeBar = true
        searchController.searchBar.scopeButtonTitles = Scope.allCases.map { $0.localizedShortName }
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no

        reloadSearchBarPlaceholder(searchController.searchBar, showPatchedOnly: appList.filter.showPatchedOnly)
    }

    private func reloadSearchBarPlaceholder(_ searchBar: UISearchBar, showPatchedOnly: Bool) {
        searchBar.placeholder = (showPatchedOnly
            ? "搜索已注入…"
            : "搜索…")
    }

    // MARK: - 批量操作（作用于所有支持注入的应用，包括巨魔应用）

    private func batchEnableAll() {
        let allApps = appList.allSupportedApps
        guard !allApps.isEmpty else { return }
        performBatchOperation(on: allApps, enable: true)
    }

    private func batchDisableAll() {
        let allApps = appList.allSupportedApps
        guard !allApps.isEmpty else { return }
        performBatchOperation(on: allApps, enable: false)
    }

    private func performBatchOperation(on apps: [App], enable: Bool) {
        isBatchProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failCount = 0

            for app in apps {
                do {
                    let injector = try InjectorV3(app.url)
                    var didSomething = false

                    if enable {
                        // 启用所有持久化插件（重新注入已存在的、但未注入的插件）
                        let persistedURLs = InjectorV3.main.persistedAssetURLs(bid: app.bid)
                        let injectedURLs = InjectorV3.main.injectedAssetURLsInBundle(app.url)
                        let toInject = persistedURLs.filter { !injectedURLs.contains($0) }
                        if !toInject.isEmpty {
                            try injector.inject(toInject, shouldPersist: false)
                            didSomething = true
                        }
                    } else {
                        // 禁用所有已注入的插件（但不删除文件）
                        let injectedURLs = InjectorV3.main.injectedAssetURLsInBundle(app.url)
                        if !injectedURLs.isEmpty {
                            try injector.ejectAll(shouldDesist: false)
                            didSomething = true
                        }
                    }

                    if didSomething {
                        DispatchQueue.main.async {
                            app.reload()
                        }
                        successCount += 1
                    }
                } catch {
                    DDLogError("Batch operation failed for \(app.bid): \(error)")
                    failCount += 1
                }
            }

            DispatchQueue.main.async {
                isBatchProcessing = false
                if failCount == 0 {
                    if enable {
                        batchResultMessage = "已成功启用 \(successCount) 个应用的插件。"
                    } else {
                        batchResultMessage = "已成功禁用 \(successCount) 个应用的插件。"
                    }
                } else {
                    batchResultMessage = "完成，成功 \(successCount) 个，失败 \(failCount) 个。"
                }
                appList.reload()
            }
        }
    }
}

struct URLIdentifiable: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - 不支持的应用详情页（带图标）
struct UnsupportedAppsView: View {
    let unsupportedApps: [App]
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(unsupportedApps, id: \.bid) { app in
                    HStack(spacing: 12) {
                        // 应用图标
                        Image(uiImage: app.icon ?? UIImage())
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.name)
                                    .font(.headline)
                                Spacer()
                                if let version = app.version {
                                    Text(version)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(app.bid)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("不支持的应用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}