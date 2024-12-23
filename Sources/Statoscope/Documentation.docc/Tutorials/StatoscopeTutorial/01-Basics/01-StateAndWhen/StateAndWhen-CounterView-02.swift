import Statoscope
import SwiftUI

struct CounterView: View {
    @StateObject var model = Counter()
    var body: some View {
        VStack {
            Text("\(model.viewDisplaysTotalCount)")
            HStack {
                Button("+") {
                    model.send(.userTappedIncrementButton)
                }
                Button("-") {
                    model.send(.userTappedDecrementButton)
                }
            }
        }
    }
}
