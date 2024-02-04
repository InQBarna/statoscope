# ``Statoscope``

A small library to handle iOS application state, focused in simplicity, testability and scalability.

## Overview

Statoscope enables the app developer to focus on the overall design of the app's state, providing helpers for testing, dependency injection and composition of state scopes.

* **State management**

    State and mutation of state using synchronous events is implemented by the Store with a single entry point: When events.

* **Effects**

    All asynchronous effects are handled by the library using the EffectsHandler, enabling effects status check and cancellation.

* **Scopes**

    The Statoscope is the minimum implementation for a piece of state, handling State, mutation and Effects. Scopes can be linked together as a dependency tree using the provided Superscope and Subscope property wrappers

* **Testing**

    The TestPlan helper object allows Flow tests of the whole app's production code setup, enabling Acceptance As Code if when properly naming your states and When events

* **Dependency injection**

    Injectable protocol and Injected property wrappers, in conjunction with the Scopes links allow a multi-level dependency injection such as the one accomplished by SwiftUI.

## Topics

### Tutorials

- <doc:Overview-article>

