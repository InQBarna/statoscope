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

/// Macro that generates a Store typealias + ChildStores struct for a Reducer.
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
/// Into (members, inside the struct):
/// ```swift
/// public typealias Store = Statoscope.Store<ParentReducer>
///
/// public struct ChildStores: ChildStoresProtocol { ... }
///
/// public static var _childSlots: [AnyChildSlot<State>] { ... }
/// public static var _superSlots: [AnySuperSlot<State>] { ... }
/// ```
///
/// Plus (extension, at module scope):
/// ```swift
/// extension ParentReducer: Reducer {}
/// ```
public struct ReducerMacro: MemberMacro, ExtensionMacro {

    // MARK: - ExtensionMacro
    // Only emits the Reducer conformance. All type-aware code goes in MemberMacro
    // so that sibling types in enclosing enums/structs remain in scope.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {

        guard declaration.is(StructDeclSyntax.self) else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): Reducer {}")]
    }

    // MARK: - MemberMacro
    // Generates typealias Store, ChildStores struct, _childSlots, _superSlots,
    // and build<Name>View helpers — all inside the struct body so sibling types
    // in enclosing namespaces are accessible.
    public static func expansion<
        Context: MacroExpansionContext,
        Declaration: DeclGroupSyntax
    >(
        of node: AttributeSyntax,
        providingMembersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {

        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: Syntax(declaration), message: StatoscopeMacroDiagnostic.notAStruct)
            context.diagnose(diagnostic)
            return []
        }

        let reducerName = structDecl.name.text

        guard let stateStruct = findStateStruct(in: structDecl) else {
            let diagnostic = Diagnostic(
                node: Syntax(structDecl),
                message: StatoscopeMacroDiagnostic.reducerMissingStateStruct
            )
            context.diagnose(diagnostic)
            return []
        }

        guard findWhenEnum(in: structDecl) != nil else {
            let diagnostic = Diagnostic(
                node: Syntax(structDecl),
                message: StatoscopeMacroDiagnostic.reducerMissingWhenEnum
            )
            context.diagnose(diagnostic)
            return []
        }

        let subStateProperties = findSubStateProperties(in: stateStruct)
        let superStateProperties = findSuperStateProperties(in: stateStruct)
        let parentStoreProperties = findSuperScopeProperties(in: stateStruct)
        let injectedProperties = findReducerInjectedProperties(in: stateStruct)

        // 1. typealias Store = Statoscope.Store<ReducerName>  (always)
        let typeAlias: DeclSyntax = DeclSyntax("""
        public typealias Store = Statoscope.Store<\(raw: reducerName)>
        """)

        var members: [DeclSyntax] = [typeAlias]

        // 2. ChildStores struct (only when @SubState props exist)
        if !subStateProperties.isEmpty {
            let childStoresMember = try generateChildStoresMember(
                reducerName: reducerName,
                subStateProperties: subStateProperties
            )
            members.append(childStoresMember)
        }

        // 3. _childSlots / _superSlots (whenever there is anything to wire)
        let hasSlots = !subStateProperties.isEmpty || !superStateProperties.isEmpty
            || !parentStoreProperties.isEmpty || !injectedProperties.isEmpty
        if hasSlots {
            let slotMembers = try generateSlotMembers(
                subStateProperties: subStateProperties,
                superStateProperties: superStateProperties,
                parentStoreProperties: parentStoreProperties,
                injectedProperties: injectedProperties
            )
            members += slotMembers
        }

        // 4. build<Name>View helpers (when @SubState exists)
        let buildChildViewMethods = generateBuildChildViewMethods(
            reducerName: reducerName,
            subStateProperties: subStateProperties
        )
        members += buildChildViewMethods

        return members
    }

    // MARK: - Helpers: finders

    private static func findStateStruct(in structDecl: StructDeclSyntax) -> StructDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let nestedStruct = member.decl.as(StructDeclSyntax.self),
               nestedStruct.name.text == "State" {
                return nestedStruct
            }
        }
        return nil
    }

    private static func findWhenEnum(in structDecl: StructDeclSyntax) -> EnumDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let nestedEnum = member.decl.as(EnumDeclSyntax.self),
               nestedEnum.name.text == "When" {
                return nestedEnum
            }
        }
        return nil
    }

    private static func findSuperStateProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String, observed: Bool)] {
        var properties: [(String, String, Bool)] = []
        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            var superStateAttribute: AttributeSyntax?
            for attr in varDecl.attributes {
                guard case .attribute(let attribute) = attr else { continue }
                if attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SuperState" {
                    superStateAttribute = attribute
                    break
                }
            }
            guard let attribute = superStateAttribute else { continue }
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

    private static func findSubStateProperties(in stateStruct: StructDeclSyntax) -> [(name: String, type: String)] {
        var properties: [(String, String)] = []
        for member in stateStruct.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let hasSubState = varDecl.attributes.contains { attr in
                guard case .attribute(let attribute) = attr else { return false }
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SubState"
            }
            guard hasSubState else { continue }
            if let binding = varDecl.bindings.first,
               let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let typeAnnotation = binding.typeAnnotation?.type.as(OptionalTypeSyntax.self) {
                let childType = typeAnnotation.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
                properties.append((identifier, childType))
            }
        }
        return properties
    }

    // MARK: - Helpers: inference

    /// "ParentState" → "ParentReducer", "ChildReducer.State" → "ChildReducer"
    private static func inferReducerType(from stateType: String) -> String {
        if stateType.hasSuffix(".State") {
            return String(stateType.dropLast(".State".count))
        }
        if stateType.hasSuffix("State") {
            let baseName = String(stateType.dropLast("State".count))
            return baseName + "Reducer"
        }
        return stateType + "Reducer"
    }

    // MARK: - Generators

    private static func generateChildStoresMember(
        reducerName: String,
        subStateProperties: [(name: String, type: String)]
    ) throws -> DeclSyntax {
        let propDecls = subStateProperties.map { prop -> String in
            let reducerType = inferReducerType(from: prop.type)
            return """
            public var \(prop.name): Statoscope.Store<\(reducerType)>? {
                    guard let _raw = _cache[_CK.\(prop.name)] else { return nil }
                    guard let _typed = _raw as? Statoscope.Store<\(reducerType)> else {
                        fatalError("Statoscope internal error: child slot '\(prop.name)' cached an " +
                                   "unexpected type \\(Swift.type(of: _raw)); expected Statoscope.Store<\(reducerType)>. " +
                                   "This indicates a bug in the @Reducer macro, not user code.")
                    }
                    return _typed
                }
            """
        }.joined(separator: "\n    ")

        let ckCases = subStateProperties.map { "case \($0.name)" }.joined(separator: "\n        ")

        return DeclSyntax("""
        public struct ChildStores: ChildStoresProtocol {
            let _cache: [AnyHashable: AnyObject]
            public init(cache: [AnyHashable: AnyObject]) { self._cache = cache }
            \(raw: propDecls)
            enum _CK: Hashable { \(raw: ckCases) }
        }
        """)
    }

    /// Generates `_childSlots` and `_superSlots` as static members of the Reducer struct.
    ///
    /// Because these are MemberMacro-generated (inside the struct body), sibling types
    /// in the same enclosing namespace are accessible without qualification.
    private static func generateSlotMembers(
        subStateProperties: [(name: String, type: String)],
        superStateProperties: [(name: String, type: String, observed: Bool)],
        parentStoreProperties: [(name: String, type: String, observed: Bool)],
        injectedProperties: [(name: String, type: String)]
    ) throws -> [DeclSyntax] {

        // _childSlots
        let childSlotEntries = subStateProperties.map { prop -> String in
            let reducerType = inferReducerType(from: prop.type)
            return """
            AnyChildSlot(
                    key: ChildStores._CK.\(prop.name),
                    isDirty: { $0.$\(prop.name).isDirty },
                    isPresent: { $0.\(prop.name) != nil },
                    create: { parentState in Statoscope.Store<\(reducerType)>(initialState: parentState.\(prop.name)!) },
                    triggerDefault: { store in
                        guard let s = store as? Statoscope.Store<\(reducerType)> else {
                            fatalError("Statoscope internal error: child slot '\(prop.name)' triggerDefault " +
                                       "received an unexpected store type \\(Swift.type(of: store)); " +
                                       "expected Statoscope.Store<\(reducerType)>. " +
                                       "This indicates a bug in the @Reducer macro, not user code.")
                        }
                        guard let t = \(reducerType).defaultTrigger else { return }
                        s.send(t)
                    },
                    resetDirty: { $0.$\(prop.name) = SubState() },
                    injectIntoParent: { store, state in
                        guard let store else {
                            state.$\(prop.name) = SubState(injectedValue: nil)
                            return
                        }
                        guard let s = store as? Statoscope.Store<\(reducerType)> else {
                            fatalError("Statoscope internal error: child slot '\(prop.name)' injectIntoParent " +
                                       "received an unexpected store type \\(Swift.type(of: store)); " +
                                       "expected Statoscope.Store<\(reducerType)>. " +
                                       "This indicates a bug in the @Reducer macro, not user code.")
                        }
                        state.$\(prop.name) = SubState(injectedValue: s._rawState)
                    },
                    extractChildState: { parentState in parentState.\(prop.name)! }
                )
            """
        }

        let childSlotsBody = childSlotEntries.isEmpty
            ? "[]"
            : "[\n        " + childSlotEntries.joined(separator: ",\n        ") + "\n    ]"

        // _superSlots
        var superSlotEntries: [String] = []

        for prop in superStateProperties {
            let reducerType = inferReducerType(from: prop.type)
            let subscribeArg = prop.observed ? """
            ,
                subscribe: { store in
                    guard let parentStore = resolveAncestor(Statoscope.Store<\(reducerType)>.self, from: store),
                          let childStore = store as? Store else { return nil }
                    return parentStore.objectWillChange.sink { [weak childStore] _ in
                        childStore?.objectWillChange.send()
                    }
                }
            """ : ""
            superSlotEntries.append("""
            AnySuperSlot(
                inject: { store, state in
                    if let parentStore = resolveAncestor(Statoscope.Store<\(reducerType)>.self, from: store) {
                        state.$\(prop.name) = SuperState(injectedValue: parentStore.state)
                    }
                }\(subscribeArg)
            )
            """)
        }

        for prop in parentStoreProperties {
            let parentType = prop.type
            superSlotEntries.append("""
            AnySuperSlot(inject: { store, state in
                    if let parentStore = resolveAncestor(\(parentType).self, from: store) {
                        state._$\(prop.name) = ParentStoreBinding { [weak parentStore] in
                            parentStore ?? \(parentType).defaultValue
                        }
                    }
                })
            """)
        }

        for prop in injectedProperties {
            superSlotEntries.append("""
            AnySuperSlot(inject: { store, state in
                    if let node = store as? any InjectionTreeNode {
                        state.$\(prop.name) = ReducerInjected(injectedValue: node.resolveForBinding())
                    }
                })
            """)
        }

        let superSlotsBody = superSlotEntries.isEmpty
            ? "[]"
            : "[\n        " + superSlotEntries.joined(separator: ",\n        ") + "\n    ]"

        let childSlotsDecl: DeclSyntax = DeclSyntax("""
        public static var _childSlots: [AnyChildSlot<State>] { \(raw: childSlotsBody) }
        """)
        let superSlotsDecl: DeclSyntax = DeclSyntax("""
        public static var _superSlots: [AnySuperSlot<State>] { \(raw: superSlotsBody) }
        """)

        return [childSlotsDecl, superSlotsDecl]
    }

    private static func generateBuildChildViewMethods(
        reducerName: String,
        subStateProperties: [(name: String, type: String)]
    ) -> [DeclSyntax] {
        guard !subStateProperties.isEmpty else { return [] }
        return subStateProperties.map { prop -> DeclSyntax in
            let reducerType = inferReducerType(from: prop.type)
            let method = "build\(prop.name.capitalized)View"
            return DeclSyntax("""
            public static func \(raw: method)<V: _StatoscopeView>(
                content: @escaping (\(raw: prop.type), @escaping (\(raw: reducerType).When) -> Void) -> V
            ) -> some _StatoscopeView {
                _ReducerChildViewConnector<Store, Statoscope.Store<\(raw: reducerType)>, V>(
                    storeKeyPath: \\.children.\(raw: prop.name),
                    content: content
                )
            }
            """)
        }
    }
}

// MARK: - String Extensions

extension String {
    var capitalized: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
