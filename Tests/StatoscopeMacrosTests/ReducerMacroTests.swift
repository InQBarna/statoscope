//
//  ReducerMacroTests.swift
//  Statoscope
//
//  Created by Claude Code on 28/2/26.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class ReducerMacroTests: XCTestCase {

    // MARK: - @SuperState Tests

    func testSuperStateMacroExpansion() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            struct ChildState {
                @SuperState var parent: ParentState
            }
            """#,
            expandedSource: #"""
            struct ChildState {
                var parent: ParentState {
                    get {
                        _$parent.wrappedValue
                    }
                }

                var _$parent: SuperStateBinding<ParentState> = .defaultValue
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // Note: @SubState is now a @propertyWrapper (not a macro), so no macro expansion test needed.
    // Integration tests in ReducerTests.swift verify the parent-child state management behavior.

    // MARK: - @Reducer Tests


    func testReducerMissingState() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Reducer
            struct InvalidReducer {
                enum When {
                    case action
                }
            }
            """#,
            expandedSource: #"""
            struct InvalidReducer {
                enum When {
                    case action
                }
            }
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reducer requires a nested 'struct State' definition",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testReducerMissingWhen() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Reducer
            struct InvalidReducer {
                struct State {
                    var value: Int = 0
                }
            }
            """#,
            expandedSource: #"""
            struct InvalidReducer {
                struct State {
                    var value: Int = 0
                }
            }
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reducer requires a nested 'enum When' definition",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - @ReducerInjected Tests

    func testReducerInjectedMacroExpansion() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            struct MyState {
                @ReducerInjected var logger: Logger
            }
            """#,
            expandedSource: #"""
            struct MyState {
                var logger: Logger {
                    get {
                        _$logger.wrappedValue
                    }
                }

                var _$logger: InjectedBinding<Logger> = .defaultValue
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

}
