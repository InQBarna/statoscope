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
    "EffectStruct": EffectStructMacro.self,
    "StateProtocol": StateProtocolMacro.self,
    "CaseAssociatedGet": CaseAssociatedGetMacro.self,
    "Copy": CopyMacro.self
]
#endif

final class StatoscopeMacrosTests: XCTestCase {

    func testCreateEffectMacroWithNoArguments() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct
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

                public struct MethodNameEffect: Effect {
                    public func runEffect() async throws -> Int {
                        try await methodName()
                    }
                    public init() {
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

    func testCreateEffectMacroWithNoArgumentsEquatable() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct(equatable: true)
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

                public struct MethodNameEffect: Effect, Equatable {
                    public func runEffect() async throws -> Int {
                        try await methodName()
                    }
                    public init() {
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
                @EffectStruct
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

                public struct CEffect: Effect {
                    let a: Int
                    let b: String
                    let value: Double
                    public func runEffect() async throws -> Int {
                        try await c(a: a, for: b, _: value)
                    }
                    public init(a: Int, for b: String, _ value: Double) {
                        self.a = a
                        self.b = b
                        self.value = value
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

    func testCreateEffectMacroTrim() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct
                func c(
                    a: Int,
                    for b: String,
                    _ value: Double
                ) -> Int {
                    return 2
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func c(
                    a: Int,
                    for b: String,
                    _ value: Double
                ) -> Int {
                    return 2
                }

                public struct CEffect: Effect {
                    let a: Int
                    let b: String
                    let value: Double
                    public func runEffect() async throws -> Int {
                        try await c(a: a, for: b, _: value)
                    }
                    public init(
                            a: Int,
                            for b: String,
                            _ value: Double
                        ) {
                        self.a = a
                        self.b = b
                        self.value = value
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

    func testCreateEffectMacroEquatable() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct(equatable: true)
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

                public struct CEffect: Effect, Equatable {
                    let a: Int
                    let b: String
                    let value: Double
                    public func runEffect() async throws -> Int {
                        try await c(a: a, for: b, _: value)
                    }
                    public init(a: Int, for b: String, _ value: Double) {
                        self.a = a
                        self.b = b
                        self.value = value
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
            @EffectStruct
            func network<Response: Decodable>(request: URLRequest) async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
            """#,
            expandedSource: #"""
            func network<Response: Decodable>(request: URLRequest) async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }

            public struct NetworkEffect<Response: Decodable>: Effect {
                let request: URLRequest
                public func runEffect() async throws -> Response {
                    try await network(request: request)
                }
                public init(request: URLRequest) {
                    self.request = request
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
                @EffectStruct(equatable: false)
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

                public struct MethodNameEffect: Effect {
                    @MainActor public func runEffect() async throws -> Int {
                        try await methodName()
                    }
                    public init() {
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

    func testCreateEffectMacroWithTemplate() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct
                func createDoc<T: Encodable>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func createDoc<T: Encodable>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }

                public struct CreateDocEffect<T: Encodable & Equatable>: Effect {
                    let docRef: DocRef
                    let collectionName: String
                    let value: T
                    public func runEffect() async throws -> String {
                        try await createDoc(docRef: docRef, collectionName: collectionName, value: value)
                    }
                    public init(docRef: DocRef, collectionName: String, value: T) {
                        self.docRef = docRef
                        self.collectionName = collectionName
                        self.value = value
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

    func testCreateEffectMacroWithTemplateComposed() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct
                func createDoc<T: Encodable & BrainFuck>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func createDoc<T: Encodable & BrainFuck>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }

                public struct CreateDocEffect<T: Encodable & BrainFuck & Equatable>: Effect {
                    let docRef: DocRef
                    let collectionName: String
                    let value: T
                    public func runEffect() async throws -> String {
                        try await createDoc(docRef: docRef, collectionName: collectionName, value: value)
                    }
                    public init(docRef: DocRef, collectionName: String, value: T) {
                        self.docRef = docRef
                        self.collectionName = collectionName
                        self.value = value
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

    func testCreateEffectMacroWithTemplateComposedEquatable() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct(equatable: true)
                func createDoc<T: Encodable & Equatable>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                func createDoc<T: Encodable & Equatable>(docRef: DocRef, collectionName: String, value: T) async throws -> String {
                    return ""
                }

                public struct CreateDocEffect<T: Encodable & Equatable>: Effect, Equatable {
                    let docRef: DocRef
                    let collectionName: String
                    let value: T
                    public func runEffect() async throws -> String {
                        try await createDoc(docRef: docRef, collectionName: collectionName, value: value)
                    }
                    public init(docRef: DocRef, collectionName: String, value: T) {
                        self.docRef = docRef
                        self.collectionName = collectionName
                        self.value = value
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

    func testCreateEffectMacroWithTemplateComposedManyEquatable() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            enum SomeNamespace {
                @EffectStruct(equatable: true)
                static func performRequest<Request: Encodable, Response: Decodable>(_ callable: Callable, request: Request? = EmptyRequest()) async throws -> Response {
                    return
                }
            }
            """#,
            expandedSource: #"""
            enum SomeNamespace {
                static func performRequest<Request: Encodable, Response: Decodable>(_ callable: Callable, request: Request? = EmptyRequest()) async throws -> Response {
                    return
                }

                public struct PerformRequestEffect<Request: Encodable & Equatable, Response: Decodable>: Effect, Equatable {
                    let callable: Callable
                    let request: Request?
                    public func runEffect() async throws -> Response {
                        try await performRequest(_: callable, request: request)
                    }
                    public init(_ callable: Callable, request: Request? = EmptyRequest()) {
                        self.callable = callable
                        self.request = request
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
