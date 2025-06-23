//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class CaseAssociatedGetTests: XCTestCase {

    func testCaseAssociatedGetters() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @CaseAssociatedGet
            enum When {
                case associatedBool(Bool)
                case associatedTuple(Bool, Int, String)
                case associatedObject(SomeObjectType)
                case associatedWithSomeLabels(Bool, intLabel: Int, String)
                case associatedWithLabels(boolLabel: Bool, intLabel: Int, stringLabel: String)
                case nonAssociatedCase
            }
            """#,
            expandedSource: #"""
            enum When {
                case associatedBool(Bool)
                case associatedTuple(Bool, Int, String)
                case associatedObject(SomeObjectType)
                case associatedWithSomeLabels(Bool, intLabel: Int, String)
                case associatedWithLabels(boolLabel: Bool, intLabel: Int, stringLabel: String)
                case nonAssociatedCase

                var associatedBool: Bool? {
                    switch self {
                        case .associatedBool(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }

                var associatedTuple: (Bool, Int, String)? {
                    switch self {
                        case .associatedTuple(let param0, let param1, let param2):
                        return (param0, param1, param2)
                        default:
                        return nil
                    }
                }

                var associatedObject: SomeObjectType? {
                    switch self {
                        case .associatedObject(let associatedValue):
                        return associatedValue
                        default:
                        return nil
                    }
                }

                var associatedWithSomeLabels: (Bool, intLabel: Int, String)? {
                    switch self {
                        case .associatedWithSomeLabels(let param0, let intLabel, let param2):
                        return (param0, intLabel: intLabel, param2)
                        default:
                        return nil
                    }
                }

                var associatedWithLabels: (boolLabel: Bool, intLabel: Int, stringLabel: String)? {
                    switch self {
                        case .associatedWithLabels(let boolLabel, let intLabel, let stringLabel):
                        return (boolLabel: boolLabel, intLabel: intLabel, stringLabel: stringLabel)
                        default:
                        return nil
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
