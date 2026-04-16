import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LibraryViewModel(client: EngineClient())

    var body: some View {
        LibraryView(viewModel: viewModel)
            .onAppear {
                // Connect the engine client once the view hierarchy is live.
                // EngineClient.connect() is actor-isolated — Task hops to actor executor.
                Task { await viewModel.connectEngine() }
            }
    }
}
