import Statoscope

fileprivate final class Counter: Scope {
    
    var viewDisplaysTotalCount: Int = 0
    
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    func update(_ when: When) throws {
    }
}
