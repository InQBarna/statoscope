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

    // Note: @SuperState and @SubState are now @propertyWrappers (not macros), so no macro expansion
    // tests are needed for them. Integration tests in ReducerTests.swift verify the behavior.

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
