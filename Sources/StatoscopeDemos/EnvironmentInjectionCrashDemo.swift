//
//  EnvironmentInjectionCrashDemo.swift
//  Statoscope
//
//  Demonstrates the @EnvironmentObject propagation failure that occurs when a child-store
//  connector is resolved lazily inside navigation/presentation content, and the fix:
//  `ReducerStoreRegistry` — a single object injected once, at the true root, that every level
//  of the reducer tree registers itself into, so `build<Name>View(content:)` can resolve its
//  own live parent store safely regardless of how many levels of push/presentation deep it's
//  reached. See `ReducerStoreRegistry`'s own documentation in AutoConnectedView.swift for the
//  full mechanism.
//
//  Preview "Crash reproduction": shows the ORIGINAL bug (hand-rolled, raw @EnvironmentObject,
//  bypassing the library entirely) that motivated this whole design. The library's own
//  `_ReducerChildViewConnector` no longer reproduces this exact crash — it fails softer
//  (renders nothing) if misconfigured, rather than a hard fatalError, because it resolves
//  through the registry rather than a raw @EnvironmentObject lookup.
//
//  NOTE: Xcode Previews may not crash here because the Preview host injects its own
//  environment. Run on a simulator or device to see the crash.
//

#if DEBUG
import SwiftUI
import Statoscope

// MARK: - Minimal stores for the historical crash repro

/// Minimal ReducerStoreProtocol conforming parent store
final class _DemoParentStore: ObservableObject, ReducerStoreProtocol {
    struct State {
        var title: String = "Parent"
        var child: _DemoChildStore? = nil
    }
    enum When {
        case showChild
        case hideChild
    }

    @Published var state: State = State()

    init() {}

    func _dispatch(_ when: When) {
        switch when {
        case .showChild:
            state.child = _DemoChildStore()
        case .hideChild:
            state.child = nil
        }
        objectWillChange.send()
    }

    // KeyPath accessor mirroring what @Reducer macro generates
    var child: _DemoChildStore? { state.child }
}

/// Minimal ReducerStoreProtocol conforming child store
final class _DemoChildStore: ObservableObject, ReducerStoreProtocol {
    struct State {
        var label: String = "Child view rendered ✓"
    }
    enum When {}

    @Published var state: State = State()

    func _dispatch(_ when: When) {}
}

/// The child view — a StoreViewProtocol-like view
private struct _DemoChildPresentedView: View {
    let model: _DemoChildStore.State
    let send: (_DemoChildStore.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Text("@EnvironmentObject was resolved successfully")
                .foregroundColor(.green)
        }
        .padding()
    }
}

// MARK: - Preview: the ORIGINAL bug, hand-rolled, bypassing the library

/// Hand-rolls the exact pattern that used to crash: a connector resolving `@EnvironmentObject`
/// lazily, inside a `NavigationLink` destination closure. This is the historical motivation for
/// `ReducerStoreRegistry` — kept as a standalone repro, independent of the library's own
/// (now registry-based, no-longer-hard-crashing) connector.
private struct _HandRolledUnsafeConnector: View {
    @EnvironmentObject private var parentStore: _DemoParentStore
    let content: (_DemoChildStore.State, @escaping (_DemoChildStore.When) -> Void) -> _DemoChildPresentedView

    var body: some View {
        if let childStore = parentStore.child {
            content(childStore.state, childStore._dispatch)
        }
    }
}

private struct _DemoParentView: View {
    let model: _DemoParentStore.State
    let send: (_DemoParentStore.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            NavigationLink(
                isActive: Binding(
                    get: { model.child != nil },
                    set: { if !$0 { send(.hideChild) } }
                ),
                destination: {
                    // ← body evaluated here, AFTER push.
                    // On device: @EnvironmentObject lookup for _DemoParentStore fails → CRASH
                    _HandRolledUnsafeConnector(content: _DemoChildPresentedView.init)
                }
            ) {
                EmptyView()
            }
            #if !os(macOS)
            .isDetailLink(false)
            #endif

            Text("↑ Tapping the button above will crash on device/simulator\nbut may survive in Xcode Preview")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Demo — original bug (hand-rolled)")
    }
}

private struct _StoreViewBridge: View, StoreViewProtocol {
    typealias State = _DemoParentStore.State
    typealias When = _DemoParentStore.When

    let model: State
    let send: (When) -> Void

    init(model: State, send: @escaping (When) -> Void) {
        self.model = model
        self.send = send
    }

    var body: some View {
        // INTENTIONALLY the anti-pattern: NavigationView wraps ReducerStoreView, rather than
        // the other way around (as ReducerStoreView's own doc requires) — this is what recreates
        // the original bug. Every other preview in this file follows the documented convention.
        NavigationView { _DemoParentView(model: model, send: send) }
    }
}

