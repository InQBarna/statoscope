import Statoscope

struct DateProvider: Injectable {
    var currentDate: () -> Date
    // Default value in case injection setup is invalid
    static var defaultValue = DateProvider(
        currentDate: Date.init
    )
}

struct PersistenceProvider: Injectable {
    let get: () throws -> [Favorite]
    let set: ([Favorite]) throws -> Void
    // Default value in case injection setup is invalid
    static var defaultValue = PersistenceProvider(
        get: { try JSONDecoder().decode([Favorite].self, from: UserDefaults.value(forKey: "newsfeed") as? Data ?? Data()) },
        set: { try UserDefaults.setValue(JSONEncoder().encode($0), forKey: "newsfeed") }
    )
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
