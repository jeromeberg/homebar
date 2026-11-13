import Foundation
import Testing
@testable import HomeBarCore

@MainActor
struct PingTests {
    @Test(arguments: [false, true])
    /** Preserve the first ping result when later callbacks repeat or arrive concurrently. */
    func repeatedCompletion(firstFails: Bool) async {
        do {
            try await URLSessionTransport.waitForPong { complete in
                complete(firstFails ? URLError(.networkConnectionLost) : nil)
                DispatchQueue.concurrentPerform(iterations: 10) { index in
                    complete(index.isMultiple(of: 2) ? nil : URLError(.cancelled))
                }
            }
            #expect(!firstFails)
        } catch {
            #expect(firstFails)
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
    }
}
