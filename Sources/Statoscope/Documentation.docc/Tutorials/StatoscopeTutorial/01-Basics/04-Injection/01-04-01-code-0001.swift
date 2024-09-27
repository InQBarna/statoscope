import Statoscope

// Entities
struct DTO: Codable, Hashable {
    struct ListItem: Codable, Hashable {
        let id: String
        let title: String
        let url: String
    }
    let news: [ListItem]
}
struct Favorite: Hashable {
    let id: String
    let dateAdded: Date
}

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
