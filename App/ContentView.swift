import SwiftUI
import MetadataDomain

struct ContentView: View {
    @StateObject private var libraryViewModel = LibraryViewModel(client: EngineClient())
    @StateObject private var homeViewModel: HomeViewModel
    @State private var selection: DiscoveryDestination = .home
    @State private var selectedItem: MediaItem?

    private let metadataProvider: MetadataProvider

    init(metadataProvider: MetadataProvider? = nil) {
        // Default to a TMDB provider sourcing its token from
        // `TMDBSecrets.tmdbAccessToken`. With no token (CI / fresh checkout)
        // calls fail with `.authentication`, which the UI renders as the
        // calm "We can't reach the catalogue right now" line per
        // `06-brand.md § Voice` — never a crash, never a red banner.
        let provider: MetadataProvider = metadataProvider ?? TMDBProvider(
            config: .init(bearerToken: TMDBSecrets.tmdbAccessToken)
        )
        self.metadataProvider = provider
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(provider: provider))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $selectedItem) { item in
            DetailRouteStub(item: item)
                .frame(minWidth: 480, minHeight: 360)
        }
    }

    private var sidebar: some View {
        List(DiscoveryDestination.allCases, selection: $selection) { destination in
            Label(destination.title, systemImage: destination.systemImage)
                .tag(destination)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            HomeView(viewModel: homeViewModel,
                     provider: metadataProvider,
                     selectedItem: $selectedItem)
        case .library:
            LibraryView(viewModel: libraryViewModel)
        case .movies:
            MoviesGridView(provider: metadataProvider, selectedItem: $selectedItem)
        case .shows:
            ShowsGridView(provider: metadataProvider, selectedItem: $selectedItem)
        }
    }
}
