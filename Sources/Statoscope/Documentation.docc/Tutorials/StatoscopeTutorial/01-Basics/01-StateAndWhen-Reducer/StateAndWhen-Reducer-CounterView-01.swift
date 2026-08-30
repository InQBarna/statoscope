import SwiftUI

extension Tutorial01Reducer {

    struct CounterView: View {

        @StateObject var store = CounterReducer.Store(initialState: CounterReducer.State())

        var body: some View {
            VStack {
                Text("\(store.state.viewDisplaysTotalCount)")
                HStack {
                    Button("+") {
                        store.send(.userTappedIncrementButton)
                    }
                    Button("-") {
                        store.send(.userTappedDecrementButton)
                    }
                }
            }
        }
    }
}
