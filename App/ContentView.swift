import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LibraryViewModel(client: EngineClient())

    var body: some View {
        LibraryView(viewModel: viewModel)
    }
}