#Preview("Crash reproduction — run on simulator to see crash") {
    let store = _DemoParentStore()
    return ReducerStoreView<_DemoParentStore, _StoreViewBridge>(store: store)
}

// MARK: - The fix: ReducerStoreRegistry, resolved via build<Name>View(content:)
//
// `build<Name>View(content:)` — the only method the macro generates — is safe to use directly
// as the content of `.sheet`/`.fullScreenCover`/`NavigationLink`/`.navigationDestination`
// (or embedded inline), at any nesting depth. Pair it with `store.bind(_:dismissWhen:)` /
// `Reducer.bind(_:in:dismissWhen:send:)` for the presentation `Binding<Bool>` — this connector
// only produces content, it has no opinion on how you present it.

/// `.sheet` — bind + buildChildView, composed directly at the call site.
private struct _DemoFixedSheetParentView: View {
    let model: _DemoParentStore.State
    let send: (_DemoParentStore.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Present child") {
                send(.showChild)
            }

            Text("↑ Works on device/simulator — .sheet + bind + _ReducerChildViewConnector")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Demo — .sheet")
        .sheet(
            isPresented: Binding(
                get: { model.child != nil },
                set: { if !$0 { send(.hideChild) } }
            )
        ) {
            _ReducerChildViewConnector<_DemoParentStore, _DemoChildStore, _DemoChildPresentedView>(
                storeKeyPath: \.child,
                content: _DemoChildPresentedView.init
            )
        }
    }
}

private struct _FixedSheetStoreViewBridge: View, StoreViewProtocol {
    typealias State = _DemoParentStore.State
    typealias When = _DemoParentStore.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationView { _DemoFixedSheetParentView(model: model, send: send) }
    }
}

#Preview("Macro fix — .sheet") {
    let store = _DemoParentStore()
    return ReducerStoreView<_DemoParentStore, _FixedSheetStoreViewBridge>(store: store)
}

/// `.navigationDestination` — the `NavigationStack` case.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _DemoFixedNavigationDestinationParentView: View {
    let model: _DemoParentStore.State
    let send: (_DemoParentStore.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            Text("↑ Works on device/simulator — .navigationDestination + bind + _ReducerChildViewConnector")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Demo — .navigationDestination")
        .navigationDestination(
            isPresented: Binding(
                get: { model.child != nil },
                set: { if !$0 { send(.hideChild) } }
            )
        ) {
            _ReducerChildViewConnector<_DemoParentStore, _DemoChildStore, _DemoChildPresentedView>(
                storeKeyPath: \.child,
                content: _DemoChildPresentedView.init
            )
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _FixedNavigationDestinationStoreViewBridge: View, StoreViewProtocol {
    typealias State = _DemoParentStore.State
    typealias When = _DemoParentStore.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationStack { _DemoFixedNavigationDestinationParentView(model: model, send: send) }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
#Preview("Macro fix — .navigationDestination") {
    let store = _DemoParentStore()
    return ReducerStoreView<_DemoParentStore, _FixedNavigationDestinationStoreViewBridge>(store: store)
}

// MARK: - Alternative: ReducerEnvironmentCapture (single-level only, no registry)
//
// A hand-rolled pattern that doesn't depend on ReducerStoreRegistry at all: the connector OWNS
// the NavigationLink itself, rendered as a normal sibling (never inside a lazy closure), so its
// @EnvironmentObject lookup always runs eagerly. Safe for a single level of push; NOT safe once
// nested more than one level deep (see ReducerEnvironmentCapture's own documentation) — kept as
// a reference for what to reach for if you ever need to avoid the registry for some reason.

/// Safe destination: uses @ObservedObject (direct reference), never @EnvironmentObject.
private struct _DemoChildStoreView: View {
    @ObservedObject var parentStore: _DemoParentStore

    var body: some View {
        if let childStore = parentStore.child {
            _DemoObservingChildView(store: childStore)
        }
    }
}

private struct _DemoObservingChildView: View {
    @ObservedObject var store: _DemoChildStore

    var body: some View {
        _DemoChildPresentedView(model: store.state, send: store._dispatch)
            .environmentObject(store)
    }
}

private struct _DemoWorkingParentView: View {
    let model: _DemoParentStore.State
    let send: (_DemoParentStore.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            ReducerEnvironmentCapture(_DemoParentStore.self) { parentStore in
                NavigationLink(
                    isActive: Binding(
                        get: { parentStore.child != nil },
                        set: { if !$0 { parentStore._dispatch(.hideChild) } }
                    ),
                    destination: {
                        _DemoChildStoreView(parentStore: parentStore)
                    }
                ) { EmptyView() }
                #if !os(macOS)
                .isDetailLink(false)
                #endif
            }

            Text("↑ Works on device/simulator — no crash, no registry needed (single level only)")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Demo — ReducerEnvironmentCapture (no registry)")
    }
}

private struct _WorkingStoreViewBridge: View, StoreViewProtocol {
    typealias State = _DemoParentStore.State
    typealias When = _DemoParentStore.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationView { _DemoWorkingParentView(model: model, send: send) }
    }
}

#Preview("Alternative — ReducerEnvironmentCapture, no registry (single level only)") {
    let store = _DemoParentStore()
    return ReducerStoreView<_DemoParentStore, _WorkingStoreViewBridge>(store: store)
}

