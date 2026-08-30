func testBasicGivenWhenThenPattern() throws {
    let fixedDate = Date(timeIntervalSince1970: 1000)

    try NewsFeedReducer.Store.GIVEN(
        state: NewsFeedReducer.State()
    ) { $0
        .injectObject(DateProvider { fixedDate })
        .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
    }
    .THEN(\.state.loading, equals: false)
    .THEN(\.state.favorites, equals: [])
    .WHEN(.systemLoadedScope)
    .THEN(\.state.loading, equals: true)
    .runTest(assertNoPendingEffects: false)  // Effect enqueued but not completed
}
