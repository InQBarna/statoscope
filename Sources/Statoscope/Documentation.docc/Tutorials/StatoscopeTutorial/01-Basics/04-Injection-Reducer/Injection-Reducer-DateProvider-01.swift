struct DateProvider: Injectable {
    var currentDate: () -> Date
    static var defaultValue = DateProvider(currentDate: Date.init)
}
