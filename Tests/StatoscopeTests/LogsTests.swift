//
//  LogsTests.swift
//  
//
//  Created by Sergi Hernanz on 18/2/24.
//

import Foundation
import XCTest
@testable import Statoscope
import StatoscopeTesting
import Combine

final class LogsTests: XCTestCase {

    private enum ParentChild {
        final class Parent: Statostore {
            var loading: Bool = false
            @Subscope var child: Child?
            typealias When = Void
            func update(_ when: When) throws { }
        }

        final class Child: Statostore {
            var showingChild: Bool = false
            typealias When = Void
            func update(_ when: Void) throws { }
        }
    }

    func testLogState() throws {
        let sut = ParentChild.Parent()
        let expectedDescription = """
Parent(
  loading: false
  _child: nil
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }

    func testLogChildren() throws {
        let sut = ParentChild.Parent()
        sut.child = ParentChild.Child()
        let expectedDescription = """
Parent(
  loading: false
  _child: Child(
    showingChild: false
  )
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }

    private enum ParentChildGrandSon {
        final class Parent: Statostore {
            var loading: Bool = false
            @Subscope var child: Child?
            typealias When = Void
            func update(_ when: Void) throws {}
        }

        final class Child: Statostore {
            var showingChild: Bool = false
            @Subscope var grandson: GrandSon?
            typealias When = Void
            func update(_ when: Void) throws { }
        }

        final class GrandSon: Statostore {
            var someVar: String = "someVarValue"
            typealias When = Void
            func update(_ when: Void) throws { }
        }
    }

    func testLogChildrenGrandson() throws {
        let sut = ParentChildGrandSon.Parent()
        sut.child = ParentChildGrandSon.Child()
        sut.child?.grandson = ParentChildGrandSon.GrandSon()
        let expectedDescription = """
Parent(
  loading: false
  _child: Child(
    showingChild: false
    _grandson: GrandSon(
      someVar: someVarValue
    )
  )
)
"""
        let description = String(describing: sut)
        XCTAssertEqual(description, expectedDescription)
    }

    private struct MyEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        }
    }

    final class ScopeWithEffect: Statostore {
        var loading: Bool = false
        enum When {
            case sendWaitEffect
            case anyEffectCompleted
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect:
                loading = true
                effectsState.enqueue(MyEffect(milliseconds: 1000).map {
                    .anyEffectCompleted
                })
            case .anyEffectCompleted:
                loading = false
            }
        }
    }

    func testLogEffects() throws {
        let sut = ScopeWithEffect()
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: false
)
""")
        sut.send(.sendWaitEffect)
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: true
  effects: [
  MyEffect(milliseconds: 1000)
  ]
)
""")
        sut.send(.sendWaitEffect)
        XCTAssertEqual(
            String(describing: sut),
"""
ScopeWithEffect(
  loading: true
  effects: [
  MyEffect(milliseconds: 1000)
  MyEffect(milliseconds: 1000)
  ]
)
""")
    }

    private enum ParentChildImplemented {
        final class Parent: Statostore {
            var loading: Bool = false
            enum When {
                case systemLoadedScope
                case networkDidFinish
                case navigateToChild
                case childAppeared(Bool)
            }
            @Subscope var child: Child?
            func update(_ when: When) throws {
                switch when {
                case .systemLoadedScope:
                    loading = true
                case .networkDidFinish:
                    loading = false
                case .navigateToChild:
                    child = Child()
                case .childAppeared(let appeared):
                    if appeared {
                        assert(child != nil)
                        return
                    }
                    child = nil
                }
            }
        }

        final class Child: Statostore {
            var showingChild: Bool = false
            enum When {
                case didAppear
            }
            func update(_ when: When) throws {
                switch when {
                case .didAppear:
                    showingChild = true
                }
            }
        }
    }

    func testStoreLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { _, log in
            logs.append(log.replacing(regex) { _ in "0xF"})
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.systemLoadedScope)
        XCTAssertEqual(logs, [
            "[SCOPE]: Parent (0xF):  systemLoadedScope",
            "[SCOPE]: Parent (0xF):  [STATE] Parent(",
            "[SCOPE]: Parent (0xF):  [STATE]   loading: false",
            "[SCOPE]: Parent (0xF):  [STATE]   _child: nil",
            "[SCOPE]: Parent (0xF):  [STATE] )",
            "[SCOPE]: Parent (0xF):  [STATE] Parent(",
            "[SCOPE]: Parent (0xF):  [STATE]   loading: true",
            "[SCOPE]: Parent (0xF):  [STATE]   _child: nil",
            "[SCOPE]: Parent (0xF):  [STATE] )",
            "[SCOPE]: Parent (0xF):  [STATE] [DIFF] -   loading: false",
            "[SCOPE]: Parent (0xF):  [STATE] [DIFF] +   loading: true"
        ])
    }

    func testChildStoreLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { _, log in
            if log.contains(" Child ") {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.navigateToChild)
        sut.child?.send(.didAppear)
        XCTAssertEqual(logs, [
            "[SCOPE]: Child (0xF):  didAppear",
            "[SCOPE]: Child (0xF):  [STATE] Child(",
            "[SCOPE]: Child (0xF):  [STATE]   showingChild: false",
            "[SCOPE]: Child (0xF):  [STATE] )",
            "[SCOPE]: Child (0xF):  [STATE] Child(",
            "[SCOPE]: Child (0xF):  [STATE]   showingChild: true",
            "[SCOPE]: Child (0xF):  [STATE] )",
            "[SCOPE]: Child (0xF):  [STATE] [DIFF] -   showingChild: false",
            "[SCOPE]: Child (0xF):  [STATE] [DIFF] +   showingChild: true"
        ])
    }

    private enum PublishedLogs {
        final class WithPublishedProperties: Statostore, ObservableObject {
            @Published var loading: Bool = false
            enum When {
                case systemLoadedScope
                case networkDidFinish
            }
            func update(_ when: When) throws {
                switch when {
                case .systemLoadedScope:
                    loading = true
                case .networkDidFinish:
                    loading = false
                }
            }
            var debugLoading: Bool { loading }
        }
    }

    func testPublishedPropertiesLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            if level == .stateDiff {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = PublishedLogs.WithPublishedProperties()
        sut.send(.systemLoadedScope)
        XCTAssertEqual(logs, [
            "[SCOPE]: WithPublishedProperties (0xF):  [STATE] [DIFF] -   _loading: false",
            "[SCOPE]: WithPublishedProperties (0xF):  [STATE] [DIFF] +   _loading: true"
        ])
    }

    func testPublishedPropertiesLogsWithSink() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            if level == .stateDiff {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = PublishedLogs.WithPublishedProperties()
        var cancellable: AnyCancellable? = sut.objectWillChange.sink { _ in
            // to nothing
        }
        sut.send(.systemLoadedScope)
        XCTAssertEqual(logs, [
            "[SCOPE]: WithPublishedProperties (0xF):  [STATE] [DIFF] -   _loading: false",
            "[SCOPE]: WithPublishedProperties (0xF):  [STATE] [DIFF] +   _loading: true"
        ])
        XCTAssertNotNil(cancellable, "shutting up compiler warnings")
        cancellable = nil
    }
}
