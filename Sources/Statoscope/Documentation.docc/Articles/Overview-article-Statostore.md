# Statostore Overview

Explore the core concepts of the Statostore pattern through examples.

Using the recommended pattern for new features instead? See <doc:Overview-article> for the Reducer walkthrough. Statostore is the migration path for bringing an existing `ObservableObject`/ViewModel-shaped screen into Statoscope — its `@Published`-properties-plus-methods shape maps closely onto what a ViewModel already looks like.

## Statoscope Basics

### The Statostore Object

The `Statostore` object manages your application state, or a portion (scope) of it.

It is a class object with the following components:

* A `When` type (typically an enum), which defines the events that occur within your application's scope.
* Member variables that represent the state of the application/scope. These variables should never be modified directly. Instead, the view or other components should send a `When` event to the scope, and the scope's `update` method will handle state changes.
* A public `send` method that forwards events for scope processing.
* An internal `update` method that processes the current state and incoming `When` event, applying the business logic to produce a new state.

The `When` events are processed synchronously, meaning the state is updated immediately after sending an event. Asynchronous tasks, called **Effects**, are triggered as side effects. Each effect has a corresponding completion `When` event. Thus, a typical asynchronous task introduces two `When` events: one to start the effect and one to handle its completion.

#### Asynchronous Tasks

The `Statostore` object is intentionally designed as a class to manage the lifecycle of ongoing effects. When a `Statostore` instance is released, all associated effects are canceled. This ensures that the lifespan of the object defines the lifespan of the effects.

For asynchronous tasks, the Statoscope object provides:

* An `effectsState.enqueue(_:)` method to trigger asynchronous tasks during state updates.
* `effectsState.effects`, the list of ongoing effects.
* Automatic cancellation of effects upon releasing the scope.
* `effectsState.cancelEffect(where:)` to cancel specific ongoing effects.


## State + When

Defining a scope means defining at least the State of your application and the When events that may affect it. Some scopes don’t have asynchronous effects, so we will discuss Effects later. See it all together in a simple Statoscope:

```swift
fileprivate final class Counter: Statostore {
    
    // Define state member variables
    var viewDisplaysTotalCount: Int = 0
    
    // Define possible When events affecting state:
    enum When {
        //  case namings are much better with a sentence format:
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    // Statoscope conformance forces you to implement the update method:
    func update(_ when: When) throws { throw NotImplemented() }
}
```

Here we define a common simple application sample commonly used in unidirectional architectures: a counter. It displays the counter and a button to increase or decrease it. 

Since we’re using it on SwiftUI, see the full Statoscope + View implementation:

```swift
fileprivate final class Counter: Statostore, ObservableObject {
    
    // Define state member variables, indicate which ones update the ui with Published
    @Published var viewDisplaysTotalCount: Int = 0
    
    // Define possible When events affecting state:
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
        case .userTappedDecrementButton:
            viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
        }
    }
}

fileprivate struct CounterView: View {
    @ObservedObject var model = Counter()
    var body: some View {
        VStack {
            Text("\(model.viewDisplaysTotalCount)")
            HStack {
                Button("+") {
                    model.send(.userTappedIncrementButton)
                }
                Button("-") {
                    model.send(.userTappedDecrementButton)
                }
            }
        }
    }
}

```

*State* is expressed with member variables, as usually done in other SwiftUI design patterns that use ObservableObject. This is an important design decision to make the transition to Statoscope smoother from other development patterns.

```swift
    @Published var viewDisplaysTotalCount: Int = 0
```

*When* type enumerates the events that may take place in your app/screen. 

```swift
enum When {
    case userTappedIncrementButton
    case userTappedDecrementButton
}
```

There will usually be 3 big groups of the when cases. See how we intentionally selected a “sentence” format for our cases so it will help you describing the app behavior:
* User driven actions: userTappedIncrementButton, userDismissedAlert…
* System: systemLoadedTheScreen, systemMovedAppToBackground…
* Effects feedback: next topic is all about effects… will get there soon

At the core design principle of the library we’ve added the testability principle, and we want to introduce it as soon as possible. When using sentence-like typing of the State and When events, the fact that the whens are an enum, and using some testing sugar helpers included in the library, testing looks as straightforward as this:

```swift
final class StatoscopeExample1: XCTestCase {
    func testCounterUserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .runTest()
    }
}
```

These test description accomplishes several things:
* Describes the behavior of the application: accomplishing ACCEPTANCE AS CODE
* Provides an out-of-the-box testing coverage
* Documents common and supported scenarios. See it further in the testing section and using FORK

## State + When … + Effect

