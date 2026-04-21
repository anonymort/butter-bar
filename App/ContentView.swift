import SwiftUI
import MetadataDomain

struct ContentView: View {
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var searchViewModel: SearchViewModel
    @StateObject private var providerPipeline = ProviderSearchPipeline(
        providers: DefaultProviderRegistry.makeProviders()
    )
    @State private var selection: DiscoveryDestination = .home
    @State private var selectedItem: MediaItem?

    private let metadataProvider: MetadataProvider
    private let engineClient: EngineClient

    init(metadataProvider: MetadataProvider? = nil,
         engineClient: EngineClient = EngineClient()) {
        // Default to a TMDB provider sourcing its token from
        // `TMDBSecrets.tmdbAccessToken`. With no token (CI / fresh checkout)
        // calls fail with `.authentication`, which the UI renders as the
        // calm "We can't reach the catalogue right now" line per
        // `06-brand.md § Voice` — never a crash, never a red banner.
        let provider: MetadataProvider = metadataProvider ?? TMDBProvider(
            config: .init(bearerToken: TMDBSecrets.tmdbAccessToken)
        )
        self.metadataProvider = provider
        self.engineClient = engineClient
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(client: engineClient))
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(provider: provider))
        _searchViewModel = StateObject(wrappedValue: SearchViewModel(provider: provider))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .searchable(
            text: Binding(
                get: { searchViewModel.query },
                set: { searchViewModel.updateQuery($0) }
            ),
            placement: .toolbar,
            prompt: "Search"
        )
        .sheet(item: $selectedItem) { item in
            DetailRouteStub(
                item: item,
                provider: metadataProvider,
                engineClient: engineClient
            )
            .frame(minWidth: 720, minHeight: 560)
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
        if searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            SearchView(
                viewModel: searchViewModel,
                provider: metadataProvider,
                onSelect: { selectedItem = $0 }
            )
        } else {
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
}
