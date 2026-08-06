import Foundation
import Testing

struct PreferencesViewTests {
    @Test
    func settingsUseNativeTabbedStructure() throws {
        let source = try preferencesViewSource()

        #expect(source.contains("TabView(selection: $selectedTab)"))
        #expect(source.contains("case general"))
        #expect(source.contains("case files"))
        #expect(source.contains("case runtime"))
        #expect(source.contains("case updates"))
        #expect(source.contains(".formStyle(.grouped)"))
        #expect(!source.contains("PreferencesCard"))
        #expect(!source.contains("preferencesHero"))
    }

    @Test
    func generalTabKeepsOnlyGlobalPreferencesAndStatus() throws {
        let source = try preferencesViewSource()
        let general = try extractSection(from: source, start: "private func generalTab", end: "private var filesTab")

        #expect(general.contains("Picker(isChinese ? \"语言\""))
        #expect(general.contains("Toggle(isChinese ? \"减少动画\""))
        #expect(general.contains("LabeledContent(isChinese ? \"版本\""))
        #expect(general.contains("LabeledContent(\"VisiData\")"))
    }

    @Test
    func filesTabCombinesHandoffAndDefaultApplications() throws {
        let source = try preferencesViewSource()
        let files = try extractSection(from: source, start: "private var filesTab", end: "private func runtimeTab")

        #expect(files.contains("Toggle("))
        #expect(files.contains("isChinese ? \"转交小文件\" : \"Hand Off Small Files\""))
        #expect(files.contains("isOn: $model.isSmallFileHandoffEnabled"))
        #expect(files.components(separatedBy: ".disabled(!model.isSmallFileHandoffEnabled)").count - 1 == 2)
        #expect(files.contains("model.preferredSmallFileApplicationDisplayName"))
        #expect(files.contains("model.choosePreferredSmallFileApplication()"))
        #expect(files.contains("testSmallFileHandoff()"))
        #expect(files.contains("model.clearPreferredSmallFileApplication()"))
        #expect(files.contains("FormatChip("))
        #expect(files.contains("customAssociationInput"))
        #expect(files.contains("LabeledContent(isChinese ? \"自定义后缀\" : \"Custom Suffix\")"))
        #expect(files.contains("prompt: Text(isChinese ? \"例如 .bed\" : \"e.g. .bed\")"))
        #expect(!files.contains("TextField(\".vcf\", text: $customAssociationInput)"))
        #expect(files.contains("点击格式设为 iData；再次点击恢复原应用。"))
    }

    @Test
    func runtimeAndUpdatesExposeDirectActions() throws {
        let source = try preferencesViewSource()
        let runtime = try extractSection(from: source, start: "private func runtimeTab", end: "private var updatesTab")
        let updates = try extractSection(from: source, start: "private var updatesTab", end: "private func visiDataStatusTitle")

        #expect(runtime.contains("model.chooseVDExecutable()"))
        #expect(runtime.contains("model.vdExecutablePath = \"\""))
        #expect(runtime.contains("model.runVisiDataOneClickSetup()"))
        #expect(updates.contains("updater.checkForUpdates()"))
        #expect(updates.contains("updater.releasesURL"))
    }

    @Test
    func dependencyStateIsResolvedOncePerBodyRecomputation() throws {
        let source = try preferencesViewSource()

        #expect(source.components(separatedBy: "model.visiDataDependencyState").count - 1 == 1)
        #expect(source.contains("generalTab(dependencyState: dependencyState)"))
        #expect(source.contains("runtimeTab(dependencyState: dependencyState)"))
        #expect(source.contains("visiDataStatusTitle(for: dependencyState)"))
        #expect(source.contains("model.visiDataDependencySummary(for: dependencyState)"))
    }

    @Test
    func chineseCopyIsCompactAndTaskFocused() throws {
        let source = try preferencesViewSource()

        for text in [
            "通用",
            "文件",
            "小文件",
            "默认打开方式",
            "选择应用…",
            "测试打开",
            "恢复默认",
            "自动检测",
            "检查更新",
            "查看发布页",
        ] {
            #expect(source.contains(text))
        }
    }
}

private func preferencesViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/iData/PreferencesView.swift"),
        encoding: .utf8
    )
}

private func extractSection(from source: String, start: String, end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw NSError(domain: "PreferencesViewTests", code: 1)
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw NSError(domain: "PreferencesViewTests", code: 2)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
