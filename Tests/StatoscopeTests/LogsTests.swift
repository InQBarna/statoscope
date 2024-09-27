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
    
    struct ExpLog: Equatable {
        let level: LogLevel
        let message: String
        init(_ level: LogLevel, _ message: String) {
            self.level = level
            self.message = message
        }
    }
    
    struct MissingInjectable: Injectable {
        static var defaultValue = LogsTests.MissingInjectable()
        let id: UUID = UUID()
    }

    private enum ParentChildImplemented {
        final class Parent: Statostore {
            var loading: Bool = false
            enum When {
                case systemLoadedScope
                struct DTO {
                    let message: String
                }
                case networkDidFinish(DTO)
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
                case checkMissingInjection
            }
            @Injected var missing: MissingInjectable
            func update(_ when: When) throws {
                switch when {
                case .didAppear:
                    showingChild = true
                case .checkMissingInjection:
                    _ = String(describing: missing)
                }
            }
        }
    }

    @available(iOS 16.0, *)
    func testStoreLogs() throws {
        var logs: [ExpLog] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            logs.append(
                ExpLog(level, log.replacing(regex) { _ in "0xF"})
            )
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.systemLoadedScope)
        try XCTAssertEqualDiff(logs, [
            ExpLog(.when, "Parent (0xF): systemLoadedScope"),
            ExpLog(.state, """
            Parent (0xF): Parent(
              loading: false
              _child: nil
            )
            """),
            ExpLog(.state, """
            Parent (0xF): Parent(
              loading: true
              _child: nil
            )
            """),
            ExpLog(.stateDiff, """
            Parent (0xF):
            -   loading: false
            +   loading: true
            """)
        ])
    }

    @available(iOS 16.0, *)
    func testChildStoreLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { _, log in
            logs.append(log.replacing(regex) { _ in "0xF"})
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.navigateToChild)
        sut.child?.send(.didAppear)
        try XCTAssertEqualDiff(logs, [
            "Parent (0xF): navigateToChild",
            """
            Parent (0xF): Parent(
              loading: false
              _child: nil
            )
            """,
            """
            Parent (0xF): Parent(
              loading: false
              _child: Child(
                showingChild: false
              )
            )
            """,
            """
            Parent (0xF):
            -   _child: nil
            +   _child: Child(
            +     showingChild: false
            +   )
            """,
            "Child (0xF): didAppear",
            """
            Child (0xF): Child(
              showingChild: false
            )
            """,
            """
            Child (0xF): Child(
              showingChild: true
            )
            """,
            """
            Child (0xF):
            -   showingChild: false
            +   showingChild: true
            """
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
        try XCTAssertEqualDiff(logs, [
            """
            WithPublishedProperties (0xF):
            -   _loading: false
            +   _loading: true
            """
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
        try XCTAssertEqualDiff(logs, [
            """
            WithPublishedProperties (0xF):
            -   _loading: false
            +   _loading: true
            """
        ])
        XCTAssertNotNil(cancellable, "shutting up compiler warnings")
        cancellable = nil
    }
    
    @available(iOS 16.0, *)
    func testStoreWhenAssociatedValueLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            if level == .when {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.networkDidFinish(ParentChildImplemented.Parent.When.DTO(message: "message")))
        try XCTAssertEqualDiff(logs, [
            """
            Parent (0xF): 
              networkDidFinish: DTO(
                message: message
              )
            """
        ])
    }
    
    @available(iOS 16.0, *)
    func testMisingInjectionLogs() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            if level == .errors {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = ParentChildImplemented.Parent()
        sut.send(.navigateToChild)
        sut.child?.send(.checkMissingInjection)
        XCTAssertEqual(logs.count, 1)
        let firstLog = try XCTUnwrap(logs.first)
        try XCTAssertEqualDiff(
            firstLog.split(separator: String.newLine),
            """
            💉 ⁉️ Injection failed at Child (0xF) \\Child._missing: MissingInjectable
            ⚠️ Please note Injected properties from ancestor scopes can\'t be accessed until Scope is assigned to a Subscope property wrapper
            🌳
             Parent (0xF)
               Child (0xF)
            """.split(separator: String.newLine)
        )
    }
    
    @available(iOS 16.0, *)
    func testInjectedAddedLog() throws {
        var logs: [String] = []
        let regex: Regex = try Regex("(0x[0-9a-f]*)")
        StatoscopeLogger.logReplacement = { level, log in
            if level == .injection {
                logs.append(log.replacing(regex) { _ in "0xF"})
            }
        }
        let sut = ParentChildImplemented.Parent()
            .injectObject(MissingInjectable())
        sut.send(.navigateToChild)
        sut.child?.send(.checkMissingInjection)
        XCTAssertEqual(logs.count, 1)
        let firstLog = try XCTUnwrap(logs.first)
        try XCTAssertEqualDiff(
            firstLog.split(separator: String.newLine),
            """
             Parent (0xF)
               💉 MissingInjectable
            """.split(separator: String.newLine)
        )
        
        let sut2 = ParentChildImplemented.Parent()
        sut2.send(.navigateToChild)
        sut2.child?.send(.checkMissingInjection)
        sut2.injectObject(MissingInjectable())
        XCTAssertEqual(logs.count, 2)
        let firstLog2 = try XCTUnwrap(logs.last)
        try XCTAssertEqualDiff(
            firstLog2.split(separator: String.newLine),
            """
             Parent (0xF)
               💉 MissingInjectable
               Child (0xF)
            """.split(separator: String.newLine)
        )
    }
}
// swiftlint:enable nesting

