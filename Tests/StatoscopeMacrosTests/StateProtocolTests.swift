//
//  File.swift
//
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

protocol State {
    var someVar: String { get }
}
class SomeScope {
    let someVar: String = ""
}

final class StateProtocolMacroTests: XCTestCase {
    func testCreateStateProtocol() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @StateProtocol
            class SomeScope {
            let someVar: String
            var someMutableVar: SomeStruct
            }
            """#,
            expandedSource: #"""
            class SomeScope {
            let someVar: String
            var someMutableVar: SomeStruct
            }

            protocol SomeScopeState {
                var someVar: String {
                    get
                }
                var someMutableVar: SomeStruct {
                    get
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testCreateStateProtocolWithPublished() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @StateProtocol
            class SomeScope {
            let someVar: String
            @Published var somePublishedVar: Int
            }
            """#,
            expandedSource: #"""
            class SomeScope {
            let someVar: String
            @Published var somePublishedVar: Int
            }

            protocol SomeScopeState {
                var someVar: String {
                    get
                }
                var somePublishedVar: Int {
                    get
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testCreateStateProtocolDoNotExposePrivate() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @StateProtocol
            class SomeScope {
            let someVar: String
            public let somePublicVar: String
            private let somePrivateVar: String
            private var someMutableVar: SomeStruct
            }
            """#,
            expandedSource: #"""
            class SomeScope {
            let someVar: String
            public let somePublicVar: String
            private let somePrivateVar: String
            private var someMutableVar: SomeStruct
            }

            protocol SomeScopeState {
                var someVar: String {
                    get
                }
                var somePublicVar: String {
                    get
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
