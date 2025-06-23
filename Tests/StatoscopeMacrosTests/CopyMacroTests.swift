//
//  CopyMacroTests.swift
//  Views
//
//  Created by Sergi Hernanz on 27/12/24.
//
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class CopyMacroTests: XCTestCase {

    func testStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            struct Struct {
                let bool: Bool
                let optBool: Bool?
            }
            """#,
            expandedSource: #"""
            struct Struct {
                let bool: Bool
                let optBool: Bool?

                public func copy(
                    bool: Bool? = nil,
                    optBool: Bool?? = .some(nil)
                ) -> Self {
                    .init(
                        bool: bool ?? self.bool,
                        optBool: (optBool == .some(nil) ? self.optBool : optBool as? Bool)
                    )
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
