# Overview

Explore the core concepts of the Statoscope architecture through examples.

## Choosing an approach

Statoscope ships two patterns for managing a scope's state:

- **Reducer** (`@Reducer`, a static `update()` over a single `State` struct, covered below) — recommended for new features.
- **Statostore** (a class with `@Published` properties) — the easy migration path when you're bringing an existing ViewModel-shaped screen into Statoscope; its shape maps closely onto what a ViewModel already looks like. See <doc:Overview-article-Statostore>.

## Reducer: State + When

Defining a Reducer means defining at least the `State` of your application and the `When` events that may affect it — the same "State[N] + Event[N] = State[N+1]" idea used across unidirectional architectures. Some reducers don't have asynchronous effects, so we'll cover those in the next section. Here's a simple counter:

```swift
@Reducer
struct Counter {
    struct State {
        // Define state member variables
        var viewDisplaysTotalCount: Int = 0
    }

    // Define possible When events affecting state:
    enum When {
        //  case namings are much better with a sentence format:
        case userTappedIncrementButton
        case userTappedDecrementButton
    }

    // @Reducer conformance forces you to implement the static update method:
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount += 1
        case .userTappedDecrementButton:
            state.viewDisplaysTotalCount = max(0, state.viewDisplaysTotalCount - 1)
        }
    }
}
```

A Reducer is a plain struct annotated with `@Reducer` — no class, no `self`. Everything above is one of three parts:

* `State` — every member variable the scope owns, in one struct. Never modified from the outside; instead the view or other components send a `When` event, and `update()` handles the change.
* `When` — an enum defining every event that can occur during this scope's lifetime.
* `static func update(...)` — processes the current state and an incoming event, applying business logic to produce a new state.

The `@Reducer` macro generates `Counter.Store` — a class holding the actual state, conforming to `ObservableObject` for SwiftUI, and exposing the public `send(_:)` method used to forward events. No class needs to be written by hand. `When` events are processed synchronously: state updates immediately after `send(_:)`.

Since we're using it on SwiftUI, see the full view:

```swift
struct CounterView: View {
    @ObservedObject var store = Counter.Store(initialState: Counter.State())
    var body: some View {
        VStack {
            Text("\(store.state.viewDisplaysTotalCount)")
            HStack {
                Button("+") {
                    store.send(.userTappedIncrementButton)
                }
                Button("-") {
                    store.send(.userTappedDecrementButton)
                }
            }
        }
    }
}
```

There will usually be 3 big groups of When cases. See how we intentionally selected a "sentence" format for our cases so it helps describe the app's behavior:
* User driven actions: userTappedIncrementButton, userDismissedAlert…
* System: systemLoadedTheScreen, systemMovedAppToBackground…
* Effects feedback: next topic is all about effects… will get there soon

With sentence-like State and When naming, an enum-backed When, and the testing helpers included in the library, testing looks as straightforward as this:

```swift
final class StatoscopeExample1: XCTestCase {
    func testCounterUserFlow() throws {
        try Counter.Store.GIVEN {
            Counter.Store(initialState: Counter.State())
        }
        .THEN(\.state.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.state.viewDisplaysTotalCount, equals: 1)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.state.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.state.viewDisplaysTotalCount, equals: 0)
        .runTest()
    }
}
```

Note the `.state.` prefix on every KeyPath — since state lives in one struct, tests always go through it. These test descriptions accomplish several things:
* Describe the behavior of the application: accomplishing ACCEPTANCE AS CODE
* Provide out-of-the-box testing coverage
* Document common and supported scenarios — see it further in the testing section and using FORK

## Reducer: State + When + Effects

Side effects are events that may result in later state changes. To keep using the pattern used until now (State[N] + Event[N] = State[N+1]), we split an asynchronous task into 2 different When cases: the one that starts it, and the one receiving the asynchronous result.

Let's see an example, starting with the test:

```swift
func testCounterExample2UserFlow() throws {
    try CloudCounterReducer.Store.GIVEN {
        CloudCounterReducer.Store(initialState: CloudCounterReducer.State())
    }
    .THEN(\.state.viewDisplaysTotalCount, equals: 0)
    .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
    // Increment
    .WHEN(.userTappedIncrementButton)
    .THEN(\.state.viewDisplaysTotalCount, equals: 1)
    .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: true)
    .WHEN(.networkPostCompleted(DTO(count: 1)))
    .THEN(\.state.viewDisplaysTotalCount, equals: 1)
    .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
    .runTest(assertNoPendingEffects: false)
}
```

Now let's look at the reducer:

