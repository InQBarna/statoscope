//
//  AutoConnectedView.swift
//  Statoscope
//

import SwiftUI

// Typealias used by the macro-generated `build<Name>View` method so generated code doesn't
// require `import SwiftUI` in the file where `@Reducer` is applied.
public typealias _StatoscopeView = SwiftUI.View

// MARK: - ReducerStoreProtocol

/// Protocol that generated `@Reducer` Store classes conform to.
public protocol ReducerStoreProtocol: ObservableObject {
    associatedtype State
    associatedtype When
    var state: State { get }
    func _dispatch(_ when: When)
}

// MARK: - ReducerStoreView

/// Root connector between a `@Reducer`-generated Store and a `StoreViewProtocol` view.
///
/// Renders the view with the store's current state and injects `store` into the SwiftUI
/// environment so that `build<Name>View` methods and `AutoConnectedView` can resolve
/// the store from any descendant — including navigation destinations.
///
/// Place the `NavigationStack` **inside** the root `StoreViewProtocol` view so the injected
/// store is an ancestor of the stack and propagates through all pushed destinations:
///
/// ```swift
/// struct AppRootView: StoreViewProtocol {
///     var model: AppReducer.State
///     var send: (AppReducer.When) -> Void
///     var body: some View {
///         NavigationStack { ... }   // ← inside ReducerStoreView, so store reaches destinations
///     }
/// }
/// ReducerStoreView<AppReducer.Store, AppRootView>(store: store)
/// ```
public struct ReducerStoreView<S: ReducerStoreProtocol, V: StoreViewProtocol>: View
    where S.State == V.State, S.When == V.When {

    @ObservedObject public var store: S
    @StateObject private var registry = ReducerStoreRegistry()

    public init(store: S) {
        self.store = store
    }

    public var body: some View {
        let _ = registry.push(store)
        V(model: store.state, send: store._dispatch)
            .environmentObject(store)
            .environmentObject(registry)
    }
}

// MARK: - AutoConnectedView

/// Embeds a child view connected to a child store, resolved from the parent store via a `KeyPath`.
///
/// Reads the parent store from `@EnvironmentObject`, navigates to the child store,
/// and — if non-nil — renders the child view observing that store.
///
/// ## Requirement
/// The parent store must be in the SwiftUI environment via `.environmentObject(store)`.
/// `ReducerStoreView` injects it automatically.
public struct AutoConnectedView<
    ParentStore: ReducerStoreProtocol,
    ChildStore: ReducerStoreProtocol,
    V: StoreViewProtocol
>: View where ChildStore.State == V.State, ChildStore.When == V.When {

    @EnvironmentObject private var parentStore: ParentStore
    private let keyPath: KeyPath<ParentStore, ChildStore?>

    public init(_ keyPath: KeyPath<ParentStore, ChildStore?>) {
        self.keyPath = keyPath
    }

    public var body: some View {
        if let childStore = parentStore[keyPath: keyPath] {
            _ConnectedChildView<ChildStore, V>(store: childStore)
        }
    }
}

