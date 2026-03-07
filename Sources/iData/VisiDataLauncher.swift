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
            "The selected file no longer exists: \(path)"
        case .visiDataNotFound:
            "Could not find `vd`. Install VisiData with `brew install visidata`, or set its executable path in Preferences."
        case let .pseudoTerminalUnavailable(message):
            "Could not create a terminal session for VisiData: \(message)"
        case let .processLaunchFailed(message):
            "Could not launch VisiData inside iData: \(message)"
        }
    }
}

func systemErrorDescription(_ errorCode: Int32) -> String {
    guard let posixError = POSIXErrorCode(rawValue: errorCode) else {
        return String(cString: strerror(errorCode))
    }

    return POSIXError(posixError).localizedDescription
}