```swift
struct DTO: Codable, Equatable {
    let count: Int
}

enum Network {
    static func buildURLRequestPosting(dto: DTO) throws -> URLRequest {
        guard let url = URL(string: "http://statoscope.com") else {
            throw InvalidStateError()
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(dto)
        return request
    }
}

@Reducer
struct CloudCounterReducer {
    struct State {
        var viewDisplaysTotalCount: Int = 0
        var viewShowsLoadingAndDisablesButtons: Bool = false
    }

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(DTO)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount += 1
            state.viewShowsLoadingAndDisablesButtons = true
            effectsState.enqueue(
                AnyEffect {
                    let request = try Network.buildURLRequestPosting(dto: DTO(count: state.viewDisplaysTotalCount))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        case .userTappedDecrementButton:
            guard state.viewDisplaysTotalCount > 0 else { return }
            state.viewDisplaysTotalCount -= 1
            state.viewShowsLoadingAndDisablesButtons = true
            /** Same enqueue pattern as in userTappedIncrementButton */
        case .networkPostCompleted(let remoteCounter):
            state.viewShowsLoadingAndDisablesButtons = false
            state.viewDisplaysTotalCount = remoteCounter.count
        }
    }
}
```

`effectsState` — the parameter `update()` receives above, alongside `state` — is where asynchronous tasks live: `effectsState.enqueue(_:)` triggers one, as shown in `.userTappedIncrementButton`. It also provides `effectsState.effects`, the list of ongoing effects, and `effectsState.cancelEffect(where:)` to cancel specific ones (both used a couple of examples down). The generated `Counter.Store` manages effect lifecycle the same way a Statostore does: when the `Store` is released, every associated effect is canceled, so the store's lifespan defines the effects' lifespan.

The library heavily relies on Apple's concurrency library — it MUST be used to implement your own Effects. However it's recommended to use typed (non-anonymous) effects to achieve testability, cancellability and observability. See how to do it:

1. Define an Effect — this type doesn't know or care which state-management pattern enqueues it:
```swift
struct NetworkEffect<Response: Decodable>: Effect {
    let request: URLRequest
    func runEffect() async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    }
}
```

2. Use it in `update()`:
```swift
static func update(
    _ when: When,
    state: inout State,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies
) throws {
    switch when {
    case .userTappedIncrementButton:
        state.viewDisplaysTotalCount += 1
        state.viewShowsLoadingAndDisablesButtons = true
        effectsState.enqueue(
            NetworkEffect<DTO>(request: request)
                .map(When.networkPostCompleted)
        )
        /** … */
    }
}
```

3. Test state changes and effect triggering together. Effects aren't executed in a test environment — they're added to an enqueued list to check correct enqueueing, and the next WHEN cleans up the queue:
```swift
.WHEN(.userTappedDecrementButton)
.THEN { sut in
    XCTAssertEqualEffects(sut, NetworkEffect<DTO>(request: try Network.buildURLRequestPosting(dto: DTO(count: 1))))
}
```

4. Read which effects are ongoing, and/or cancel them:
```swift
static func update(
    _ when: When,
    state: inout State,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies
) throws {
    switch when {
    case .userTappedIncrementButton:
        state.viewDisplaysTotalCount += 1
        state.viewShowsLoadingAndDisablesButtons = true
        if nil != effectsState.effects.first(where: { $0 is NetworkEffect<DTO> }) {
            effectsState.cancelEffect(where: { $0 is NetworkEffect<DTO> })
        }
        effectsState.enqueue(
            NetworkEffect<DTO>(request: request)
                .map(When.networkPostCompleted)
        )
        /** … */
    }
}
```

We've covered the basics of triggering, reading, canceling and testing Effects with Reducer. In the following topics we'll discuss some advanced usages and tricks for great Effects programming.

## App state as scope composition: @SubState + @SuperState

A single Reducer handling an entire screen tends to grow into a "god struct": feature toggles, list state, detail state, favorites — all mixed into one `When` enum and one `update()` switch. Statoscope lets you split that into a tree of smaller Reducers instead, declared directly on the `State` struct — no separate property wrapper on a class, no manual wiring step.

**`@SubState`** declares that a scope owns a child scope:

```swift
@Reducer
struct NewsFeedListReducer {
    struct State {
        var loadedArticles: [Article] = []
        @SubState var readingArticle: NewsFeedArticleReducer.State?
    }

    enum When {
        case networkListDidFinish([Article])
        case navigateToArticle(id: String)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .networkListDidFinish(let articles):
            state.loadedArticles = articles
        case .navigateToArticle(let id):
            // creates and wires the child Store
            state.readingArticle = NewsFeedArticleReducer.State(articleId: id)
        }
    }
}
```

Assigning to `state.readingArticle` creates the child `Store` and wires it into the injection tree; assigning `nil` releases it. The parent reads the live child through the macro-generated `store.children.readingArticle` accessor.

