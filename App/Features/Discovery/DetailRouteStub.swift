import SwiftUI
import MetadataDomain

/// Placeholder destination for tapping a poster card. Issue #15 will replace
/// this with the real title detail page; per the AC for #13 we route to a
/// stub rather than block on #15.
struct DetailRouteStub: View {

    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayTitle)
                .brandDisplay()
                .foregroundStyle(BrandColors.cocoa)
            Text(idLabel)
                .brandCaptionMonospacedNumeric()
                .foregroundStyle(BrandColors.cocoaSoft)
            Text("Detail page lands with #15.")
                .brandCaption()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandColors.surfaceBase)
    }

    private var displayTitle: String {
        switch item {
        case .movie(let m): return m.title
        case .show(let s):  return s.name
        }
    }

    private var idLabel: String {
        let id = item.id
        return "\(id.provider.rawValue):\(id.id)"
    }
}
