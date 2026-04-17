import SwiftUI
import MetadataDomain

// MARK: - Genre chips
//
// A horizontally-flowing row of soft butter chips. Used for the genres
// list at the top of the body. No interaction in v1; chips are display-only
// (filtering by genre is a Discovery surface concern, separate ticket).

struct GenreChipRow: View {
    let genres: [Genre]

    var body: some View {
        // Use a flexible flow via a horizontal ScrollView so very-many-genre
        // titles (rare) don't break layout.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.id) { genre in
                    Text(genre.name)
                        .font(BrandTypography.caption)
                        .foregroundStyle(BrandColors.cocoa)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(BrandColors.butter.opacity(0.18))
                        )
                        .overlay(
                            Capsule().stroke(BrandColors.butterDeep.opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

// MARK: - Cast chip row
//
// Horizontal scroll of cast headshots + name + character. Hidden when the
// cast list is empty — the foundation does not yet expose cast (#11), so
// the v1 detail page renders without the section until that lands. Tests
// exercise the populated path via injected `CastMember` fixtures.

struct CastChipRow: View {
    let cast: [CastMember]
    let imageURL: (String) -> URL

    private let cardWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(BrandTypography.bodyEmphasis)
                .foregroundStyle(BrandColors.cocoa)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cast) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            CastHeadshot(member: member, imageURL: imageURL)
                            Text(member.name)
                                .font(BrandTypography.caption)
                                .foregroundStyle(BrandColors.cocoa)
                                .lineLimit(2)
                            Text(member.character)
                                .font(BrandTypography.caption)
                                .foregroundStyle(BrandColors.cocoaSoft)
                                .lineLimit(2)
                        }
                        .frame(width: cardWidth, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct CastHeadshot: View {
    let member: CastMember
    let imageURL: (String) -> URL

    var body: some View {
        ZStack {
            // Brand-tokenised soft butter rounded rect placeholder (per AC).
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrandColors.butter.opacity(0.18))
                .frame(width: 96, height: 128)

            if let path = member.profilePath {
                AsyncImage(url: imageURL(path)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }
}
