//
//  ReducerMacro.swift
//  Statoscope
//
//  Created by Claude Code on 28/2/26.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Macro that generates a nested Store class for a Reducer
///
/// Transforms:
/// ```swift
/// @Reducer
/// struct ParentReducer {
///     struct State {
///         var count: Int = 0
///         @SuperState var grandparent: GrandparentState
///         @SubState var child: ChildState?
///     }
///     enum When { case increment }
///     static func update(...) { ... }
/// }
/// ```
///
/// Into:
/// ```swift
/// extension ParentReducer {
///     public final class Store: Statostore, ObservableObject {
///         public typealias When = ParentReducer.When
///
///         @Superscope var _grandparent: GrandparentReducer.Store?
///         @Subscope var _child: ChildReducer.Store?
///
///         @Published private var _rawState: State
///
///         public var state: State {
///             get { /* inject bindings */ }
///             set { /* wire children */ }
///         }
///
///         public init(initialState: State) { ... }
///         public func update(_ when: When) throws { ... }
///     }
/// }
///
/// extension ParentReducer.State: Injectable {
///     public static var defaultValue: State { State() }
/// }
/// ```
public struct ReducerMacro: MemberMacro {

    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclGroupSyntax
    >(
        of node: AttributeSyntax,
        providingMembersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        // Validate this is a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: Syntax(declaration), message: StatoscopeMacroDiagnostic.notAStruct)
            context.diagnose(diagnostic)
            return []
        }

        let reducerName = structDecl.name.text

        // Find nested State struct
        guard let stateStruct = findStateStruct(in: structDecl) else {
            let diagnostic = Diagnostic(
                node: Syntax(structDecl),
                message: StatoscopeMacroDiagnostic.reducerMissingStateStruct
            )
            context.diagnose(diagnostic)
            return []
        }

        // Find nested When enum
        guard findWhenEnum(in: structDecl) != nil else {
            let diagnostic = Diagnostic(
                node: Syntax(structDecl),
                message: StatoscopeMacroDiagnostic.reducerMissingWhenEnum
            )
            context.diagnose(diagnostic)
            return []
        }

        // Analyze State properties for @SuperState and @SubState
        let superStateProperties = findSuperStateProperties(in: stateStruct)
        let subStateProperties = findSubStateProperties(in: stateStruct)

        // Check if State conforms to Injectable
        let stateIsInjectable = stateConformsToInjectable(in: stateStruct)

        // Check if Reducer conforms to MiddlewareReducer
        let isMiddlewareReducer = reducerConformsToMiddleware(in: structDecl)

        // Generate Store class as nested member
        let storeClass = try generateStoreClass(
            reducerName: reducerName,
            superStateProperties: superStateProperties,
            subStateProperties: subStateProperties,
            stateIsInjectable: stateIsInjectable,
            isMiddlewareReducer: isMiddlewareReducer
        )

