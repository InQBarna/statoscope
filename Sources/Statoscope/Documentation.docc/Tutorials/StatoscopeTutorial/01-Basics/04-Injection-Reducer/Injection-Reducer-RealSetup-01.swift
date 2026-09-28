// `dependencies.resolve()` never falls back to `Injectable.defaultValue` automatically —
// unlike `@Injected`/`@ReducerInjected`, a miss always throws. So even DateProvider and
// PersistenceProvider, despite being `Injectable`, need to be injected explicitly once —
// typically right here, wherever your app creates this Store for real use (a SwiftUI
// `@StateObject`, your composition root, etc.), not just inside tests.
static func makeNewsFeedStore() -> NewsFeedListReducer.Store {
    NewsFeedListReducer.Store(initialState: NewsFeedListReducer.State())
        .injectObject(DateProvider.defaultValue)
        .injectObject(PersistenceProvider.defaultValue)
        .injectObject(RealNetworkProvider.defaultValue)
}
