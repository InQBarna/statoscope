import Statoscope

final class NewsFeedList: Statostore {

    // Scope state
    var loading: Bool = false
    var loadedDTOs: DTO?
    var readingArticle: URL?
    var favorites: [Favorite] = []

    // Scope When events
    enum When {
        case systemLoadedScope
        case networkDidFinish(DTO)
        case navigateToChild(id: String)
        case favorite(id: String)
    }

    // Implementation
    func update(_ when: When) throws {
        // TODO
    }
}
