# Overview

Learn the main concepts in the Statoscope architecture, by examples

## Statoscope basics

### The Statoscope Object

It holds your application state, or a piece (a scope) of your application state.

It is a class object with

* A When type (usually enum cases), which defines the events happening within your application scope.
* Member variables which define the application/scope State. You should never modify these variables directly, instead the view (for example) should send a When instance to the scope object, and the scope object will implement the update method.
* A send method publicly available to forward events for scope processing
* An internal update method that given the current state and the incoming When event updates the scope with a new state. It holds your scope’s business logic.

The mentioned When events are resolved synchronously, so right after sending a When event, the state is correctly updated. If any other asynchronous action may take place, this will be triggered as a side effect: Effects from now on. Every triggered effect has an associated effect completion When definition, so a common asynchronous task adds a pair of When definitions to a scope: there’ll be one ‘When’ to start the effect and another ‘When’ to handle the completion.

#### Asynchronous tasks

The Statoscope is a class object (designed intentionally), so the lifespan of the object is used to define the lifespan of the ongoing effects. When the statoscope object is released, all these Effects are also canceled and released. So the statoscope object also defines the transient states that occur when launching asynchronous tasks. This implicit transient state can be accessed privately by:
* An enqueue method to trigger an asynchronous task during the update process.
* A list of Ongoing Effects. 
* The ability to cancel all effects by simply releasing the scope. 
* A method to cancel specific ongoing effects

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
            enqueue(
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

In the example above we trigger an anonymous effect using the enqueue method. The Statoscope library heavily relies on Apple's concurrency library, it MUST be used to implement your own Effects.
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
        enqueue(
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
                if nil != erasedEffects.first(where: { $0 is NetworkEffect<DTO> }) {
                    cancelEffect { $0 is NetworkEffect<DTO> }
                }
                enqueue(
                    NetworkEffect<DTO>(request: request)
                        .map(When.networkPostCompleted)
                )
                /** … */
            }
        }
```

We’ve covered the basic of triggering, reading, canceling and testing Effects on Statoscope. In the following topics we’ll discuss some advanced usages and tricks for great Effects programming

## App state as Statoscope composition: Superscope + Subscope

TODO: ...
