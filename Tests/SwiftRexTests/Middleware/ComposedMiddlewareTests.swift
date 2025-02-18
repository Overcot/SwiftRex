@testable import SwiftRex
import XCTest

class ComposedMiddlewareTests: XCTestCase {
    func testComposedMiddlewareAction() {
        var sut = ComposedMiddleware<AppAction, AppAction, TestState>()
        var newActions = [AppAction]()
        let originalActions: [AppAction] = [.foo, .bar(.alpha), .bar(.alpha), .bar(.bravo), .bar(.echo), .foo]
        var originalActionsReceived: [(middlewareName: String, action: AppAction)] = []
        let lastInChainWasCalledExpectation = self.expectation(description: "last in chain should have been called")
        let expectedNewActions: [AppAction] = [
            .foo, .foo, .bar(.alpha), .bar(.alpha), .bar(.alpha), .bar(.alpha),
            .bar(.bravo), .bar(.bravo), .bar(.echo), .bar(.echo), .foo, .foo
        ]

        lastInChainWasCalledExpectation.expectedFulfillmentCount = expectedNewActions.count

        ["m1", "m2"]
            .lazy
            .map { name in
                let middleware = IsoMiddlewareMock<AppAction, TestState>()
                middleware.handleActionFromStateClosure = { action, dispatcher, _ in
                    originalActionsReceived.append((middlewareName: name, action: action))
                    XCTAssertEqual("file_1", dispatcher.file)
                    XCTAssertEqual("function_1", dispatcher.function)
                    XCTAssertEqual(1, dispatcher.line)
                    XCTAssertEqual("info_1", dispatcher.info)
                    return IO { output in
                        output.dispatch(action, from: .init(file: "file_2", function: "function_2", line: 2, info: "info_2"))
                        lastInChainWasCalledExpectation.fulfill()
                    }
                }
                return middleware
            }
            .forEach { sut.append(middleware: $0 as IsoMiddlewareMock<AppAction, TestState>) }

        originalActions.forEach { originalAction in
            let io = sut.handle(
                action: originalAction,
                from: .init(file: "file_1", function: "function_1", line: 1, info: "info_1"),
                state: { TestState() }
            )
            io.runIO(.init({ dispatchedAction in newActions.append(dispatchedAction.action) }))
        }

        wait(for: [lastInChainWasCalledExpectation], timeout: 3)

        XCTAssertEqual(newActions, expectedNewActions)
        XCTAssertEqual(originalActionsReceived.filter { $0.middlewareName == "m1" }.map { $0.action }, originalActions)
        XCTAssertEqual(originalActionsReceived.filter { $0.middlewareName == "m2" }.map { $0.action }, originalActions)
    }

    func testMiddlewareActionHandlerPropagationFromComposedMiddlewareToChildrenComposedViaAppend() {
        let shouldReceiveContext = expectation(description: "context should have been received")
        shouldReceiveContext.expectedFulfillmentCount = 4
        var composedMiddlewares = ComposedMiddleware<AppAction, AppAction, TestState>()
        ["m1", "m2", "m3", "m4"]
            .map { _ -> IsoMiddlewareMock<AppAction, TestState> in
                let middleware = IsoMiddlewareMock<AppAction, TestState>()
                middleware.receiveContextGetStateOutputClosure = { _, _ in
                    shouldReceiveContext.fulfill()
                }
                middleware.handleActionFromStateClosure = { _, _, _ in .pure() }
                return middleware
            }.forEach { middleware in
                composedMiddlewares.append(middleware: middleware)
            }

        composedMiddlewares.receiveContext(getState: { TestState() }, output: .init({ _ in }))
        wait(for: [shouldReceiveContext], timeout: 0.1)
    }