Side effects of our source code are events that may result in later state changes. These Effects are important to the Statoscope architecture. To keep using the pattern used until now (State[N] + Event[N] = State[N+1]), we will split an asynchronous task as 2 different When cases: the one that starts the asynchronous task, and the one receiving of the asynchronous result. 

Let’s see an example, but we will start by looking at the tests first:

```swift
func testCounterExample2UserFlow() throws {
    try Counter.GIVEN {
        Counter()
    }
    .THEN(\.viewDisplaysTotalCount, equals: 0)
    .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
    // Increment
    .WHEN(.userTappedIncrementButton)
    .THEN(\.viewDisplaysTotalCount, equals: 1)
    .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
    .WHEN(.networkPostCompleted(DTO(count: 1)))
    .THEN(\.viewDisplaysTotalCount, equals: 1)
    .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
    .runTest()
}
```

We hope the test above explains the behavior of the current example, it’s one of the main goals of the Statoscope architecture. Now, let’s take a look at the scope:

```swift
static func buildURLRequestPosting(dto: Example2.DTO) throws -> URLRequest {
    guard let url = URL(string: "http://statoscope.com") else {
        fatalError()
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(dto)
    return request
}

struct DTO: Codable {
    let count: Int
}

final class Counter: Statostore, ObservableObject {
    
    @Published var viewDisplaysTotalCount: Int = 0
    @Published var viewShowsLoadingAndDisablesButtons: Bool = false
    
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(DTO)
    }
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
            viewShowsLoadingAndDisablesButtons = true
            effectsState.enqueue(
                AnyEffect {
                    let request = try buildURLRequestPosting(dto: DTO(count: self.viewDisplaysTotalCount))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        case .userTappedDecrementButton:
            guard viewDisplaysTotalCount > 0 else {
                return
            }
            viewDisplaysTotalCount = viewDisplaysTotalCount - 1
            viewShowsLoadingAndDisablesButtons = true
            /** Same enqueue pattern as in userTappedIncrementButton*/
        case .networkPostCompleted(let remoteCounter):
            viewShowsLoadingAndDisablesButtons = false
            viewDisplaysTotalCount = remoteCounter.count
        }
    }
}
```

In the example above we trigger an anonymous effect using `effectsState.enqueue(_:)`. The Statoscope library heavily relies on Apple's concurrency library, it MUST be used to implement your own Effects.
However it’s recommended to use typed (non-anonymous effects) to achieve: testability, cancellability and observability. See how to do it:

1. Define an Equatable Effect:
```swift
struct NetworkEffect<Response: Decodable>: Effect {
    let request: URLRequest
    func runEffect() async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    }
}
```

2. Use it in your update method
```swift
func update(_ when: When) throws {
    switch when {
    case .userTappedIncrementButton:
        viewDisplaysTotalCount = viewDisplaysTotalCount + 1
        viewShowsLoadingAndDisablesButtons = true
        effectsState.enqueue(
            NetworkEffect<DTO>(request: request)
                .map(When.networkPostCompleted)
        )
        /** … */
    }
}
```

3. Now you can test not only state changes but also effects triggering. Please note Effects in a test environment are not executed, they’re just added to an enqueued list to check correct enqueueing, but never executed. Subsequent WHEN execution will clean up the queue. See how to test our example:
```swift
.WHEN(.userTappedDecrementButton)
.THEN { sut in
    XCTAssertEqualEffects(sut, NetworkEffect<DTO>(request: try buildURLRequestPosting(dto: DTO(count: 1))))
}
```

4. And you can also read which ongoing effects are in the current state, and/or cancel them:
```swift
        func update(_ when: When) throws {
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount = viewDisplaysTotalCount + 1
                viewShowsLoadingAndDisablesButtons = true
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

We’ve covered the basic of triggering, reading, canceling and testing Effects on Statoscope. In the following topics we’ll discuss some advanced usages and tricks for great Effects programming

## App state as Statoscope composition: Superscope + Subscope

A single `Statostore` handling an entire screen tends to grow into a "god object": feature toggles, list state, detail state, favorites — all mixed into one `When` enum and one `update()` switch. Statoscope lets you split that into a tree of smaller scopes instead, connected with two property wrappers.

**`@Subscope`** declares that a scope owns a child scope:

```swift
final class NewsFeedList: Statostore, ObservableObject {
    @Published var loadedArticles: [Article] = []
    @Subscope var readingArticle: NewsFeedArticle?

    enum When {
        case networkListDidFinish([Article])
        case navigateToArticle(id: String)
    }