**`@SuperState`** is the child's side of the same relationship — a read-only snapshot of an ancestor's state, injected fresh before every `update()` call rather than passed in by hand:

```swift
@Reducer
struct NewsFeedArticleReducer {
    struct State {
        @SuperState var parentList: NewsFeedListReducer.State
        var article: Article?
    }

    enum When { case favorite }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .favorite:
            // read shared state from the parent without it being handed down explicitly
            let favoritesEnabled = state.parentList.favoritesEnabled
            // ...
        }
    }
}
```

`@SuperState` is a **value snapshot**, not a live reference — it's read-only, so assigning to it is a compile error. It resolves the same way `@ReducerInjected`/`ReducerDependencies` resolve a plain dependency (see Dependency Injection), just yielding a scope's state instead of an arbitrary value.

Splitting scopes this way keeps each `State`/`When` focused on one concern, makes each scope independently testable via `GIVEN`/`WHEN`/`THEN`, and lets SwiftUI views compose the same way the scopes do. The tradeoff is the same one classic Statostore composition makes: state that's genuinely shared across siblings (like `favoritesEnabled` above) has to flow through `@SuperState`/`@SubState` or dependency injection rather than living in one convenient place — usually worthwhile once a screen has grown past two or three concerns, not something to reach for on day one.

## Reducers talking to each other: MiddlewareReducer

`@SubState`/`@SuperState` only move data in one direction each: a parent hands a value down when it creates a child, and a child can read a read-only snapshot of an ancestor. Neither lets a child's *event* change what a parent owns. That's what `MiddlewareReducer` is for: a parent intercepts an event from a child **before** the child processes it, and reacts on its own `update()` instead.

Say favoriting an article needs to update a single, shared list of favorites — not a copy living separately in both `NewsFeedListReducer` and `NewsFeedArticleReducer`. Move ownership to the parent and let it intercept the child's event:

```swift
@Reducer
struct NewsFeedListReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var loadedArticles: [Article] = []
        var favorites: Set<String> = []
        @SubState var readingArticle: NewsFeedArticleReducer.State?
    }

    enum When {
        case favorited(id: String)
        // ...
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .favorited(let id):
            state.favorites.formSymmetricDifference([id])  // toggle membership
        }
    }

    // Runs BEFORE `readingArticle`'s own update() sees `.favorite` — see the ordering note below.
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        guard let articleWhen = childWhen as? NewsFeedArticleReducer.When,
              case .favorite = articleWhen else { return .pass }
        // The child no longer owns `favorites` at all, so consume the event here rather
        // than still forwarding it to a child that has nothing left to do with it.
        return .intercept(.favorited(id: childState.article?.id ?? ""))
    }
}
```

`updateSubstate` returns a `SubstateOutcome<When>`, one of three cases: `.pass` (not this reducer's concern, forward the event to the child as usual), `.react(when)` (send `when` to this reducer's own `update()`, **then still forward** the original event to the child), or `.intercept(when)` (send `when`, but do **not** forward it — used above, since the child has nothing left to react to). Reach for `.intercept` whenever forwarding afterward would be pointless or unsafe — most commonly because the reaction just replaced or tore down the very child subtree the event came from.

The parenthetical above — "runs before the child's own `update()`" — is not a minor implementation detail. If a child's own handler for that same event reads a value the parent's `.react`/`.intercept` reaction just changed (say, a `submitting` flag computed from a parent-owned field), it will see the value *after* the reaction already ran, not before, because the reaction happens first. A guard like `!state.submitting` inside the handler for the very event that flips `submitting` to `true` will reject every legitimate call. If a child needs a "not already in progress" guard, it needs its own, locally-owned flag — not one read live off the parent.

One more thing worth calling out about `@SuperState` combined with `MiddlewareReducer`: a child can point `@SuperState` past its direct parent, straight at any ancestor by type — `NewsFeedArticleReducer` could declare `@SuperState var rootFeed: NewsFeedReducer.State` even if its direct parent is `NewsFeedListReducer`, and it would resolve correctly (`MiddlewareReducer`'s own event-interception works the same way — an ancestor two levels up can intercept a grandchild's event with no relay code in the reducer in between). That skip-level read is safe *only* when the data lives directly on the target ancestor's own `State` — an ancestor's state is committed the instant its own `update()` returns, so a snapshot of it is never stale. It is **not** safe to skip a level to read a field that itself merely mirrors some *other*, independently-updated descendant's data: that mirrored copy only refreshes when the reducer holding it processes an event of its own, which can leave it stale exactly when it matters. Always point `@SuperState` at whichever reducer actually **owns** the data.
