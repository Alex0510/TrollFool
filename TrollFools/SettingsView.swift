//
//  SettingsView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/28.
//

import SwiftUI

struct SettingsView: View {
    let app: App

    init(_ app: App) {
        self.app = app
        _useWeakReference = AppStorage(wrappedValue: true, "UseWeakReference-\(app.bid)")
        _preferMainExecutable = AppStorage(wrappedValue: false, "PreferMainExecutable-\(app.bid)")
        _useFrameworkEnumerationFallback = AppStorage(wrappedValue: true, "UseFrameworkEnumerationFallback-\(app.bid)")
        _injectStrategy = AppStorage(wrappedValue: .lexicographic, "InjectStrategy-\(app.bid)")
    }

    @AppStorage var useWeakReference: Bool
    @AppStorage var preferMainExecutable: Bool
    @AppStorage var useFrameworkEnumerationFallback: Bool
    @AppStorage var injectStrategy: InjectorV3.Strategy

    @StateObject var viewControllerHost = ViewControllerHost()
    @State private var showClearConfirmation = false
    @State private var savedStatesCount = 0
    @State private var savedStatesDetail: [SavedAppState] = []
    @State private var clearResultMessage: String?
    @State private var showForceCheckAlert = false
    @State private var forceCheckMessage = ""

    // 折叠状态
    @State private var isExpanded: Bool = true

    var body: some View {
        NavigationView {
            Form {
                // 注入策略
                Section {
                    Picker(NSLocalizedString("Injection Strategy", comment: ""), selection: $injectStrategy) {
                        ForEach(InjectorV3.Strategy.allCases, id: \.self) { strategy in
                            Text(strategy.localizedDescription).tag(strategy)
                        }
                    }
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Choose how TrollFools tries possible targets. If the plug-in does not work as expected, try another option.", comment: ""))
                }

                // 兼容模式
                Section {
                    Toggle(NSLocalizedString("Enable Compatibility Fallback", comment: ""), isOn: $useFrameworkEnumerationFallback)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("If needed, TrollFools will use a compatibility mode to improve success rate. Keeping this on is recommended.", comment: ""))
                }

                // 优先主可执行文件
                Section {
                    Toggle(NSLocalizedString("Prefer Main Executable", comment: ""), isOn: $preferMainExecutable)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Try the app’s main file first. Turn this on when the plug-in does not seem active.", comment: ""))
                }

                // 弱引用
                Section {
                    Toggle(NSLocalizedString("Use Weak Reference", comment: ""), isOn: $useWeakReference)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Controls whether the app crashes when the plug-in cannot be found. Keeping this on can reduce unexpected crashes in some scenarios, but the plug-in will not work in those cases.", comment: ""))
                }

                // 自动恢复管理
                Section {
                    HStack {
                        Text("自动恢复状态")
                            .font(.headline)
                        Spacer()
                        Text("\(savedStatesCount) 个应用")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // 折叠/展开按钮
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                                .padding(.leading, 8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    
                    if isExpanded {
                        if !savedStatesDetail.isEmpty {
                            ForEach(savedStatesDetail) { state in
                                DisclosureGroup(
                                    content: {
                                        ForEach(state.pluginNames, id: \.self) { pluginName in
                                            HStack {
                                                Image(systemName: "puzzlepiece")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(pluginName)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                        }
                                    },
                                    label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(state.appName)
                                                    .font(.body)
                                                Text(state.bid)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text("\(state.pluginNames.count) 个插件")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            // 删除按钮
                                            Button(action: {
                                                removeSavedState(for: state.bid)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(BorderlessButtonStyle())
                                        }
                                    }
                                )
                            }
                        } else if savedStatesCount > 0 {
                            Text("加载中...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("清除所有保存状态")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .disabled(savedStatesCount == 0)
                    
                    Button(action: {
                        forceCheck()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("立即检查并恢复插件")
                            Spacer()
                        }
                    }
                } header: {
                    Text("自动恢复管理")
                } footer: {
                    paddedHeaderFooterText("当应用更新后，TrollFools 会自动重新启用之前启用的插件。此处显示已保存的插件状态，清除后将不会自动恢复。\n点击右侧垃圾桶图标可删除该应用的恢复记录。")
                }
            }
            .navigationTitle(NSLocalizedString("Advanced Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onViewWillAppear { viewController in
                viewControllerHost.viewController = viewController
                refreshSavedStates()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoResumeStateChanged"))) { _ in
                refreshSavedStates()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewControllerHost.viewController?.dismiss(animated: true)
                    } label: {
                        Text(NSLocalizedString("Done", comment: ""))
                    }
                }
            }
            .alert(isPresented: $showClearConfirmation) {
                Alert(
                    title: Text("清除保存状态"),
                    message: Text("确定要清除所有 \(savedStatesCount) 个应用的自动恢复状态吗？此操作不可撤销。"),
                    primaryButton: .destructive(Text("清除")) {
                        clearSavedStates()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: .constant(clearResultMessage != nil)) {
                Alert(
                    title: Text("操作完成"),
                    message: Text(clearResultMessage ?? ""),
                    dismissButton: .default(Text("确定")) {
                        clearResultMessage = nil
                        refreshSavedStates()
                    }
                )
            }
            .alert(isPresented: $showForceCheckAlert) {
                Alert(
                    title: Text("检查完成"),
                    message: Text(forceCheckMessage),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }
    
    private func refreshSavedStates() {
        savedStatesDetail = AutoResumeService.shared.getSavedStatesDetail()
        savedStatesCount = savedStatesDetail.count
    }
    
    private func clearSavedStates() {
        let count = AutoResumeService.shared.clearAllSavedStates()
        clearResultMessage = "已清除 \(count) 个应用的自动恢复状态"
    }
    
    private func removeSavedState(for bid: String) {
        AutoResumeService.shared.removeSavedState(for: bid)
        refreshSavedStates()
        clearResultMessage = "已删除该应用的自动恢复状态"
    }
    
    private func forceCheck() {
        AutoResumeService.shared.forceCheck()
        forceCheckMessage = "已检查所有应用，如需恢复插件请稍后查看。"
        showForceCheckAlert = true
        refreshSavedStates()
    }

    @ViewBuilder
    private func paddedHeaderFooterText(_ content: String) -> some View {
        if #available(iOS 15, *) {
            Text(content)
                .font(.footnote)
        } else {
            Text(content)
                .font(.footnote)
                .padding(.horizontal, 16)
        }
    }
}