        return [storeClass]
    }

    // MARK: - Helper Methods

    /// Find the nested State struct in the Reducer
    private static func findStateStruct(in structDecl: StructDeclSyntax) -> StructDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let nestedStruct = member.decl.as(StructDeclSyntax.self),
               nestedStruct.name.text == "State" {
                return nestedStruct
            }
        }
        return nil
    }

    /// Find the nested When enum in the Reducer
    private static func findWhenEnum(in structDecl: StructDeclSyntax) -> EnumDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let nestedEnum = member.decl.as(EnumDeclSyntax.self),
               nestedEnum.name.text == "When" {
                return nestedEnum
            }
        }
        return nil
    }

    /// Find properties marked with @SuperState
    private static func findSuperStateProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String)] {
        var properties: [(String, String)] = []

        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Check if it has @SuperState attribute
            let hasSuperState = varDecl.attributes.contains { attr in
                guard case .attribute(let attribute) = attr else { return false }
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SuperState"
            }

            guard hasSuperState else { continue }

            // Extract property name and type
            if let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let typeAnnotation = binding.typeAnnotation?.type {
                let typeName = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
                properties.append((identifier, typeName))
            }
        }

        return properties
    }

    /// Find properties marked with @SubState
    private static func findSubStateProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String)] {
        var properties: [(String, String)] = []

        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Check if it has @SubState attribute
            let hasSubState = varDecl.attributes.contains { attr in
                guard case .attribute(let attribute) = attr else { return false }
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SubState"
            }

            guard hasSubState else { continue }

            // Extract property name and type (should be optional)
            if let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let typeAnnotation = binding.typeAnnotation?.type.as(OptionalTypeSyntax.self) {
                let childType = typeAnnotation.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
                properties.append((identifier, childType))
            }
        }

        return properties
    }

    /// Check if State struct conforms to Injectable protocol
    private static func stateConformsToInjectable(in stateStruct: StructDeclSyntax) -> Bool {
        guard let inheritanceClause = stateStruct.inheritanceClause else {
            return false
        }

        return inheritanceClause.inheritedTypes.contains { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Injectable"
        }
    }

    /// Check if Reducer struct conforms to MiddlewareReducer protocol
    private static func reducerConformsToMiddleware(in structDecl: StructDeclSyntax) -> Bool {
        guard let inheritanceClause = structDecl.inheritanceClause else {
            return false
        }

        return inheritanceClause.inheritedTypes.contains { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "MiddlewareReducer"
        }
    }

    /// Infer reducer type from state type
    /// "ParentState" → "ParentReducer"
    /// "ChildReducer.State" → "ChildReducer"
    private static func inferReducerType(from stateType: String) -> String {
        // Handle qualified type: "ChildReducer.State" → "ChildReducer"
        if stateType.contains(".State") {
            return stateType.components(separatedBy: ".").first ?? stateType
        }

        // Handle naming convention: "ParentState" → "ParentReducer"
        if stateType.hasSuffix("State") {
            let baseName = String(stateType.dropLast("State".count))
            return baseName + "Reducer"
        }

        // Fallback
        return stateType + "Reducer"
    }

    /// Generate the Store class as a nested member
    private static func generateStoreClass(
        reducerName: String,
        superStateProperties: [(name: String, type: String)],
        subStateProperties: [(name: String, type: String)],
        stateIsInjectable: Bool,
        isMiddlewareReducer: Bool
    ) throws -> DeclSyntax {

        // Generate @Superscope properties
        let superscopeDecls = superStateProperties.map { prop in
            let reducerType = inferReducerType(from: prop.type)
            return "@Superscope var _\(prop.name): \(reducerType).Store"
        }.joined(separator: "\n    ")

        // Generate @Subscope properties
        let subscopeDecls = subStateProperties.map { prop in
            let reducerType = inferReducerType(from: prop.type)
            return "@Subscope @_spi(Internal) public var _\(prop.name): \(reducerType).Store?"
        }.joined(separator: "\n    ")

        // Generate state getter bindings injection
        let superBindingsInjection = superStateProperties.map { prop in
            """
            mutableState._$\(prop.name) = SuperStateBinding { [weak self] in
                        self?._\(prop.name).state ?? \(prop.type).defaultValue
                    }
            """
        }.joined(separator: "\n                    ")

        let subBindingsInjection = subStateProperties.map { prop in
            """
            if let \(prop.name)Store = _\(prop.name) {
                        // Create binding with direct closure access to Store state
                        mutableState._$\(prop.name) = SubStateBinding<\(prop.type)>(
                            storeGetter: { [\(prop.name)Store] in \(prop.name)Store.state },
                            storeSetter: { [\(prop.name)Store] newState in \(prop.name)Store.state = newState },
                            underlyingStore: \(prop.name)Store
                        )
                    }
            """
        }.joined(separator: "\n                    ")

        // Generate state setter child wiring
        let childWiring = subStateProperties.map { prop in
            let reducerType = inferReducerType(from: prop.type)
            return """
            if let new\(prop.name.capitalized)Binding = finalState._$\(prop.name) {
                        if _\(prop.name) == nil {
                            // Check if this is a pending binding (needs Store creation)
                            if new\(prop.name.capitalized)Binding._isPending, let pendingState = new\(prop.name.capitalized)Binding._pendingState {
                                // Create child Store from pending state
                                let childStore = \(reducerType).Store(initialState: pendingState)
                                _\(prop.name) = childStore
                                // Update binding with direct closure access
                                finalState._$\(prop.name) = SubStateBinding<\(prop.type)>(
                                    storeGetter: { childStore.state },
                                    storeSetter: { childStore.state = $0 },
                                    underlyingStore: childStore
                                )
                            } else {
                                // Use existing Store from binding
                                _\(prop.name) = new\(prop.name.capitalized)Binding._underlyingStore as? \(reducerType).Store
                            }
                        }
                    } else if finalState._$\(prop.name) == nil {
                        _\(prop.name) = nil
                    }
            """
        }.joined(separator: "\n                    ")

        // Conditionally include Injectable and HierarchialScopeMiddleWare conformances
        var conformancesList = ["Statostore", "ObservableObject"]
        if stateIsInjectable {
            conformancesList.append("Injectable")
        }
        if isMiddlewareReducer {
            conformancesList.append("HierarchialScopeMiddleWare")
        }
        let conformances = conformancesList.joined(separator: ", ")

        // Conditionally generate Injectable defaultValue
        let injectableConformance = stateIsInjectable ? """

            // Injectable conformance
            public static var defaultValue: Store {
                Store(initialState: State.defaultValue)
            }
        """ : ""

        // Conditionally generate updateSubscope method for MiddlewareReducer
        let middlewareMethod = isMiddlewareReducer ? """

            // HierarchialScopeMiddleWare conformance
            public func updateSubscope<Child: ScopeImplementation>(
                _ event: SubscopeEvent<Child>
            ) throws {
                // BEFORE: Call static middleware method
                var mutableState = state

                let delegateWhen = try \(reducerName).updateSubscope(
                    childState: event.child,
                    childWhen: event.when,
                    parentState: &mutableState
                )

                state = mutableState

                // Send delegation event if returned
                if let delegateWhen = delegateWhen {
                    send(delegateWhen)
                }

                // FORWARD: Always forward to child (framework responsibility)
                try event.forward()
            }
        """ : ""

        return DeclSyntax("""
        public final class Store: \(raw: conformances) {
            public typealias When = \(raw: reducerName).When\(raw: injectableConformance)

            // @Superscope properties
            \(raw: superscopeDecls.isEmpty ? "// No superscope properties" : superscopeDecls)

            // @Subscope properties
            \(raw: subscopeDecls.isEmpty ? "// No subscope properties" : subscopeDecls)

            // Raw state storage (bindings not injected)
            @Published private var _rawState: State

            // Smart getter: injects bindings from @Superscope/@Subscope
            public var state: State {
                get {
                    \(raw: superBindingsInjection.isEmpty && subBindingsInjection.isEmpty ? "let" : "var") mutableState = _rawState

                    // Inject SuperStateBindings from @Superscope properties
                    \(raw: superBindingsInjection.isEmpty ? "// No super bindings to inject" : superBindingsInjection)

                    // Inject SubStateBindings from @Subscope properties
                    \(raw: subBindingsInjection.isEmpty ? "// No sub bindings to inject" : subBindingsInjection)

                    return mutableState
                }
                set {
                    \(raw: childWiring.isEmpty ? "let" : "var") finalState = newValue

                    // Detect SubStateBinding assignments and wire to @Subscope
                    \(raw: childWiring.isEmpty ? "// No child wiring needed" : childWiring)

                    // Update raw state with final values (including updated bindings)
                    _rawState = finalState
                }
            }

            public init(initialState: State) {
                self._rawState = initialState
            }

            @_spi(Internal)
            public func update(_ when: When) throws {
                var mutableState = state  // Uses getter: injects bindings
                let dependencies = ReducerDependenciesImpl(node: self, parentStore: self)
                try \(raw: reducerName).update(
                    when,
                    state: &mutableState,
                    effectsState: &effectsState,
                    dependencies: dependencies
                )
                state = mutableState  // Uses setter: wires children
            }\(raw: middlewareMethod)
        }
        """
        )
    }
}

// MARK: - String Extensions

extension String {
    var capitalized: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
