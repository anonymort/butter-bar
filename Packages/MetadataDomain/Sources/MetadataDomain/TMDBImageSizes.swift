import Foundation

/// Single source for TMDB image-size suffixes. Each layout slot pins its
/// 1x size and (optionally) a 2x retina size; consumers select via
/// `select(for:retina:)`. See design § D5.
public enum TMDBImageSize: String, Sendable, Equatable, Hashable, Codable {
    case w92, w154, w185, w300, w342, w500, w780, w1280, h632, original
}

public enum TMDBImageSlot: Sendable, Equatable, Hashable {
    /// Browse-row poster card.
    case posterCard
    /// Detail-page poster.
    case posterDetail
    /// Backdrop hero on detail / hub.
    case backdrop
    /// Episode still in season selector.
    case episodeStill
    /// Cast headshot.
    case headshot
}

public enum TMDBImageSizes {

    /// Returns the right image size for a given layout slot.
    /// `retina = true` requests the 2x size where one exists.
    public static func size(for slot: TMDBImageSlot, retina: Bool = false) -> TMDBImageSize {
        switch (slot, retina) {
        case (.posterCard, false):    return .w342
        case (.posterCard, true):     return .w500
        case (.posterDetail, false):  return .w500
        case (.posterDetail, true):   return .w780
        case (.backdrop, _):          return .w1280
        case (.episodeStill, false):  return .w300
        case (.episodeStill, true):   return .w500
        case (.headshot, false):      return .w185
        case (.headshot, true):       return .h632
        }
    }
}

/// Disk-budget configuration for the `URLCache`-backed image cache.
public enum ImageCacheConfig {
    /// 500 MB disk budget per design § D5.
    public static let diskCapacityBytes: Int = 500 * 1024 * 1024
    /// Keep memory cap modest — the OS pages disk efficiently.
    public static let memoryCapacityBytes: Int = 64 * 1024 * 1024
    /// Standard sandbox path: `images/` sibling of `responses/`.
    public static let directoryName: String = "images"
}