private struct _ConnectedChildView<S: ReducerStoreProtocol, V: StoreViewProtocol>: View
    where S.State == V.State, S.When == V.When {

    @ObservedObject var store: S

    var body: some View {
        V(model: store.state, send: store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - ReducerObservedView

/// Observes a `ReducerStoreProtocol` store and renders a view closure with its current state,
/// injecting the store into the SwiftUI environment so `build<Name>View` navigation methods work.
///
/// Use this instead of a hand-written `@ObservedObject` wrapper whenever the view tree contains
/// navigation to child scopes via `build<Name>View`.
///
/// ```swift
/// ReducerObservedView(store: store) { state, dispatch in
///     MyAccountPresentedView(model: state, send: dispatch)
/// }
/// ```
public struct ReducerObservedView<S: ReducerStoreProtocol, V: View>: View {
    @ObservedObject public var store: S
    @EnvironmentObject private var registry: ReducerStoreRegistry
    private let content: (S.State, @escaping (S.When) -> Void) -> V

    public init(store: S, @ViewBuilder content: @escaping (S.State, @escaping (S.When) -> Void) -> V) {
        self.store = store
        self.content = content
    }

    public var body: some View {
        let _ = registry.push(store)
        content(store.state, store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - _ReducerChildObservingView (private shared helper)

private struct _ReducerChildObservingView<S: ReducerStoreProtocol, V: View>: View {
    @ObservedObject var store: S
    @EnvironmentObject private var registry: ReducerStoreRegistry
    let content: (S.State, @escaping (S.When) -> Void) -> V

    var body: some View {
        let _ = registry.push(store)
        content(store.state, store._dispatch)
            .environmentObject(store)
    }
}

// MARK: - ReducerStoreRegistry

/// A stack of live stores per concrete store type, injected exactly **once** at the app's
/// root by `ReducerStoreView`, so any navigation destination — at any nesting depth — can
/// resolve its own live parent store without depending on that specific level's own
/// `@EnvironmentObject` injection being reachable.
///
/// ## Why this exists
/// Each level of a `@Reducer` parent-child tree renders its own content via
/// `_ReducerChildObservingView`/`ReducerObservedView`, which injects `.environmentObject(store)`
/// wherever *that level* happens to render. For a single level of push navigation this is
/// enough — but confirmed (device-tested, multi-level real app) to fail once a destination is
/// reached through more than one nested push: `.navigationDestination`/`NavigationLink` push
/// results are anchored to the `NavigationStack`/`NavigationView` container's own position, not
/// to wherever the pushing content is currently nested, so an `@EnvironmentObject` injected
/// several levels below that container is invisible to the destination regardless of *how*
/// the destination resolves it (owning the presentation control locally, as
/// `_ReducerChildPresentingConnector` used to, does not help — the injection point itself is
/// too deep).
///
/// The fix: inject exactly one thing at the true root — above/at the `NavigationStack`
/// container, never any deeper — and have every level register itself into *that* instead of
/// adding its own environment injection. Resolving `ReducerStoreRegistry` itself via
/// `@EnvironmentObject` always succeeds, at any depth, because its injection point never
/// moves; it isn't a value being carried through a level-specific injection the way each
/// individual store was.
///
/// Keyed by concrete store type (`ObjectIdentifier(S.self)`) with a stack of weak references
/// per type — a stack so a reducer that navigates to another instance of its own type resolves
/// to the innermost (currently relevant) one; weak so a store that's genuinely torn down (its
/// last strong reference gone, e.g. `state.child = nil`) is skipped by `current(_:)` without
/// needing an explicit removal call.
///
/// ## Why there's no `pop`
/// An earlier revision removed a registered store on `.onDisappear`. **Confirmed on device**:
/// during a nested push (a destination pushing its own child destination), SwiftUI can fire
/// `.onDisappear` for a view that's still logically part of the stack — without ever firing a
/// matching `.onAppear` afterward — as part of its path reconciliation for the nested
/// transition. Acting on that `.onDisappear` permanently removed a store that was still very
/// much alive and still rendering, and nothing ever re-registered it, leaving every subsequent
/// lookup for it `nil` (symptom: the screen goes blank right as the nested push settles).
/// `push` is idempotent and safe to call on every `body` evaluation (not just `.onAppear`), and
/// weak references mean a truly-gone store silently drops out of `current(_:)` on its own —
/// so there's nothing left for an explicit `pop` to do that isn't already handled, and removing
/// it removes the SwiftUI-lifecycle-timing risk entirely.
public final class ReducerStoreRegistry: ObservableObject {

    private final class WeakBox {
        weak var value: AnyObject?
        init(_ value: AnyObject) { self.value = value }
    }

    private var stacks: [ObjectIdentifier: [WeakBox]] = [:]

    public init() {}

    /// Idempotent: safe to call repeatedly for the same store, including synchronously from
    /// `body` on every render (not just `.onAppear`) — a no-op once the store is already
    /// topmost. Compacts dead (weakly-nil) entries for this type on every call, so the stack
    /// doesn't grow unbounded even without an explicit `pop`.
    ///
    /// The `stacks` mutation itself is always synchronous, so a store is registered before its
    /// own first synchronous consumer runs later in the *same* `body` evaluation (e.g. a child
    /// created and immediately embedded in one update) — no notification needed for that case.
    ///
    /// But a genuinely new registration (or reordering) also schedules a **deferred**
    /// `objectWillChange.send()` (next run-loop turn, not synchronous) — needed for the opposite
    /// case: an *already-mounted* `ReducerRegistryCapture` (e.g. content sitting behind a
    /// `.navigationDestination` pushed earlier) whose resolved store gets replaced by a distant
    /// ancestor reassigning a `@SubState` further up the tree (tearing down and rebuilding an
    /// entire subtree with fresh `Store` instances). That capture has no other way to learn its
    /// store was replaced — it isn't itself re-rendering as part of the ancestor's update — so
    /// without this it keeps showing stale, torn-down content indefinitely (e.g. a presented
    /// child screen that should have auto-dismissed as its subtree got rebuilt, but silently
    /// doesn't). Deferring avoids SwiftUI's "Publishing changes from within view updates is not
    /// allowed" diagnostic, since `push` itself commonly runs synchronously from inside a `body`.
    func push<S: AnyObject>(_ store: S) {
        let key = ObjectIdentifier(S.self)
        var boxes = (stacks[key] ?? []).filter { $0.value != nil }
        if let existingIndex = boxes.firstIndex(where: { $0.value === store }) {
            if existingIndex == boxes.count - 1 {
                // Already topmost — nothing changed.
                stacks[key] = boxes
                return
            }
            boxes.remove(at: existingIndex)
        }
        boxes.append(WeakBox(store))
        stacks[key] = boxes
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func current<S: AnyObject>(_ type: S.Type = S.self) -> S? {
        stacks[ObjectIdentifier(S.self)]?.last(where: { $0.value != nil })?.value as? S
    }
}

// MARK: - ReducerRegistryCapture

/// Resolves the innermost currently-registered store of type `S` from `ReducerStoreRegistry`
/// (itself reached via `@EnvironmentObject`, always safe — see `ReducerStoreRegistry`) and
/// hands it to `content` by direct reference, the same shape as `ReducerEnvironmentCapture`
/// but sourcing from the registry instead of resolving `S` itself via `@EnvironmentObject`.
///
/// This is what `_ReducerChildViewConnector` is built on. Renders nothing if `S` isn't
/// registered yet (e.g. the one render pass before the registering view's `.onAppear` fires)
/// rather than crashing — a graceful, momentary gap instead of a hard failure.
///
/// `registry.current(_:)` is a plain, non-reactive lookup — calling it here would only
/// re-resolve when `registry` itself publishes (a push/pop), never when the *resolved store's
/// own* `@Published state` changes. `@EnvironmentObject` (what `ReducerEnvironmentCapture`
/// uses) is reactive to the resolved object precisely because the property wrapper itself
/// subscribes to it; a plain method call doesn't. `_ReducerRegistryObservingCapture` restores
/// that subscription via `@ObservedObject`, so a presentation `Binding` derived from the
/// resolved store (e.g. `capturedStore.bind(...)`) actually gets re-checked when that store's
/// state changes — without this, `.navigationDestination`/`.sheet` never notices the state
/// change that's supposed to trigger the push/presentation.
public struct ReducerRegistryCapture<S: ObservableObject, Content: View>: View {
    @EnvironmentObject private var registry: ReducerStoreRegistry
    private let content: (S) -> Content

    public init(_ type: S.Type = S.self, @ViewBuilder content: @escaping (S) -> Content) {
        self.content = content
    }

    public var body: some View {
        if let store = registry.current(S.self) {
            _ReducerRegistryObservingCapture(store: store, content: content)
        } else {
            let _ = StatoscopeLogger.LOG(
                .errors,
                "🗂️ ⁉️ ReducerRegistryCapture: no \(String(describing: S.self)) registered in " +
                    "ReducerStoreRegistry — rendering nothing. If this persists (rather than a " +
                    "single transient frame), the store was never pushed, or was deallocated " +
                    "while still expected to be alive."
            )
        }
    }
}

private struct _ReducerRegistryObservingCapture<S: ObservableObject, Content: View>: View {
    @ObservedObject var store: S
    let content: (S) -> Content

    var body: some View {
        content(store)
    }
}

// MARK: - _ReducerChildViewConnector

/// Used by the macro-generated `build<Name>View(content:)` method to connect a child store to
/// a view closure. Resolves its parent via `ReducerRegistryCapture` (the root-injected
/// registry) rather than a level-specific `@EnvironmentObject`, so this is safe to use directly
/// as the content of `.sheet`/`.fullScreenCover`/`NavigationLink`/`.navigationDestination` (or
/// embedded inline) regardless of how deep it's nested — only `ReducerStoreRegistry`'s own
/// injection point matters, and that never moves. Pair this with `store.bind(_:dismissWhen:)`/
/// `Reducer.bind(_:in:dismissWhen:send:)` at the call site for the presentation `Binding<Bool>`
/// itself; this connector only produces content, it has no opinion on how it's presented.
public struct _ReducerChildViewConnector<
    ParentStore: ReducerStoreProtocol,
    ChildStore: ReducerStoreProtocol,
    V: View
>: View {

    private let storeKeyPath: KeyPath<ParentStore, ChildStore?>
    private let content: (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V

    public init(
        storeKeyPath: KeyPath<ParentStore, ChildStore?>,
        content: @escaping (ChildStore.State, @escaping (ChildStore.When) -> Void) -> V
    ) {
        self.storeKeyPath = storeKeyPath
        self.content = content
    }

    public var body: some View {
        ReducerRegistryCapture(ParentStore.self) { capturedStore in
            if let childStore = capturedStore[keyPath: storeKeyPath] {
                _ReducerChildObservingView(store: childStore, content: content)
            }
        }
    }
}

// MARK: - Reducer.bind — reusable presentation Binding for StoreViewProtocol views

extension Reducer {
    /// Builds a `Binding<Bool>` from an already-resolved `model`/`send` pair — the shape every
    /// `StoreViewProtocol` view already has — instead of a live store reference.
    ///
    /// `StoreViewProtocol` views (the standard shape used throughout Statoscope: `model: State`,
    /// `send: (When) -> Void`) never hold a `Store` instance — only a state snapshot and a
    /// dispatch closure. `ReducerStoreProtocol.bind(_:dismissWhen:)` needs a live store and so
    /// can't be called from one; this is the `model`/`send`-based equivalent for exactly that
    /// context.
    ///
    /// - Parameters:
    ///   - keyPath: An optional property on `State` — the binding reads `true` while it's
    ///     non-nil in `model`.
    ///   - model: The `State` snapshot already in scope in a `StoreViewProtocol` view's body.
    ///   - dismissWhen: Sent via `send` when the binding is set to `false`.
    ///   - send: The dispatch closure already in scope in a `StoreViewProtocol` view's body.
    /// - Returns: `true` while `model[keyPath: keyPath] != nil`; setting it to `false` calls
    ///   `send(dismissWhen)`. Setting it to `true` has no effect, matching the instance-based
    ///   overload above.
    ///
    /// ## What this can't do
    /// This only builds the boolean `Binding` — it has no way to reach a *live child store*.
    /// For presenting an interactive `@SubState` child's own view (one with real `When` cases
    /// the presented content needs to `send`), pair this with `buildXxxView`, which resolves
    /// the live parent store via `ReducerRegistryCapture` specifically so it CAN reach
    /// `store.children.xxx`. This helper is for the `Binding<Bool>` half only — presentations
    /// driven entirely by data already in `model` (an `.alert`, a read-only `.sheet`) need
    /// nothing else; presentations of a child scope pair it with `buildXxxView` for content.
    ///
    /// ## Example
    /// ```swift
    /// struct MyAccountView: StoreViewProtocol {
    ///     var model: MyAccountReducer.State
    ///     var send: (MyAccountReducer.When) -> Void
    ///     var body: some View {
    ///         Text("Account")
    ///             .alert(
    ///                 "Error",
    ///                 isPresented: MyAccountReducer.bind(\.errorMessage, in: model, dismissWhen: .dismissError, send: send),
    ///                 actions: {}
    ///             )
    ///     }
    /// }
    /// ```
    public static func bind<Value>(
        _ keyPath: KeyPath<State, Value?>,
        in model: State,
        dismissWhen: When,
        send: @escaping (When) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] != nil },
            set: { if !$0 { send(dismissWhen) } }
        )
    }
}

// MARK: - ReducerStoreProtocol.bind — reusable presentation Binding

extension ReducerStoreProtocol {
    /// Builds a `Binding<Bool>` for presenting/dismissing UI driven by an optional property
    /// on `state`, exposed here so you can wire up your own `.sheet`/`.popover`/
    /// `.fullScreenCover`/`.navigationDestination`/custom presentation around `buildXxxView`
    /// without reimplementing the `Binding(get:set:)` boilerplate by hand.
    ///
    /// Defined on `ReducerStoreProtocol` (not concretely on `Store<R>`) so it works on any
    /// conforming store — including the connectors' own generic `ParentStore` — with one
    /// implementation, not one per store type.
    ///
    /// - Parameters:
    ///   - keyPath: An optional property on `State` — the binding reads `true` while it's
    ///     non-nil. Doesn't have to be a `@SubState` child; any optional `State` property works
    ///     (e.g. `var alertMessage: String?` for a `.alert(isPresented:)` binding).
    ///   - dismissWhen: Sent to `update()` when the binding is set to `false` — e.g. the user
    ///     swipes back or taps outside a sheet. Typically the same `When` case that clears
    ///     `keyPath` back to `nil`.
    /// - Returns: `true` while `state[keyPath: keyPath] != nil`; setting it to `false` sends
    ///   `dismissWhen`. Setting it to `true` has no effect — presentation is driven by state,
    ///   not by the binding.
    ///
    /// ## Safety
    /// Safe to call on any store reference you already hold — `bind` only reads `state` and
    /// dispatches an event, it does no store resolution of its own. The rule that matters is
    /// how you obtained the store in the first place: an `@ObservedObject`-held reference, or
    /// one resolved via `ReducerRegistryCapture` (what `build<Name>View` is built on), is always
    /// safe regardless of nesting depth — see `ReducerStoreRegistry` for why.
    ///
    /// ## Example
    /// ```swift
    /// struct MyAccountView: View {
    ///     @ObservedObject var store: MyAccountReducer.Store
    ///     var body: some View {
    ///         Text("Account")
    ///             .sheet(isPresented: store.bind(\.signIn, dismissWhen: .userDismissedSignIn)) {
    ///                 // ...
    ///             }
    ///     }
    /// }
    /// ```
    public func bind<Value>(
        _ keyPath: KeyPath<State, Value?>,
        dismissWhen: When
    ) -> Binding<Bool> {
        Binding(
            get: { self.state[keyPath: keyPath] != nil },
            set: { if !$0 { self._dispatch(dismissWhen) } }
        )
    }
}

// MARK: - ReducerEnvironmentCapture

/// Resolves an `@EnvironmentObject` in its own `body` — a normal, eager render context —
/// then hands the already-resolved reference to `content` by direct reference.
///
/// ## The problem this solves
///
/// SwiftUI detaches lazily-evaluated presentation content — a `NavigationLink` destination,
/// `.navigationDestination`, `.sheet`, `.fullScreenCover`, `.popover`, and similar — from the
/// enclosing view hierarchy for environment-propagation purposes. An `@EnvironmentObject`
/// injected between the presenting view's ancestor and the presentation call site is NOT
/// visible inside that lazy closure: resolving `@EnvironmentObject` there crashes with
/// "No ObservableObject of type X found." This isn't specific to any one presentation API —
/// it's the same failure for all of them, because the root cause (lazy evaluation detaching
/// the closure's rendering context) is the same.
///
/// Resolving the environment object here, in a normal (non-lazy) `body`, and passing the
/// already-resolved value into `content` by direct reference sidesteps the lookup entirely —
/// nothing inside `content` ever needs to resolve `@EnvironmentObject` itself, no matter how
/// lazily SwiftUI evaluates it.
///
/// ## Where this alone is NOT enough
/// Owning the presentation control (rendering as an eager sibling, never nested inside a lazy
/// closure) is necessary but confirmed (device-tested, multi-level real app) not sufficient on
/// its own: `.navigationDestination`/`NavigationLink` push results are anchored to the
/// `NavigationStack`/`NavigationView` container's own position, not to wherever the pushing
/// content is currently nested. An `@EnvironmentObject` resolved here is only reachable if
/// `ReducerEnvironmentCapture` itself renders no deeper than that container — true for a
/// single level of push navigation, false a few levels down. `_ReducerChildViewConnector` is
/// built on `ReducerRegistryCapture` instead, which sidesteps this by resolving from a single
/// root-injected `ReducerStoreRegistry` rather than resolving `S` itself via `@EnvironmentObject`
/// at whatever depth this renders — see `ReducerStoreRegistry` for why that's
/// depth-independent. Kept as a public primitive for single-level cases and any other custom
/// use; prefer `ReducerRegistryCapture` for anything that might be reached through more than one
/// level of push navigation.
public struct ReducerEnvironmentCapture<S: ObservableObject, Content: View>: View {
    @EnvironmentObject private var object: S
    private let content: (S) -> Content

    public init(_ type: S.Type = S.self, @ViewBuilder content: @escaping (S) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(object)
    }
}