    func testComposedMiddlewareWhenLeftIsAlreadyComposedKeepsFlat() {
        let m1ShouldBeCalled = expectation(description: "first middleware should have been called")
        let m2ShouldBeCalled = expectation(description: "second middleware should have been called")
        let m3ShouldBeCalled = expectation(description: "third middleware should have been called")
        let m1ShouldBeCalledAfterReducer = expectation(description: "first middleware should have been called after reducer")
        let m2ShouldBeCalledAfterReducer = expectation(description: "second middleware should have been called after reducer")
        let m3ShouldBeCalledAfterReducer = expectation(description: "third middleware should have been called after reducer")

        var lhs = ComposedMiddleware<String, String, String>()
        let lhsM1 = MiddlewareMock<String, String, String>()
        lhsM1.handleActionFromStateClosure = { _, _, _ in
            m1ShouldBeCalled.fulfill()
            return IO { _ in m1ShouldBeCalledAfterReducer.fulfill() }
        }
        let lhsM2 = MiddlewareMock<String, String, String>()
        lhsM2.handleActionFromStateClosure = { _, _, _ in
            m2ShouldBeCalled.fulfill()
            return IO { _ in m2ShouldBeCalledAfterReducer.fulfill() }
        }
        lhs.append(middleware: lhsM1)
        lhs.append(middleware: lhsM2)

        let rhs = MiddlewareMock<String, String, String>()
        rhs.handleActionFromStateClosure = { _, _, _ in
            m3ShouldBeCalled.fulfill()
            return IO { _ in m3ShouldBeCalledAfterReducer.fulfill() }
        }

        let sut = lhs <> rhs

        XCTAssertEqual(sut.middlewares.count, 3)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                m1ShouldBeCalled,
                m2ShouldBeCalled,
                m3ShouldBeCalled,
                m3ShouldBeCalledAfterReducer,
                m2ShouldBeCalledAfterReducer,
                m1ShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenRightIsAlreadyComposedKeepsFlat() {
        let m1ShouldBeCalled = expectation(description: "first middleware should have been called")
        let m2ShouldBeCalled = expectation(description: "second middleware should have been called")
        let m3ShouldBeCalled = expectation(description: "third middleware should have been called")
        let m1ShouldBeCalledAfterReducer = expectation(description: "first middleware should have been called after reducer")
        let m2ShouldBeCalledAfterReducer = expectation(description: "second middleware should have been called after reducer")
        let m3ShouldBeCalledAfterReducer = expectation(description: "third middleware should have been called after reducer")

        let lhs = MiddlewareMock<String, String, String>()
        lhs.handleActionFromStateClosure = { _, _, _ in
            m1ShouldBeCalled.fulfill()
            return IO { _ in m1ShouldBeCalledAfterReducer.fulfill() }
        }

        var rhs = ComposedMiddleware<String, String, String>()
        let rhsM1 = MiddlewareMock<String, String, String>()
        rhsM1.handleActionFromStateClosure = { _, _, _ in
            m2ShouldBeCalled.fulfill()
            return IO { _ in m2ShouldBeCalledAfterReducer.fulfill() }
        }
        let rhsM2 = MiddlewareMock<String, String, String>()
        rhsM2.handleActionFromStateClosure = { _, _, _ in
            m3ShouldBeCalled.fulfill()
            return IO { _ in m3ShouldBeCalledAfterReducer.fulfill() }
        }

        rhs.append(middleware: rhsM1)
        rhs.append(middleware: rhsM2)

        let sut = lhs <> rhs

        XCTAssertEqual(sut.middlewares.count, 3)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                m1ShouldBeCalled,
                m2ShouldBeCalled,
                m3ShouldBeCalled,
                m3ShouldBeCalledAfterReducer,
                m2ShouldBeCalledAfterReducer,
                m1ShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenLeftIsAlreadyComposedButErasedKeepsFlat() {
        let m1ShouldBeCalled = expectation(description: "first middleware should have been called")
        let m2ShouldBeCalled = expectation(description: "second middleware should have been called")
        let m3ShouldBeCalled = expectation(description: "third middleware should have been called")
        let m1ShouldBeCalledAfterReducer = expectation(description: "first middleware should have been called after reducer")
        let m2ShouldBeCalledAfterReducer = expectation(description: "second middleware should have been called after reducer")
        let m3ShouldBeCalledAfterReducer = expectation(description: "third middleware should have been called after reducer")

        var lhs = ComposedMiddleware<String, String, String>()
        let lhsM1 = MiddlewareMock<String, String, String>()
        lhsM1.handleActionFromStateClosure = { _, _, _ in
            m1ShouldBeCalled.fulfill()
            return IO { _ in m1ShouldBeCalledAfterReducer.fulfill() }
        }
        let lhsM2 = MiddlewareMock<String, String, String>()
        lhsM2.handleActionFromStateClosure = { _, _, _ in
            m2ShouldBeCalled.fulfill()
            return IO { _ in m2ShouldBeCalledAfterReducer.fulfill() }
        }
        lhs.append(middleware: lhsM1)
        lhs.append(middleware: lhsM2)

        let rhs = MiddlewareMock<String, String, String>()
        rhs.handleActionFromStateClosure = { _, _, _ in
            m3ShouldBeCalled.fulfill()
            return IO { _ in m3ShouldBeCalledAfterReducer.fulfill() }
        }

        let sut = lhs.eraseToAnyMiddleware() <> rhs.eraseToAnyMiddleware()

        XCTAssertEqual(sut.middlewares.count, 3)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                m1ShouldBeCalled,
                m2ShouldBeCalled,
                m3ShouldBeCalled,
                m3ShouldBeCalledAfterReducer,
                m2ShouldBeCalledAfterReducer,
                m1ShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenRightIsAlreadyComposedButErasedKeepsFlat() {
        let m1ShouldBeCalled = expectation(description: "first middleware should have been called")
        let m2ShouldBeCalled = expectation(description: "second middleware should have been called")
        let m3ShouldBeCalled = expectation(description: "third middleware should have been called")
        let m1ShouldBeCalledAfterReducer = expectation(description: "first middleware should have been called after reducer")
        let m2ShouldBeCalledAfterReducer = expectation(description: "second middleware should have been called after reducer")
        let m3ShouldBeCalledAfterReducer = expectation(description: "third middleware should have been called after reducer")

        let lhs = MiddlewareMock<String, String, String>()
        lhs.handleActionFromStateClosure = { _, _, _ in
            m1ShouldBeCalled.fulfill()
            return IO { _ in m1ShouldBeCalledAfterReducer.fulfill() }
        }

        var rhs = ComposedMiddleware<String, String, String>()
        let rhsM1 = MiddlewareMock<String, String, String>()
        rhsM1.handleActionFromStateClosure = { _, _, _ in
            m2ShouldBeCalled.fulfill()
            return IO { _ in m2ShouldBeCalledAfterReducer.fulfill() }
        }
        let rhsM2 = MiddlewareMock<String, String, String>()
        rhsM2.handleActionFromStateClosure = { _, _, _ in
            m3ShouldBeCalled.fulfill()
            return IO { _ in m3ShouldBeCalledAfterReducer.fulfill() }
        }

        rhs.append(middleware: rhsM1)
        rhs.append(middleware: rhsM2)

        let sut = lhs.eraseToAnyMiddleware() <> rhs.eraseToAnyMiddleware()

        XCTAssertEqual(sut.middlewares.count, 3)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                m1ShouldBeCalled,
                m2ShouldBeCalled,
                m3ShouldBeCalled,
                m3ShouldBeCalledAfterReducer,
                m2ShouldBeCalledAfterReducer,
                m1ShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenLeftIsIdentityIgnoresIt() {
        let middlewareShouldBeCalled = expectation(description: "middleware should have been called")
        let middlewareShouldBeCalledAfterReducer = expectation(description: "middleware should have been called after reducer")

        let lhs = IdentityMiddleware<String, String, String>()
        let rhs = MiddlewareMock<String, String, String>()
        rhs.handleActionFromStateClosure = { _, _, _ in
            middlewareShouldBeCalled.fulfill()
            return IO { _ in middlewareShouldBeCalledAfterReducer.fulfill() }
        }

        let sut = lhs <> rhs

        XCTAssertEqual(sut.middlewares.count, 1)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                middlewareShouldBeCalled,
                middlewareShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenRightIsIdentityIgnoresIt() {
        let middlewareShouldBeCalled = expectation(description: "middleware should have been called")
        let middlewareShouldBeCalledAfterReducer = expectation(description: "middleware should have been called after reducer")

        let lhs = MiddlewareMock<String, String, String>()
        lhs.handleActionFromStateClosure = { _, _, _ in
            middlewareShouldBeCalled.fulfill()
            return IO { _ in middlewareShouldBeCalledAfterReducer.fulfill() }
        }
        let rhs = IdentityMiddleware<String, String, String>()

        let sut = lhs <> rhs

        XCTAssertEqual(sut.middlewares.count, 1)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                middlewareShouldBeCalled,
                middlewareShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenLeftIsIdentityButErasedIgnoresIt() {
        let middlewareShouldBeCalled = expectation(description: "middleware should have been called")
        let middlewareShouldBeCalledAfterReducer = expectation(description: "middleware should have been called after reducer")

        let lhs = IdentityMiddleware<String, String, String>()
        let rhs = MiddlewareMock<String, String, String>()
        rhs.handleActionFromStateClosure = { _, _, _ in
            middlewareShouldBeCalled.fulfill()
            return IO { _ in middlewareShouldBeCalledAfterReducer.fulfill() }
        }

        let sut = lhs.eraseToAnyMiddleware() <> rhs.eraseToAnyMiddleware()

        XCTAssertEqual(sut.middlewares.count, 1)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                middlewareShouldBeCalled,
                middlewareShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareWhenRightIsIdentityButErasedIgnoresIt() {
        let middlewareShouldBeCalled = expectation(description: "middleware should have been called")
        let middlewareShouldBeCalledAfterReducer = expectation(description: "middleware should have been called after reducer")

        let lhs = MiddlewareMock<String, String, String>()
        lhs.handleActionFromStateClosure = { _, _, _ in
            middlewareShouldBeCalled.fulfill()
            return IO { _ in middlewareShouldBeCalledAfterReducer.fulfill() }
        }
        let rhs = IdentityMiddleware<String, String, String>()

        let sut = lhs.eraseToAnyMiddleware() <> rhs.eraseToAnyMiddleware()

        XCTAssertEqual(sut.middlewares.count, 1)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                middlewareShouldBeCalled,
                middlewareShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func testComposedMiddlewareCannotAppendIdentityEvenErased() {
        let middlewareShouldBeCalled = expectation(description: "middleware should have been called")
        let middlewareShouldBeCalledAfterReducer = expectation(description: "middleware should have been called after reducer")

        let lhs = MiddlewareMock<String, String, String>()
        lhs.handleActionFromStateClosure = { _, _, _ in
            middlewareShouldBeCalled.fulfill()
            return IO { _ in middlewareShouldBeCalledAfterReducer.fulfill() }
        }

        var sut = lhs.eraseToAnyMiddleware() <> IdentityMiddleware<String, String, String>()
        sut.append(middleware: IdentityMiddleware<String, String, String>())
        sut.append(middleware: IdentityMiddleware<String, String, String>())
        sut.append(middleware: IdentityMiddleware<String, String, String>().eraseToAnyMiddleware())
        sut.append(middleware: IdentityMiddleware<String, String, String>().eraseToAnyMiddleware())
        sut.append(middleware: AnyMiddleware(IdentityMiddleware<String, String, String>()))
        sut.append(middleware: AnyMiddleware(IdentityMiddleware<String, String, String>()))
        sut.append(middleware: AnyMiddleware(IdentityMiddleware<String, String, String>()).eraseToAnyMiddleware())
        sut.append(middleware: AnyMiddleware(IdentityMiddleware<String, String, String>()).eraseToAnyMiddleware())
        sut.append(middleware: IdentityMiddleware<String, String, String>().eraseToAnyMiddleware().eraseToAnyMiddleware())
        sut.append(middleware:
            IdentityMiddleware<String, String, String>().eraseToAnyMiddleware().eraseToAnyMiddleware()
            <> IdentityMiddleware<String, String, String>().eraseToAnyMiddleware().eraseToAnyMiddleware()
            <> AnyMiddleware(IdentityMiddleware<String, String, String>().eraseToAnyMiddleware())
        )

        XCTAssertEqual(sut.middlewares.count, 1)

        let io = sut.handle(action: "", from: .here(), state: { .init() })
        io.runIO(.init { _ in })

        wait(
            for: [
                middlewareShouldBeCalled,
                middlewareShouldBeCalledAfterReducer
            ],
            timeout: 0.1,
            enforceOrder: true
        )
    }
}
