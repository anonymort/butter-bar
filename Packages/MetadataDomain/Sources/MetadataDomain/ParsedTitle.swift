import Foundation

/// Output of `TitleNameParser.parse(_:)`. Captures everything we can
/// extract from a release filename without doing I/O.
public struct ParsedTitle: Equatable, Sendable, Hashable, Codable {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let releaseGroup: String?
    public let qualityHints: Set<QualityHint>

    public init(title: String,
                year: Int?,
                season: Int?,
                episode: Int?,
                releaseGroup: String?,
                qualityHints: Set<QualityHint>) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.releaseGroup = releaseGroup
        self.qualityHints = qualityHints
    }

    public enum QualityHint: String, Equatable, Sendable, Hashable, Codable {
        // Resolution
        case p480 = "480p"
        case p576 = "576p"
        case p720 = "720p"
        case p1080 = "1080p"
        case p2160 = "2160p"
        case uhd = "UHD"

        // Source
        case bluRay = "BluRay"
        case webRip = "WEBRip"
        case webDL = "WEB-DL"
        case hdRip = "HDRip"
        case dvdRip = "DVDRip"
        case hdtv = "HDTV"
        case remux = "REMUX"

        // Codec
        case x264
        case x265
        case h264
        case h265
        case hevc
        case xvid
        case av1 = "AV1"

        // Dynamic range
        case hdr = "HDR"
        case hdr10 = "HDR10"
        case dolbyVision = "DV"

        // Audio
        case dts = "DTS"
        case ddp = "DDP"
        case ac3 = "AC3"
        case atmos = "Atmos"
        case truehd = "TrueHD"
    }
}
