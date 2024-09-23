# ``Statoscope``

A small library to handle iOS application state, focused in simplicity, testability and scalability.

## Overview

Statoscope enables the app developer to focus on the overall design of the app's state, providing helpers for testing, dependency injection and composition of state scopes.

* **State management**

    State and mutation of state using synchronous events is implemented by the Store with a single entry point using `When` events.

* **Effects**

    All asynchronous effects are handled by the library using the EffectsHandler, enabling effects status check and cancellation.

* **Scopes**

    The Statoscope is the minimum implementation for a piece of state, handles State, mutation and Effects. Scopes can be linked together as a dependency tree using the provided Superscope and Subscope property wrappers

* **Testing**

    The TestPlan helper object allows Flow tests of the whole app's production code setup, enabling Acceptance As Code, specially if state properties and When events are properly named

* **Dependency injection**

    Injectable protocol and Injected property wrappers, in conjunction with the Scope linkages allow a multi-level dependency injection such as the one accomplished by SwiftUI.

## Installation

The library is bundled as a Swift Package manager

  1. Add the SPM package with url "https://github.com/InQBarna/statoscope.git"
  2. Add the **Statoscope** library to your *app* target
  3. Add **StatoscopeTesting** library to your *test* target

## Usage

### Basic (State + When + Test)

Design a feature by declaring the State and When. Then Declare the acceptance criteria in your tests, see the example below:

```swift
final class Counter: Scope, ObservableObject {

    @Published var viewDisplaysTotalCount: Int = 0

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }

    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount += 1
        case .userTappedDecrementButton:
            viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
        }
    }
}
```

```swift
final class CounterTest: XCTestCase {
    func testUserFlow() throws {
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

Let's go through the pieces of the feature source code:

* **Scope**: A class object that stores and manages a part of the application state. 
* **State**: Public ember vars in the scope object define a part of the state of the app
* **When**: The list of all possible events that may occur during the app/scope lifetime.
* **update**: The implementation of the feature, should modify the state based on the received event and the current state.

However... we want the update method to be the last piece of the software to be build. In order to focus on the ACCEPTANCE CRITERIA first. Let's go through the pieces of the feature test:

* **FLOW TESTING**: testUserFlow is an integration test that defines and declares the feature accomplished by this scope. It will run the received When events on the scope and assert the declared conditions.
* **ACCEPTANCE AS CODE**: When *State* and *When* types are named as sentences, the test declaration become and acceptance criteria declaration. Defining cleanly how the app/scope behaves.
  * **GIVEN**, **WHEN**, **THEN**: Used to create the scope, send events and check the state after the event
  * **runTest()**: executes the test steps of the ACCEPTANCE AS CODE declaration

### Basic with effects

(Side) **Effect**s are triggered tasks that may finish affecting your app state. That's why effects are expressed in the Statoscope library with 2 an ending *When* case. In the following example the Counter feature is synchronized with a service by using a network api call: an *Effect*. There are many user experiences to achieve this feature, hopefully the Test (Acceptance as code) in the following snippets cleanly state

```swift
final class Counter: Scope, ObservableObject {
        
        @Published var viewDisplaysTotalCount: Int = 0
        @Published var viewDisplaysError: String?
        @Published var viewShowsLoadingAndDisablesButtons: Bool = false
        
        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(Result<DTO, Error>)
        }
        
        func update(_ when: When) throws { /* ... */ }
    }
```

```swift
final class StatoscopeExample2: XCTestCase {
    func testCounterExample3UserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .FORK(.networkPostCompleted(.failure(CancellationError()))) { sut in
            try sut
                .THEN(\.viewDisplaysTotalCount, equals: 1)
                .THEN(\.viewDisplaysError, equals: "The operation couldn’t be completed. (Swift.CancellationError error 1.)")
                .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        }
        .WHEN(.networkPostCompleted(.success(DTO(count: 1))))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .runTest()
    }
}
```

The code above can be interpreted as the "design" of the feature. Stating the different *State*s, *When*s and the user experience of the app. See below the implementation details

```swift

struct DTO: Codable {
    let count: Int
}

struct NetworkEffect<Response: Decodable>: Effect {
    let request: URLRequest
    func runEffect() async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    }
}

final class Counter: Scope, ObservableObject {
        
    /* ... */
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
            try triggerNetworkUpdate()
        case .userTappedDecrementButton:
            guard viewDisplaysTotalCount > 0 else {
                return
            }
            viewDisplaysTotalCount = viewDisplaysTotalCount - 1
            try triggerNetworkUpdate()
        case .networkPostCompleted(let remoteCounter):
            viewShowsLoadingAndDisablesButtons = false
            switch remoteCounter {
            case .success(let remoteCounterSuccess):
                viewDisplaysTotalCount = remoteCounterSuccess.count
            case .failure(let error):
                viewDisplaysError = error.localizedDescription
            }
        }
    }

    private func triggerNetworkUpdate() throws {
        viewShowsLoadingAndDisablesButtons = true
        guard let url = URL(string: "http://statoscope.com") else {
            fatalError()
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(DTO(count: viewDisplaysTotalCount))
        effectsState.enqueue(
            NetworkEffect<DTO>(request: request)
                .mapToResult()
                .map(When.networkPostCompleted)
        )
    }
}
```

### Beyond basics

There are much more interesting topics covered by the Statoscope library.
* Dependecy injection
* Scope composition
* Effects testing
* SwifUI views coupling to stores
Follow the links to the tutorials below for more info.

### Tutorials

TODO
