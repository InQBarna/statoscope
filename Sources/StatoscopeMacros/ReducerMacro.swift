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
public struct ReducerMacro: MemberMacro, ExtensionMacro {

    // ExtensionMacro: adds `Reducer` conformance to the outer struct automatically
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): Reducer {}")]
    }

    // MemberMacro: generates the nested Store class
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

        // Analyze State properties for @SuperState, @SuperScope, @SubState, and @ReducerInjected
        let superStateProperties = findSuperStateProperties(in: stateStruct)
        let parentStoreProperties = findSuperScopeProperties(in: stateStruct)
        let subStateProperties = findSubStateProperties(in: stateStruct)
        let injectedProperties = findReducerInjectedProperties(in: stateStruct)

        // Check if State conforms to Injectable
        let stateIsInjectable = stateConformsToInjectable(in: stateStruct)

        // Check if Reducer conforms to MiddlewareReducer
        let isMiddlewareReducer = reducerConformsToMiddleware(in: structDecl)

        // Generate Store class as nested member
        let storeClass = try generateStoreClass(
            reducerName: reducerName,
            superStateProperties: superStateProperties,
            parentStoreProperties: parentStoreProperties,
            subStateProperties: subStateProperties,
            injectedProperties: injectedProperties,
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
    private static func findSuperStateProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String, observed: Bool)] {
        var properties: [(String, String, Bool)] = []

        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Check if it has @SuperState attribute
            var superStateAttribute: AttributeSyntax?
            for attr in varDecl.attributes {
                guard case .attribute(let attribute) = attr else { continue }
                if attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SuperState" {
                    superStateAttribute = attribute
                    break
                }
            }

            guard let attribute = superStateAttribute else { continue }

            // Extract observed: Bool argument (defaults to false)
            var observed = false
            if let args = attribute.arguments?.as(LabeledExprListSyntax.self) {
                for arg in args {
                    if arg.label?.text == "observed",
                       let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        observed = boolExpr.literal.text == "true"
                    }
                }
            }

            // Extract property name and type
            if let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let typeAnnotation = binding.typeAnnotation?.type {
                let typeName = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
                properties.append((identifier, typeName, observed))
            }
        }

        return properties
    }

    /// Find properties marked with @SuperScope (parent Statostore, not yet migrated to Reducer)
    private static func findSuperScopeProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String, observed: Bool)] {
        var properties: [(String, String, Bool)] = []

        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            var superScopeAttribute: AttributeSyntax?
            for attr in varDecl.attributes {
                guard case .attribute(let attribute) = attr else { continue }
                if attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SuperScope" {
                    superScopeAttribute = attribute
                    break
                }
            }

            guard let attribute = superScopeAttribute else { continue }

            // Extract observed: Bool argument (defaults to false)
            var observed = false
            if let args = attribute.arguments?.as(LabeledExprListSyntax.self) {
                for arg in args {
                    if arg.label?.text == "observed",
                       let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        observed = boolExpr.literal.text == "true"
                    }
                }
            }

            if let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let typeAnnotation = binding.typeAnnotation?.type {
                let typeName = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
                properties.append((identifier, typeName, observed))
            }
        }

        return properties
    }

    /// Find properties marked with @ReducerInjected
    private static func findReducerInjectedProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String)] {
        var properties: [(String, String)] = []

        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            let hasReducerInjected = varDecl.attributes.contains { attr in
                guard case .attribute(let attribute) = attr else { return false }
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "ReducerInjected"
            }

            guard hasReducerInjected else { continue }

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
    /// "MyModule.ChildReducer.State" → "MyModule.ChildReducer"
    private static func inferReducerType(from stateType: String) -> String {
        // Handle qualified type: drop trailing ".State" component
        // "ChildReducer.State" → "ChildReducer"
        // "MyModule.ChildReducer.State" → "MyModule.ChildReducer"
        if stateType.hasSuffix(".State") {
            return String(stateType.dropLast(".State".count))
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
        superStateProperties: [(name: String, type: String, observed: Bool)],
        parentStoreProperties: [(name: String, type: String, observed: Bool)],
        subStateProperties: [(name: String, type: String)],
        injectedProperties: [(name: String, type: String)],
        stateIsInjectable: Bool,
        isMiddlewareReducer: Bool
    ) throws -> DeclSyntax {

        // Generate @Superscope properties for @SuperState (parent is a Reducer)
        let superscopeFromStateDecls = superStateProperties.map { prop in
            let reducerType = inferReducerType(from: prop.type)
            let observedArg = prop.observed ? "(observed: true)" : ""
            return "@Superscope\(observedArg) var _\(prop.name): \(reducerType).Store"
        }

        // Generate @Superscope properties for @SuperScope (parent is a Statostore)
        let superscopeFromStoreDecls = parentStoreProperties.map { prop in
            let observedArg = prop.observed ? "(observed: true)" : ""
            return "@Superscope\(observedArg) var _\(prop.name): \(prop.type)"
        }

        let superscopeDecls = (superscopeFromStateDecls + superscopeFromStoreDecls)
            .joined(separator: "\n    ")

        // Generate @Subscope properties
        let subscopeDecls = subStateProperties.map { prop in
            let reducerType = inferReducerType(from: prop.type)
            return "@Subscope @_spi(Internal) public var _\(prop.name): \(reducerType).Store?"
        }.joined(separator: "\n    ")

        // Generate state getter injection for @SuperState (parent is a Reducer) — plain value, no closures
        let superStateBindingsInjection = superStateProperties.map { prop in
            """
            mutableState.$\(prop.name) = SuperState(injectedValue: _\(prop.name).state)
            """
        }

        // Generate state getter bindings injection for @SuperScope (parent is a Statostore)
        let parentStoreBindingsInjection = parentStoreProperties.map { prop in
            """
            mutableState._$\(prop.name) = ParentStoreBinding { [weak self] in
                        self?._\(prop.name) ?? \(prop.type).defaultValue
                    }
            """
        }

        let superBindingsInjection = (superStateBindingsInjection + parentStoreBindingsInjection)
            .joined(separator: "\n                    ")

        let subBindingsInjection = subStateProperties.map { prop in
            """
            mutableState.$\(prop.name) = SubState(injectedValue: _\(prop.name)?._rawState)
            """
        }.joined(separator: "\n                    ")

        // Generate state getter bindings injection for @ReducerInjected dependencies
        let injectedBindingsInjection = injectedProperties.map { prop in
            """
            mutableState._$\(prop.name) = InjectedBinding { [weak self] in
                        self?.resolveForBinding() ?? \(prop.type).defaultValue
                    }
            """
        }.joined(separator: "\n                    ")

        // Generate per-property write-back in update() and updateSubscope()
        // For each @SubState property: update existing child store state or create/destroy store.
        let updateWiringSync: String
        if subStateProperties.isEmpty {
            updateWiringSync = ""
        } else {
            let syncPerProp = subStateProperties.map { prop in
                let reducerType = inferReducerType(from: prop.type)
                return """
                if mutableState.$\(prop.name).isDirty {
                            if let newChildState = mutableState.\(prop.name) {
                                let newStore = \(reducerType).Store(initialState: newChildState)
                                _\(prop.name) = newStore
                                let _defaultTrigger_\(prop.name): \(reducerType).When? = \(reducerType).defaultTrigger
                                if let trigger = _defaultTrigger_\(prop.name) {
                                    newStore.send(trigger)
                                }
                            } else {
                                _\(prop.name) = nil
                            }
                        }
                        mutableState.$\(prop.name) = SubState()
                """
            }.joined(separator: "\n                ")
            updateWiringSync = syncPerProp
        }

        // Conditionally include Injectable, HierarchialScopeMiddleWare, and ReducerDispatchable conformances.
        // ReducerDispatchable is always added so any Store can be a dispatchable descendant in
        // a deep middleware hierarchy, enabling grandparent+ updateSubstate calls.
        var conformancesList = ["Statostore", "ObservableObject", "ReducerDispatchable"]
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

        // ReducerDispatchable: _callUpdateSubstate generated for ALL stores (not just MiddlewareReducer)
        // so that any store can serve as a dispatchable descendant in a deep hierarchy.
        // The method casts `when` to this reducer's When type, then calls Parent.updateSubstate
        // with the exact reducer type known at code-generation time.
        let callUpdateSubstateMethod = """

            // ReducerDispatchable conformance — enables deep hierarchy updateSubstate propagation
            public func _callUpdateSubstate<Parent: MiddlewareReducer>(
                _ parentType: Parent.Type,
                when: Any,
                parentState: inout Parent.State,
                dependencies: ReducerDependencies
            ) throws -> Parent.When? {
                guard let typedWhen = when as? \(reducerName).When else { return nil }
                return try Parent.updateSubstate(
                    \(reducerName).self,
                    childState: state,
                    childWhen: typedWhen,
                    parentState: &parentState,
                    dependencies: dependencies
                )
            }
        """

        // MiddlewareReducer updateSubscope uses a single ReducerDispatchable cast instead of
        // per-@SubState type casts. This works for direct children AND any deeper descendant:
        // event.child's _callUpdateSubstate captures the exact reducer type at code-gen time,
        // so grandparent+ updateSubstate is called without artificial forwarding in intermediates.
        // Self-interception is excluded via ObjectIdentifier comparison.
        let middlewareMethod = isMiddlewareReducer ? """

            // HierarchialScopeMiddleWare conformance
            public func updateSubscope<Child: ScopeImplementation>(
                _ event: SubscopeEvent<Child>
            ) throws {
                var mutableState = state
                let dependencies = ReducerDependenciesImpl(node: self, parentStore: self)
                var delegateWhen: When? = nil

                if let dispatchable = event.child as? any ReducerDispatchable,
                   ObjectIdentifier(dispatchable) != ObjectIdentifier(self) {
                    delegateWhen = try dispatchable._callUpdateSubstate(
                        \(reducerName).self,
                        when: event.when,
                        parentState: &mutableState,
                        dependencies: dependencies
                    )
                }

                // Write back child states to child stores and handle create/destroy
                \(updateWiringSync.isEmpty ? "// No child state write-back needed" : updateWiringSync)
                _rawState = mutableState

                if let delegateWhen = delegateWhen {
                    send(delegateWhen)
                }

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

            // Raw state storage (bindings not injected). Internal so parent stores can
            // read child._rawState directly — avoiding the parent↔child getter recursion.
            @Published @_spi(Internal) public var _rawState: State

            // Smart getter: injects parent bindings, live child states, and injected dependencies
            public var state: State {
                get {
                    var mutableState = _rawState

                    // Inject SuperStateBindings from @Superscope properties
                    \(raw: superBindingsInjection.isEmpty ? "// No super bindings to inject" : superBindingsInjection)

                    // Inject current child states from @Subscope stores
                    \(raw: subBindingsInjection.isEmpty ? "// No child states to inject" : subBindingsInjection)

                    // Inject InjectedBindings for @ReducerInjected dependencies
                    \(raw: injectedBindingsInjection.isEmpty ? "// No injected dependencies" : injectedBindingsInjection)

                    return mutableState
                }
                set {
                    _rawState = newValue
                }
            }

            public init(initialState: State) {
                self._rawState = initialState
            }

            @_spi(Internal)
            public func update(_ when: When) throws {
                var mutableState = state  // Uses getter: injects child states and super bindings
                let dependencies = ReducerDependenciesImpl(node: self, parentStore: self)
                try \(raw: reducerName).update(
                    when,
                    state: &mutableState,
                    effectsState: &effectsState,
                    dependencies: dependencies
                )
                // Write back child states to child stores and handle create/destroy
                \(raw: updateWiringSync.isEmpty ? "// No child state write-back needed" : updateWiringSync)
                _rawState = mutableState
            }\(raw: callUpdateSubstateMethod)\(raw: middlewareMethod)
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