// MARK: - Real @Reducer usage — the way a library consumer actually writes this
//
// Everything above hand-conforms minimal stores to ReducerStoreProtocol, to keep the repro
// self-contained. It proves the connector works, but it doesn't exercise what a real consumer
// writes: a `@Reducer`/`@SubState` parent-child pair, calling the macro-generated
// `buildChildView` method paired with `bind`. This section does that instead — same domain
// (title, "Navigate to child", child label), real `@Reducer` types, real macro-generated call
// sites.

@Reducer
private struct _RealDemoGrandchildReducer {
    struct State {
        var label: String = "Grandchild view rendered ✓ (2 pushes deep)"
    }
    enum When {}

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {}
}

@Reducer
private struct _RealDemoChildReducer {
    struct State {
        var label: String = "Child view rendered ✓"
        @SubState var grandchild: _RealDemoGrandchildReducer.State?
    }
    enum When {
        case showGrandchild
        case hideGrandchild
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showGrandchild:
            state.grandchild = _RealDemoGrandchildReducer.State()
        case .hideGrandchild:
            state.grandchild = nil
        }
    }
}

@Reducer
private struct _RealDemoParentReducer {
    struct State {
        var title: String = "Parent"
        @SubState var child: _RealDemoChildReducer.State?
        // Not a child scope — plain data on this reducer's own State. Presenting UI driven
        // by this needs no live store, no @EnvironmentObject, no registry lookup:
        // `Reducer.bind(_:in:dismissWhen:send:)` is a direct fit.
        var infoMessage: String?
    }
    enum When {
        case showChild
        case hideChild
        case showInfo
        case dismissInfo
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showChild:
            state.child = _RealDemoChildReducer.State()
        case .hideChild:
            state.child = nil
        case .showInfo:
            state.infoMessage = "This alert's Binding was built by Reducer.bind — no live store involved."
        case .dismissInfo:
            state.infoMessage = nil
        }
    }
}

private struct _RealDemoChildPresentedView: View {
    let model: _RealDemoChildReducer.State
    let send: (_RealDemoChildReducer.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Text("@EnvironmentObject was resolved successfully")
                .foregroundColor(.green)
        }
        .padding()
    }
}

/// The real macro-generated fix: `bind` + `buildChildView(content:)`, paired with `.sheet`.
private struct _RealDemoFixedParentView: View {
    let model: _RealDemoParentReducer.State
    let send: (_RealDemoParentReducer.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Present child") {
                send(.showChild)
            }

            Text("↑ Works on device/simulator — real bind + buildChildView, via .sheet")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Real @Reducer — macro fix (.sheet)")
        .sheet(isPresented: _RealDemoParentReducer.bind(\.child, in: model, dismissWhen: .hideChild, send: send)) {
            _RealDemoParentReducer.buildChildView(content: _RealDemoChildPresentedView.init)
        }
    }
}

private struct _RealDemoFixedStoreViewBridge: View, StoreViewProtocol {
    typealias State = _RealDemoParentReducer.State
    typealias When = _RealDemoParentReducer.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationView { _RealDemoFixedParentView(model: model, send: send) }
    }
}

private func _makeRealDemoFixedPreview() -> some View {
    let store = _RealDemoParentReducer.Store(initialState: _RealDemoParentReducer.State())
    return ReducerStoreView<_RealDemoParentReducer.Store, _RealDemoFixedStoreViewBridge>(store: store)
}

#Preview("Real @Reducer — macro fix (.sheet)") {
    _makeRealDemoFixedPreview()
}

