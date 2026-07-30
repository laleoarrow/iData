import SwiftUI

struct IDataAppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                model.openDocument()
            } label: {
                Label(model.localized(english: "Open…", chinese: "打开…"), systemImage: "folder")
            }
            .keyboardShortcut("o")

            Button {
                model.reopenLastFile()
            } label: {
                Label(model.localized(english: "Reopen Last File", chinese: "重新打开上个文件"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.lastOpenedFile == nil)
        }

        CommandGroup(after: .appInfo) {
            Button(model.localized(english: "Check for Updates…", chinese: "检查更新…")) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        CommandMenu(model.localized(english: "Session", chinese: "会话")) {
            Button {
                model.toggleSidebarCollapsed()
            } label: {
                Label(
                    model.isSidebarCollapsed
                        ? model.localized(english: "Expand Sidebar", chinese: "展开侧边栏")
                        : model.localized(english: "Collapse Sidebar", chinese: "收起侧边栏"),
                    systemImage: "sidebar.left"
                )
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Divider()

            Button {
                model.revealCurrentFileInFinder()
            } label: {
                Label(model.localized(english: "Show in Finder", chinese: "在 Finder 中显示"), systemImage: "finder")
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!model.canActOnCurrentSessionFile)

            Button {
                model.copyCurrentFilePathToPasteboard()
            } label: {
                Label(model.localized(english: "Copy Path", chinese: "复制路径"), systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!model.canActOnCurrentSessionFile)

            Divider()

            Button {
                model.presentTutorialHub()
            } label: {
                Label(model.localized(english: "Start Tutorial", chinese: "开始教程"), systemImage: "graduationcap.fill")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button {
                model.returnExternalHandoffToIData()
            } label: {
                Label(model.localized(english: "Open Handoff File in iData", chinese: "用 iData 打开转交文件"), systemImage: "arrow.uturn.backward.circle.fill")
            }
            .disabled(model.externalHandoffNotice == nil)
        }

        CommandGroup(replacing: .help) {
            Button(isChinese ? "iData 帮助" : "iData Help") {
                model.isHelpPresented = true
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }
    }
}
