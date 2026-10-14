//
//  ReducerKeyPath.swift
//  Statoscope
//

import Foundation

extension Reducer {
    /// Every `@Reducer`'s canonical live Store type. Always `Store<Self>` — `Store<R>` already
    /// exists generically for any `Reducer`, so this needs no macro-generated conformance.
    public typealias OwnStore = Statoscope.Store<Self>
}

/// A position-based path from a root `Reducer`'s live Store down to a descendant `Reducer`'s
/// live Store, expressed purely in terms of `Reducer`/`State` types — a view that holds one
/// never names a `Store` type.
///
/// ## Why this exists
/// SwiftUI detaches lazily-evaluated presentation content (`.navigationDestination`, `.sheet`,
/// `.fullScreenCover`, `NavigationLink`) from the environment of whoever presented it: an
/// `@EnvironmentObject` injected more than one level above a destination is unreachable from
/// inside it — confirmed structural (not a timing issue), confirmed uniform across all three
/// presentation APIs, and confirmed to be a general, widely-documented SwiftUI limitation, not
/// specific to this library. The previous fix (`ReducerStoreRegistry`) sidestepped this with a
/// single root-injected registry keyed by *concrete Store type* — which has a real, documented
/// weakness: two simultaneous instances of the same reducer type at different tree positions
/// collide, since the registry has no notion of tree position, only type.
///
/// `ReducerKeyPath` fixes this by construction: it's a position in the tree, built by composing
/// one hop at a time from the true root (injected exactly once, above everything, via
/// `ReducerStoreView`/`.environmentObject(store)`), carried explicitly through ordinary `init`
/// parameters rather than resolved from a global. Composing via closures (not Swift's native
/// `KeyPath.appending(path:)`, which requires decomposing an already-composed KeyPath — something
/// Swift provides no API for) means each `.append(_:)` call captures the previous resolver
/// directly, with no information loss.
///
/// ## Usage
/// ```swift
/// struct ChildView: View {
///     let model: ChildReducer.State
///     let send: (ChildReducer.When) -> Void
///     let ownPath: ReducerKeyPath<ParentReducer, ChildReducer>   // "ParentReducer" is the root here
///
///     var body: some View {
///         Text(model.label)
///             .navigationDestination(isPresented: ChildReducer.bind(\.grandchild, in: model, dismissWhen: .hide, send: send)) {
///                 ConnectedChild(ownPath.append(\.grandchild, as: GrandchildReducer.self)) { state, send, path in
///                     GrandchildView(model: state, send: send, ownPath: path)
///                 }
///             }
///     }
/// }
/// ```
public struct ReducerKeyPath<RootReducer: Reducer, CurrentReducer: Reducer> {
    fileprivate let resolveStore: (RootReducer.OwnStore) -> CurrentReducer.OwnStore?

    fileprivate init(resolveStore: @escaping (RootReducer.OwnStore) -> CurrentReducer.OwnStore?) {
        self.resolveStore = resolveStore
    }

    /// Resolves the live Store at this position, starting from the root Store — `nil` if
    /// anything along the path is currently absent (e.g. a `@SubState` that's been set to `nil`).
    public func resolve(from root: RootReducer.OwnStore) -> CurrentReducer.OwnStore? {
        resolveStore(root)
    }

    /// Extends this path one `@SubState` hop deeper.
    ///
    /// `hop` is a State-relative KeyPath — the same one you'd write to read the child state
    /// directly off `State` (`\.child`). `NextReducer` can't be inferred from `hop` alone (Swift
    /// doesn't invert an associated-type projection like `NextReducer.State` back to
    /// `NextReducer`), so it's supplied explicitly via `as:`.
    public func append<NextReducer: Reducer>(
        _ hop: KeyPath<CurrentReducer.State, NextReducer.State?>,
        as nextReducer: NextReducer.Type = NextReducer.self
    ) -> ReducerKeyPath<RootReducer, NextReducer> {
        let storeHop = _SubStateHopRegistry.storeHop(
            for: hop, parent: CurrentReducer.self, child: NextReducer.self
        )
        return ReducerKeyPath<RootReducer, NextReducer>(resolveStore: { root in
            self.resolveStore(root).flatMap { $0[keyPath: storeHop] }
        })
    }
}

extension ReducerKeyPath where RootReducer == CurrentReducer {
    /// The path from a root Store to itself — the starting point every root view passes down.
    public static var root: ReducerKeyPath<RootReducer, RootReducer> {
        ReducerKeyPath(resolveStore: { $0 })
    }
}