    func update(_ when: When) throws {
        switch when {
        case .networkListDidFinish(let articles):
            loadedArticles = articles
        case .navigateToArticle(let id):
            readingArticle = NewsFeedArticle(articleId: id)   // creates and wires the child scope
        }
    }
}
```

Assigning to `readingArticle` creates the child scope and links it into the injection tree; assigning `nil` releases it. The parent can read and observe the live child directly through the property.

**`@Superscope`** is the child's side of the same relationship — a weak, read-only link back up to an ancestor scope, resolved through the injection tree rather than passed in by hand:

```swift
final class NewsFeedArticle: Statostore, ObservableObject {
    @Superscope var parentList: NewsFeedList
    @Published var article: Article?

    enum When { case favorite }

    func update(_ when: When) throws {
        switch when {
        case .favorite:
            // read shared state from the parent without the parent handing it down explicitly
            let favoritesEnabled = parentList.favoritesEnabled
            // ...
        }
    }
}
```

`@Superscope` walks up the injection tree to find the nearest ancestor of the declared type — the same tree `@Injected`/`Injectable` dependency resolution uses (see Dependency Injection below), just resolving to a live scope instead of a plain value.

Splitting scopes this way keeps each `State`/`When` focused on one concern, makes each scope independently testable via `GIVEN`/`WHEN`/`THEN`, and lets SwiftUI views compose the same way the scopes do — one view per scope, each observing only the state it owns. The tradeoff: state that's genuinely shared across siblings (like `favoritesEnabled` above) has to flow through `@Superscope`/`@Subscope` or dependency injection rather than living in one convenient place — usually a worthwhile trade once a screen has grown past two or three concerns, not something to reach for on day one.

## Reacting to child events: HierarchialScopeMiddleWare

`@Subscope`/`@Superscope` only move data in one direction each: a parent hands a value down when it creates a child, and a child gets a read-only link back up. Neither lets a child's *event* change what a parent owns. `HierarchialScopeMiddleWare` is for that: a parent intercepts an event from a child before deciding whether to let it through.

Say favoriting an article needs to update a single, shared list of favorites — not a copy living separately in both `NewsFeedList` and `NewsFeedArticle`. Move ownership to the parent and let it intercept the child's event:

```swift
final class NewsFeedList: Statostore, ObservableObject, HierarchialScopeMiddleWare {
    @Published var loadedArticles: [Article] = []
    @Published var favorites: Set<String> = []
    @Subscope var readingArticle: NewsFeedArticle?

    // ...

    // Runs for every event `readingArticle` sends, before it reaches the child's own update().
    func updateSubscope<Child: ScopeImplementation>(_ event: SubscopeEvent<Child>) throws {
        guard let articleEvent = event as? SubscopeEvent<NewsFeedArticle>,
              case .favorite = articleEvent.when else {
            try event.forward()
            return
        }
        favorites.formSymmetricDifference([articleEvent.child.id])  // toggle membership
        // The child no longer owns `favorites` at all, so this simply returns — never calling
        // event.forward() — rather than letting an event the child has nothing left to do with
        // reach its update() anyway.
    }
}
```

Unlike the Reducer pattern's `MiddlewareReducer`, where `parentState` is read-only and any reaction has to go through a `When` the parent's own `update()` processes, `updateSubscope` is an ordinary instance method — it can mutate `self` directly, no delegation required. And where `SubstateOutcome` fixes the ordering (`.react` always reacts before forwarding, `.intercept` never forwards), `event.forward()` is a call you make yourself: call it first to react *after* the child processes the event, last to react *before*, or not at all to consume it, as above.

That flexibility doesn't remove the ordering pitfall, though — it just moves the decision point. A real app on the Reducer side of this same library reacted to a child's submit event, and a guard inside the child's own handler for that *same* event read a parent-owned flag the reaction had already flipped moments earlier, rejecting every legitimate submit. The `HierarchialScopeMiddleWare` equivalent is exactly as possible: react-then-forward means the child's own `update()` for that event runs *after* your reaction already changed the state it might be checking.

One more contrast worth calling out: a child can point `@Superscope` past its direct parent, straight at any ancestor by type (`allHierarchialScopeMiddlewareParents()` walks the whole chain the same way, so an ancestor two levels up intercepts a grandchild's event with no relay code in the reducer in between). For the Reducer pattern's `@SuperState`, that skip-level read is only safe when the data lives directly on the target ancestor's own state — a value snapshot mirroring some *other* descendant's data can go stale. `@Superscope` has no such trap: it resolves to a **live reference** to the actual ancestor object, not a value copied at some point in time, so skipping levels is always safe here — there's nothing cached in between to go stale.
