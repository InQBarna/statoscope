struct DateProvider: Injectable {
    var currentDate: () -> Date
    static var defaultValue = DateProvider(currentDate: Date.init)
}

struct Favorite: Codable, Equatable {
    let id: String
    let dateAdded: Date
}

struct PersistenceProvider: Injectable {
    let get: () throws -> [Favorite]
    let set: ([Favorite]) throws -> Void
    static var defaultValue = PersistenceProvider(get: { [] }, set: { _ in })
}

struct ArticleDTO: Codable, Equatable {
    let id: String
    let title: String
}