/// The real macro-generated `NavigationStack` case: `bind` + `buildChildView(content:)`, paired
/// with `.navigationDestination`.
///
/// Also demonstrates `Reducer.bind(_:in:dismissWhen:send:)` — the `model`/`send`-based static
/// helper — for the `.alert` below, needed because this `StoreViewProtocol` view only ever has
/// `model`/`send` in scope, never a live `store` to call the instance-based `bind` on.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoFixedNavigationStackParentView: View {
    let model: _RealDemoParentReducer.State
    let send: (_RealDemoParentReducer.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            Text("↑ Works on device/simulator — real bind + buildChildView, via .navigationDestination")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)

            Button("Show info alert (Reducer.bind, no store needed)") {
                send(.showInfo)
            }
        }
        .padding()
        .navigationTitle("Real @Reducer — macro fix (NavigationStack)")
        .alert(
            "Info",
            isPresented: _RealDemoParentReducer.bind(\.infoMessage, in: model, dismissWhen: .dismissInfo, send: send),
            actions: {},
            message: { Text(model.infoMessage ?? "") }
        )
        .navigationDestination(
            isPresented: _RealDemoParentReducer.bind(\.child, in: model, dismissWhen: .hideChild, send: send)
        ) {
            _RealDemoParentReducer.buildChildView(content: _RealDemoChildPresentedView.init)
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoFixedNavigationStackStoreViewBridge: View, StoreViewProtocol {
    typealias State = _RealDemoParentReducer.State
    typealias When = _RealDemoParentReducer.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationStack { _RealDemoFixedNavigationStackParentView(model: model, send: send) }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private func _makeRealDemoFixedNavigationStackPreview() -> some View {
    let store = _RealDemoParentReducer.Store(initialState: _RealDemoParentReducer.State())
    return ReducerStoreView<_RealDemoParentReducer.Store, _RealDemoFixedNavigationStackStoreViewBridge>(store: store)
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
#Preview("Real @Reducer — macro fix (NavigationStack / .navigationDestination)") {
    _makeRealDemoFixedNavigationStackPreview()
}

// MARK: - Multi-level (parent → child → grandchild) — the actual reported failure

// Every demo above is a single level of push (root parent → one direct child) — which is
// exactly what did NOT reproduce the confirmed real-app crash. The real failure only shows up
// a level deeper: a child, reached via one push, that itself pushes a grandchild. This section
// exercises that — parent pushes child, and *from inside that pushed content* child pushes
// grandchild — the scenario `ReducerStoreRegistry` exists for (see its documentation).
// Device-confirmed working, with `.navigationDestination` consistently at both levels.

private struct _RealDemoGrandchildPresentedView: View {
    let model: _RealDemoGrandchildReducer.State
    let send: (_RealDemoGrandchildReducer.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)
            Text("Registry-resolved 2 levels deep — no crash")
                .foregroundColor(.green)
        }
        .padding()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoMultiLevelChildView: View {
    let model: _RealDemoChildReducer.State
    let send: (_RealDemoChildReducer.When) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.label)
                .font(.headline)

            Button("Navigate to grandchild") {
                send(.showGrandchild)
            }
        }
        .padding()
        .navigationTitle("Child (1 push deep)")
        .navigationDestination(
            isPresented: _RealDemoChildReducer.bind(\.grandchild, in: model, dismissWhen: .hideGrandchild, send: send)
        ) {
            _RealDemoChildReducer.buildGrandchildView(content: _RealDemoGrandchildPresentedView.init)
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoMultiLevelParentView: View {
    let model: _RealDemoParentReducer.State
    let send: (_RealDemoParentReducer.When) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(model.title)
                .font(.title)

            Button("Navigate to child") {
                send(.showChild)
            }

            Text("↑ Push, then push again from inside the pushed content — 2 levels deep")
                .font(.caption)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Real @Reducer — multi-level (parent)")
        .navigationDestination(
            isPresented: _RealDemoParentReducer.bind(\.child, in: model, dismissWhen: .hideChild, send: send)
        ) {
            _RealDemoParentReducer.buildChildView(content: _RealDemoMultiLevelChildView.init)
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct _RealDemoMultiLevelStoreViewBridge: View, StoreViewProtocol {
    typealias State = _RealDemoParentReducer.State
    typealias When = _RealDemoParentReducer.When
    let model: State
    let send: (When) -> Void
    init(model: State, send: @escaping (When) -> Void) {
        self.model = model; self.send = send
    }
    var body: some View {
        NavigationStack { _RealDemoMultiLevelParentView(model: model, send: send) }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private func _makeRealDemoMultiLevelPreview() -> some View {
    let store = _RealDemoParentReducer.Store(initialState: _RealDemoParentReducer.State())
    return ReducerStoreView<_RealDemoParentReducer.Store, _RealDemoMultiLevelStoreViewBridge>(store: store)
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
#Preview("Real @Reducer — multi-level push (parent → child → grandchild)") {
    _makeRealDemoMultiLevelPreview()
}

#endif
