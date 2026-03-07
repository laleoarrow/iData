import Foundation

public protocol ExecutableChecking {
    func isExecutableFile(atPath path: String) -> Bool
}

public struct LocalExecutableChecker: ExecutableChecking {
    public init() {}

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
