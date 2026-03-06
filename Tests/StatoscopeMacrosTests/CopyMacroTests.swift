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

    // MARK: - Visibility Modifier Tests

    func testPrivateStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            private struct PrivateStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            private struct PrivateStruct {
                let value: Int

                private func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testFileprivateStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            fileprivate struct FileprivateStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            fileprivate struct FileprivateStruct {
                let value: Int

                fileprivate func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testInternalStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            internal struct InternalStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            internal struct InternalStruct {
                let value: Int

                internal func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testPackageStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            package struct PackageStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            package struct PackageStruct {
                let value: Int

                package func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testPublicStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            public struct PublicStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            public struct PublicStruct {
                let value: Int

                public func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testOpenStructCopy() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Copy
            open struct OpenStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            open struct OpenStruct {
                let value: Int

                open func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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

    func testDefaultVisibilityImpliesToPublic() throws {
        #if canImport(StatoscopeMacros)
        // When no visibility modifier is specified, copy function should be public
        assertMacroExpansion(
            #"""
            @Copy
            struct DefaultStruct {
                let value: Int
            }
            """#,
            expandedSource: #"""
            struct DefaultStruct {
                let value: Int

                public func copy(
                    value: Int? = nil
                ) -> Self {
                    .init(
                        value: value ?? self.value
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