extension ReducerKeyPath {
    /// A placeholder path that always resolves to `nil`, without touching
    /// `_SubStateHopRegistry` or requiring any Store to exist.
    ///
    /// A view that navigates further needs a real `ownPath` value to pass to its own
    /// `ConnectedChild` calls — including in a SwiftUI `#Preview`, which usually renders that
    /// view directly from a mock `State`, with no root Store ever created and no
    /// `ReducerStoreView` in the hierarchy. Building a real path there with `.root.append(...)`
    /// would call into `_SubStateHopRegistry` before any `Store.init` has registered the hop it
    /// needs, hitting its `fatalError` fallback — even though the path is never actually
    /// resolved, since the mock `State` driving the preview has nothing further to navigate to.
    /// Use `.preview` instead wherever a `ReducerKeyPath` value is needed only to satisfy a
    /// type, never to resolve a live Store.
    public static var preview: ReducerKeyPath<RootReducer, CurrentReducer> {
        ReducerKeyPath(resolveStore: { _ in nil })
    }

    /// A path that always resolves to `store`, ignoring the environment root entirely.
    ///
    /// For a Store built standalone — outside the real root hierarchy — but typed against the
    /// app's real `RootReducer` for API consistency with every other `ownPath` (e.g. an isolated
    /// QA/test-double screen, seeded directly with a descendant's state). `append` still works
    /// normally on the result: it only needs a live Store at this position, never how it got here.
    /// Rendering a `ConnectedChild` anywhere in `store`'s own subtree still requires *some*
    /// `RootReducer.OwnStore` present in the environment to satisfy `@EnvironmentObject` — one
    /// that's never actually read, since this path never consults it.
    public static func detached(_ store: CurrentReducer.OwnStore) -> ReducerKeyPath<RootReducer, CurrentReducer> {
        ReducerKeyPath(resolveStore: { _ in store })
    }
}

/// Internal — populated automatically by `@Reducer`'s generated `_childSlots`, once per
/// `@SubState` property, the first time any Store of that reducer type is created (well before
/// any navigation can reach it, since a `@SubState` child can't be presented before it exists).
///
/// Maps each `@SubState` property's State-relative KeyPath to its Store-relative equivalent —
/// the one place this design erases a type, and only from a missing *codegen* registration
/// (unreachable from an app call site, since `append`'s `hop` parameter is already
/// compiler-checked against the correct `State` type before this is ever consulted).
///
/// Plain `public`, not `@_spi` — macro-expanded code referencing this lands directly in
/// whatever file declares a `@Reducer`, so it must be reachable from an ordinary `import
/// Statoscope`, the same way `AnyChildSlot`/`ChildStoresProtocol` are.
public enum _SubStateHopRegistry {
    private static var hopsByStateKeyPath: [AnyKeyPath: AnyKeyPath] = [:]

    /// `parent`/`child` are redundant with `state`/`store`'s own generic parameters at any call
    /// site that already knows both concrete reducer types (as macro-generated code always
    /// does) — passed explicitly so the compiler never has to invert an associated-type
    /// projection (`ChildReducer.State`) back to the reducer type that produced it, which Swift
    /// generic inference doesn't support.
    public static func register<ParentReducer: Reducer, ChildReducer: Reducer>(
        parent: ParentReducer.Type,
        child: ChildReducer.Type,
        state: KeyPath<ParentReducer.State, ChildReducer.State?>,
        store: KeyPath<ParentReducer.OwnStore, ChildReducer.OwnStore?>
    ) {
        hopsByStateKeyPath[state] = store
    }

    static func storeHop<ParentReducer: Reducer, ChildReducer: Reducer>(
        for stateHop: KeyPath<ParentReducer.State, ChildReducer.State?>,
        parent: ParentReducer.Type,
        child: ChildReducer.Type
    ) -> KeyPath<ParentReducer.OwnStore, ChildReducer.OwnStore?> {
        guard
            let erased = hopsByStateKeyPath[stateHop],
            let typed = erased as? KeyPath<ParentReducer.OwnStore, ChildReducer.OwnStore?>
        else {
            fatalError(
                "Statoscope internal error: no Store-relative hop registered for \(stateHop) " +
                    "(\(ParentReducer.self) -> \(ChildReducer.self)). This indicates a bug in " +
                    "the @Reducer macro, not user code."
            )
        }
        return typed
    }
}
