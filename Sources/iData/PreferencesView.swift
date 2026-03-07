import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController

    var body: some View {
        Form {
            Section("VisiData") {
                TextField("/Users/leoarrow/.local/bin/vd", text: $model.vdExecutablePath)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Choose Executable…") {
                        model.chooseVDExecutable()
                    }

                    if !model.vdExecutablePath.isEmpty {
                        Button("Clear") {
                            model.vdExecutablePath = ""
                        }
                    }
                }

                Text("Leave this blank to auto-detect `vd` from PATH. Set it explicitly if you use a custom install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))

                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticallyDownloadsUpdates($0) }
                ))
                .disabled(!updater.automaticallyChecksForUpdates)

                Button("Check for Updates Now") {
                    updater.checkForUpdates()
                }

                Text(updater.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
