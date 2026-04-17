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
    @State private var savedStatesList: [(bid: String, count: Int)] = []
    @State private var clearResultMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(NSLocalizedString("Injection Strategy", comment: ""), selection: $injectStrategy) {
                        ForEach(InjectorV3.Strategy.allCases, id: \.self) { strategy in
                            Text(strategy.localizedDescription).tag(strategy)
                        }
                    }
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Choose how TrollFools tries possible targets. If the plug-in does not work as expected, try another option.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Enable Compatibility Fallback", comment: ""), isOn: $useFrameworkEnumerationFallback)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("If needed, TrollFools will use a compatibility mode to improve success rate. Keeping this on is recommended.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Prefer Main Executable", comment: ""), isOn: $preferMainExecutable)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Try the app’s main file first. Turn this on when the plug-in does not seem active.", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Use Weak Reference", comment: ""), isOn: $useWeakReference)
                } footer: {
                    paddedHeaderFooterText(NSLocalizedString("Controls whether the app crashes when the plug-in cannot be found. Keeping this on can reduce unexpected crashes in some scenarios, but the plug-in will not work in those cases.", comment: ""))
                }

                // 自动恢复管理 Section
                Section {
                    HStack {
                        Text("自动恢复状态")
                            .font(.headline)
                        Spacer()
                        Text("\(savedStatesCount) 个应用")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if !savedStatesList.isEmpty {
                        ForEach(savedStatesList, id: \.bid) { item in
                            HStack {
                                Text(item.bid)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.count) 个插件")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                } header: {
                    Text("自动恢复管理")
                } footer: {
                    paddedHeaderFooterText("当应用更新后，TrollFools 会自动重新启用之前启用的插件。此处显示已保存的插件状态，清除后将不会自动恢复。")
                }
            }
            .navigationTitle(NSLocalizedString("Advanced Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onViewWillAppear { viewController in
                viewControllerHost.viewController = viewController
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
        }
    }
    
    private func refreshSavedStates() {
        savedStatesCount = AutoResumeService.shared.getSavedStatesCount()
        savedStatesList = AutoResumeService.shared.getSavedStatesList()
    }
    
    private func clearSavedStates() {
        let count = AutoResumeService.shared.clearAllSavedStates()
        clearResultMessage = "已清除 \(count) 个应用的自动恢复状态"
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