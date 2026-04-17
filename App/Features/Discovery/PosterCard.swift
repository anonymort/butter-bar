import SwiftUI
import MetadataDomain

/// Single poster card used in carousels and grids. Loads the poster image
/// asynchronously through the injected `MetadataProvider`'s `imageURL`;
/// while loading or on failure it shows the brand-tokenised soft butter
/// rounded rect placeholder per `06-brand.md § Voice` and design § D5.
struct PosterCard: View {

    let item: MediaItem
    let provider: MetadataProvider

    /// Logical poster width; w342 source on standard, w500 on retina-ish.
    /// Matches `TMDBImageSizes.size(for: .posterCard, ...)`.
    var width: CGFloat = 132
    var height: CGFloat { width * 1.5 }   // TMDB posters are 2:3.

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            posterImage
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(displayTitle)
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let year = displayYear {
                Text(String(year))
                    .brandCaptionMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let path = posterPath {
            AsyncImage(url: provider.imageURL(path: path, size: .w342)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    /// Brand-tokenised soft butter rounded rect — never a broken-image icon
    /// per design § D5 and brand § Voice.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandColors.creamRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BrandColors.cocoaFaint.opacity(0.4), lineWidth: 0.5)
            )
    }

    private var posterPath: String? {
        switch item {
        case .movie(let m): return m.posterPath
        case .show(let s):  return s.posterPath
        }
    }

    private var displayTitle: String {
        switch item {
        case .movie(let m): return m.title
        case .show(let s):  return s.name
        }
    }

    private var displayYear: Int? {
        switch item {
        case .movie(let m): return m.releaseYear
        case .show(let s):  return s.firstAirYear
        }
    }
}
