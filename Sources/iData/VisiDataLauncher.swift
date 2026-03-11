import Foundation
#if canImport(iDataCore)
import iDataCore
#endif

struct VisiDataLaunchPrereflight {
    func resolveExecutable(explicitVDPath: String?) throws -> URL {
        guard let vdURL = VDExecutableLocator.resolve(
            explicitPath: explicitVDPath,
            environmentPath: ProcessInfo.processInfo.environment["PATH"] ?? "",
            checker: LocalExecutableChecker()
        ) else {
            throw LaunchError.visiDataNotFound
        }

        return vdURL
    }
}

enum LaunchError: LocalizedError {
    case fileMissing(String)
    case visiDataNotFound
    case pseudoTerminalUnavailable(String)
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .fileMissing(path):
            AppModel.localized(
                english: "The selected file no longer exists: \(path)",
                chinese: "所选文件已不存在：\(path)"
            )
        case .visiDataNotFound:
            AppModel.localized(
                english: "Could not find `vd`. Install VisiData with `brew install visidata`, or set its executable path in Preferences.",
                chinese: "找不到 `vd`。请用 `brew install visidata` 安装 VisiData，或在偏好设置中指定其可执行文件路径。"
            )
        case let .pseudoTerminalUnavailable(message):
            AppModel.localized(
                english: "Could not create a terminal session for VisiData: \(message)",
                chinese: "无法为 VisiData 创建终端会话：\(message)"
            )
        case let .processLaunchFailed(message):
            AppModel.localized(
                english: "Could not launch VisiData inside iData: \(message)",
                chinese: "无法在 iData 内启动 VisiData：\(message)"
            )
        }
    }
}

func systemErrorDescription(_ errorCode: Int32) -> String {
    guard let posixError = POSIXErrorCode(rawValue: errorCode) else {
        return String(cString: strerror(errorCode))
    }

    return POSIXError(posixError).localizedDescription
}
