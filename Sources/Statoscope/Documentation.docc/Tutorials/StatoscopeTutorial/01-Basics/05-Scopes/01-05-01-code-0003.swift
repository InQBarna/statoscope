final class NewsFeed: Statostore, ObservableObject {

    @Published var loadingFeatureToggles: Bool = true
    var atList: NewsFeedList?

    enum When {
        case systemLoadedScope
        case networkReturnsFeatureToggle(Result<[String: String], EquatableError>)
    }

    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}
