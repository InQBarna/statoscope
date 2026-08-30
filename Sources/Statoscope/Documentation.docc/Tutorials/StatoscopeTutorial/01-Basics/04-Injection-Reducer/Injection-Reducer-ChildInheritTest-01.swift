func testChildInheritsInjectedLoggerFromParent() throws {
    var capturedMessages: [String] = []

    let parentStore = ParentWithChild.Store(initialState: .init())
        .injectObject(AuditLogger { capturedMessages.append($0) })

    parentStore.send(.labelChanged("hello"))
    parentStore.send(.openChild)

    // Retrieve child store through the injection tree
    guard let childStore = parentStore.children.child else {
        XCTFail("Child store was not created")
        return
    }

    childStore.send(.add(5))
    childStore.send(.add(3))

    XCTAssertEqual(parentStore.state.label, "hello")
    XCTAssertEqual(childStore.state.value, 8)

    // Both parent and child log through the same injected logger
    XCTAssertEqual(capturedMessages, [
        "label: hello",
        "opening child",
        "child add 5",
        "child add 3"
    ])
}
