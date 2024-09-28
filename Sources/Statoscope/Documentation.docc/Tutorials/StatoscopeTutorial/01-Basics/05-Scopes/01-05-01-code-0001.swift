final class NewsFeed: Statostore, ObservableObject {
    
    @Published var loadingList: Bool = false
    @Published var loadedListDTOs: DTO?
    @Published var readingArticle: URL?
    @Published var favorites: [Favorite] = []
    
    enum When {
        case systemLoadedScope
        case networkDidFinish(DTO)
        case navigateToChild(id: String)
        case favorite(id: String)
    }
    
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}
