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

// swiftlint:disable nesting
final class LogsTests: XCTestCase {

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

    @available(iOS 16.0, *)
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

    @available(iOS 16.0, *)
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

    @available(iOS 16.0, *)
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

    @available(iOS 16.0, *)
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
// swiftlint:enable nesting
