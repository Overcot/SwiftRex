@testable import SwiftRex
import XCTest

class IdentityMiddlewareTests: XCTestCase {
    func testIdentityMiddlewareAction() {
        // Given
        let sut = IdentityMiddleware<AppAction, AppAction, TestState>()
        var getStateCount = 0
        var dispatchActionCount = 0

        let action = AppAction.bar(.delta)

        // Then
        sut.handle(
            action: action,
            from: .here(),
            state: {
                getStateCount += 1
                return TestState()
            }
        ).runIO(.init { _ in
            dispatchActionCount += 1
        })

        // Expect
        XCTAssertEqual(0, dispatchActionCount)
        XCTAssertEqual(0, getStateCount)
    }
}
