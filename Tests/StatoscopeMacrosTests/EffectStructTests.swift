//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(StatoscopeMacros)
import StatoscopeMacros

let testMacros: [String: Macro.Type] = [
    "EffectStructMacro": EffectStructMacro.self,
    "StateProtocol": StateProtocolMacro.self,
    "CaseAssociatedGet": CaseAssociatedGetMacro.self
]
#endif

final class StatoscopeMacrosTests: XCTestCase {

    func testCreateEffectMacroWithNoArguments() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStructMacro
                func methodName() -> Int {
                    return 2
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func methodName() -> Int {
                    return 2
                }

                struct MethodNameEffect: Effect, Equatable {
                    func runEffect() async throws -> Int {
                        try await methodName()
                    }
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testCreateEffectMacro() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStructMacro
                func c(a: Int, for b: String, _ value: Double) -> Int {
                    return 2
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func c(a: Int, for b: String, _ value: Double) -> Int {
                    return 2
                }

                struct CEffect: Effect, Equatable {
                    let a: Int
                    let b: String
                    let value: Double
                    func runEffect() async throws -> Int {
                        try await c(a: a, for : b, _ : value)
                    }
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testGenericReturnTypeMethod() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @EffectStructMacro
            func network<Response: Decodable>(request: URLRequest) async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
            """#,
            expandedSource: #"""
            func network<Response: Decodable>(request: URLRequest) async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }

            struct NetworkEffect<Response: Decodable>: Effect, Equatable {
                let request: URLRequest
                func runEffect() async throws -> Response {
                    try await network(request: request)
                }
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testCreateEffectMacroWithActorAnnotation() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStructMacro
                @MainActor
                func methodName() -> Int {
                    return 2
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                @MainActor
                func methodName() -> Int {
                    return 2
                }

                struct MethodNameEffect: Effect, Equatable {
                    @MainActor func runEffect() async throws -> Int {
                        try await methodName()
                    }
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
