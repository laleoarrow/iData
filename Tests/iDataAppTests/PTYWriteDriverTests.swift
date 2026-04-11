import Darwin
import Foundation
import Testing
@testable import iData

struct PTYWriteDriverTests {
    @Test
    func retriesTransientWriteErrorsUntilPayloadIsWritten() {
        var attemptCount = 0
        var sleepCount = 0

        let driver = PTYWriteDriver(
            maxBackoffRetries: 4,
            backoffMicros: 1,
            writeCall: { _, _, count in
                attemptCount += 1
                switch attemptCount {
                case 1:
                    errno = EAGAIN
                    return -1
                case 2:
                    errno = EINTR
                    return -1
                default:
                    return min(2, count)
                }
            },
            sleepCall: { _ in
                sleepCount += 1
            }
        )

        let result = driver.writeAll(
            data: Data("abcde".utf8),
            fileDescriptorProvider: { 7 }
        )

        #expect(result == .completed)
        #expect(sleepCount == 1)
        #expect(attemptCount >= 4)
    }

    @Test
    func failsAfterTransientRetryBudgetIsExhausted() {
        var sleepCount = 0

        let driver = PTYWriteDriver(
            maxBackoffRetries: 2,
            backoffMicros: 1,
            writeCall: { _, _, _ in
                errno = EAGAIN
                return -1
            },
            sleepCall: { _ in
                sleepCount += 1
            }
        )

        let result = driver.writeAll(
            data: Data("payload".utf8),
            fileDescriptorProvider: { 9 }
        )

        #expect(result == .retryBudgetExceeded)
        #expect(sleepCount == 2)
    }

    @Test
    func failsWhenDescriptorDisappearsBeforeWrite() {
        var writeCount = 0

        let driver = PTYWriteDriver(
            maxBackoffRetries: 1,
            backoffMicros: 1,
            writeCall: { _, _, _ in
                writeCount += 1
                return 1
            },
            sleepCall: { _ in }
        )

        let result = driver.writeAll(
            data: Data("x".utf8),
            fileDescriptorProvider: { -1 }
        )

        #expect(result == .descriptorUnavailable)
        #expect(writeCount == 0)
    }
}
