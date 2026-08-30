struct Favorite: Codable, Equatable {
    let id: String
    let dateAdded: Date
}

struct PersistenceProvider: Injectable {
    let get: () throws -> [Favorite]
    let set: ([Favorite]) throws -> Void

    static var defaultValue = PersistenceProvider(
        get: {
            guard let data = UserDefaults.standard.data(forKey: "favorites") else {
                return []
            }
            return try JSONDecoder().decode([Favorite].self, from: data)
        },
        set: { favorites in
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: "favorites")
        }
    )
}
