# ``Statoscope``

A lightweight library for managing state in iOS applications, designed with simplicity, testability, and scalability in mind.

## Overview

Statoscope helps developers focus on the overall design of application state, offering helpers for testing, dependency injection, and composing state scopes.

* **State Management**

    State and state mutation using synchronous events are managed by the `Store`, which has a single entry point for handling `When` events.

* **Effects**

    Asynchronous effects are managed through the `EffectsHandler`, which supports checking the status of effects and allows for their cancellation.

* **Scopes**

    A `Scope` is the minimal implementation for managing a piece of state, handling state, mutations, and effects. Scopes can be connected as a dependency tree using the `Superscope` and `Subscope` property wrappers.

* **Testing**

    The `TestPlan` helper object enables flow tests of the entire app using production code, allowing for Acceptance-As-Code if state and `When` events are clearly named.

* **Dependency Injection**

    The `Injectable` protocol and `Injected` property wrappers, in combination with scope linking, provide a multi-level dependency injection pattern similar to the one used in SwiftUI.

## Two ways to build a scope

Statoscope ships two patterns, covered side by side in the tutorials below: **Reducer** (`@Reducer`, a static `update()` over a single state struct) is recommended for new features, and **Statostore** (a class with `@Published` properties) is the easy migration path for bringing an existing ViewModel-shaped screen into Statoscope.

## Topics

### Tutorials

- <doc:Overview-article>
- <doc:Overview-article-Statostore>
- <doc:StatoscopeTutorial>
