import XCTest
import StatoscopeTesting
@testable import NewsFeed

class NewsFeedTests: XCTestCase {
    func testFeatureUserCanSaveArticleAsFavorite() throws {
        let networkResponse = DTO(
            news: [
                DTO.ListItem(
                    id: "1",
                    title: "Title 1",
                    url: "http://newsfeed.com/article/1"
                )
            ]
        )
        
        try NewsFeedList.GIVEN {
            NewsFeedList()
        }
        .WHEN(.systemLoadedScope)
        .THEN(\.loading, equals: true)
        .WHEN(.networkDidFinish(networkResponse))
        .THEN(\.loading, equals: false)
        .THEN(\.loadedDTOs, equals: networkResponse)
        .WHEN(.navigateToChild(id: "1"))
        .THEN(\.readingArticle?.lastPathComponent, equals: "1")
        .WHEN(.favorite(id: "1"))
        .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: Date())])
        .runTest()
    }
    
    func testFeatureSavedFavoriteIsPersistedForSubsequentExecution() throws {
        try NewsFeedList.GIVEN {
            NewsFeedList()
        }
        .WHEN(.systemLoadedScope)
        // We can't simulate a previous execution of the app with some persistence
        .THEN(\.favorites, equals: [Favorite(id: "1", dateAdded: Date())])
        .runTest()
    }
}
