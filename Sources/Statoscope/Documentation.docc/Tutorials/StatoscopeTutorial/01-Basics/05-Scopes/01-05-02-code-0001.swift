struct NewsFeedView: View {
    @ObservedObject var model: NewsFeed
    var body: some View {
        if let atList = model.atList {
            ListView(model: atList)
        } else if model.loading {
            Text("Loading...")
        } else {
            AssertNeverDisplayedEmptyView()
        }
    }
}
