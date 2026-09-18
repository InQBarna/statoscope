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


    func testReducerBasicExpansion() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Reducer
            struct Counter {
                struct State {
                    var count: Int = 0
                }
                enum When {
                    case increment
                }
                static func update(
                    _ when: When,
                    state: inout State,
                    effectsState: inout EffectsState<When>,
                    dependencies: ReducerDependencies
                ) throws {
                    state.count += 1
                }
            }
            """#,
            expandedSource: #"""
            struct Counter {
                struct State {
                    var count: Int = 0
                }
                enum When {
                    case increment
                }
                static func update(
                    _ when: When,
                    state: inout State,
                    effectsState: inout EffectsState<When>,
                    dependencies: ReducerDependencies
                ) throws {
                    state.count += 1
                }

                public typealias Store = Statoscope.Store<Counter>
            }

            extension Counter: Reducer {
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testReducerWithSubStateExpansion() throws {
        #if canImport(StatoscopeMacros)
        assertMacroExpansion(
            #"""
            @Reducer
            struct Parent {
                struct State {
                    var label: String = ""
                    @SubState var child: Child.State?
                }
                enum When {
                    case openChild
                }
                static func update(
                    _ when: When,
                    state: inout State,
                    effectsState: inout EffectsState<When>,
                    dependencies: ReducerDependencies
                ) throws {
                    state.child = Child.State()
                }
            }
            """#,
            expandedSource: #"""
            struct Parent {
                struct State {
                    var label: String = ""
                    @SubState var child: Child.State?
                }
                enum When {
                    case openChild
                }
                static func update(
                    _ when: When,
                    state: inout State,
                    effectsState: inout EffectsState<When>,
                    dependencies: ReducerDependencies
                ) throws {
                    state.child = Child.State()
                }

                public typealias Store = Statoscope.Store<Parent>

                public struct ChildStores: ChildStoresProtocol {
                    let _cache: [AnyHashable: AnyObject]
                    public init(cache: [AnyHashable: AnyObject]) {
                        self._cache = cache
                    }
                    public var child: Statoscope.Store<Child>? {
                        guard let _raw = _cache[_CK.child] else {
                            return nil
                        }
                        guard let _typed = _raw as? Statoscope.Store<Child> else {
                            fatalError("Statoscope internal error: child slot 'child' cached an " +
                                       "unexpected type \(Swift.type(of: _raw)); expected Statoscope.Store<Child>. " +
                                       "This indicates a bug in the @Reducer macro, not user code.")
                        }
                        return _typed
                    }
                    enum _CK: Hashable {
                        case child
                    }
                }

                public static var _childSlots: [AnyChildSlot<State>] {
                    [
                            AnyChildSlot(
                            key: ChildStores._CK.child,
                            isDirty: {
                                $0.$child.isDirty
                            },
                            isPresent: {
                                $0.child != nil
                            },
                            create: { parentState in
                                Statoscope.Store<Child>(initialState: parentState.child!)
                            },
                            triggerDefault: { store in
                                guard let s = store as? Statoscope.Store<Child> else {
                                    fatalError("Statoscope internal error: child slot 'child' triggerDefault " +
                                               "received an unexpected store type \(Swift.type(of: store)); " +
                                               "expected Statoscope.Store<Child>. " +
                                               "This indicates a bug in the @Reducer macro, not user code.")
                                }
                                guard let t = Child.defaultTrigger else {
                                    return
                                }
                                s.send(t)
                            },
                            resetDirty: {
                                $0.$child = SubState()
                            },
                            injectIntoParent: { store, state in
                                guard let store else {
                                    state.$child = SubState(injectedValue: nil)
                                    return
                                }
                                guard let s = store as? Statoscope.Store<Child> else {
                                    fatalError("Statoscope internal error: child slot 'child' injectIntoParent " +
                                               "received an unexpected store type \(Swift.type(of: store)); " +
                                               "expected Statoscope.Store<Child>. " +
                                               "This indicates a bug in the @Reducer macro, not user code.")
                                }
                                state.$child = SubState(injectedValue: s._rawState)
                            },
                            extractChildState: { parentState in
                                parentState.child!
                            }
                        )
                        ]
                }

                public static var _superSlots: [AnySuperSlot<State>] {
                    []
                }

                public static func buildChildView<V: _StatoscopeView>(
                    content: @escaping (Child.State, @escaping (Child.When) -> Void) -> V
                ) -> some _StatoscopeView {
                    _ReducerChildViewConnector<Store, Statoscope.Store<Child>, V>(
                        storeKeyPath: \.children.child,
                        content: content
                    )
                }
            }

            extension Parent: Reducer {
            }
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

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

            extension InvalidReducer: Reducer {
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

            extension InvalidReducer: Reducer {
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


}
