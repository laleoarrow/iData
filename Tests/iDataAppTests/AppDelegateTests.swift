import AppKit
import Foundation
import Testing
@testable import iData

@MainActor
struct AppDelegateTests {
    @Test
    func appTerminatesWhenLastWindowCloses() {
        let delegate = AppDelegate()
        let shouldTerminate = (delegate as NSApplicationDelegate)
            .applicationShouldTerminateAfterLastWindowClosed?(NSApplication.shared)

        #expect(shouldTerminate == true)
    }
}
