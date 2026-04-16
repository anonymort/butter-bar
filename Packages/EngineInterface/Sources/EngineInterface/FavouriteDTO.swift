import Foundation

/// Versioned XPC projection of a `favourites` row (T-STORE-FAVOURITES /
/// spec 07 § 4 — favourites required feature). One row per favourited file.
@objc(FavouriteDTO)
public final class FavouriteDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let torrentID: NSString
    public let fileIndex: Int32
    /// Unix milliseconds when the file was favourited.
    public let favouritedAt: Int64

    public init(
        torrentID: NSString,
        fileIndex: Int32,
        favouritedAt: Int64
    ) {
        self.schemaVersion = 1
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.favouritedAt = favouritedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(torrentID, forKey: "torrentID")
        coder.encode(fileIndex, forKey: "fileIndex")
        coder.encode(favouritedAt, forKey: "favouritedAt")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let torrentID = coder.decodeObject(of: NSString.self, forKey: "torrentID") else { return nil }
        fileIndex = coder.decodeInt32(forKey: "fileIndex")
        favouritedAt = coder.decodeInt64(forKey: "favouritedAt")
        self.torrentID = torrentID
    }
}

/// Side-channel event payload for `favouritesChanged`. Distinguishes the
/// add/remove case so the app can update its in-memory map without
/// re-fetching the full list.
@objc(FavouriteChangeDTO)
public final class FavouriteChangeDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let favourite: FavouriteDTO
    public let isRemoved: Bool

    public init(favourite: FavouriteDTO, isRemoved: Bool) {
        self.schemaVersion = 1
        self.favourite = favourite
        self.isRemoved = isRemoved
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(favourite, forKey: "favourite")
        coder.encode(isRemoved, forKey: "isRemoved")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let favourite = coder.decodeObject(of: FavouriteDTO.self, forKey: "favourite") else { return nil }
        isRemoved = coder.decodeBool(forKey: "isRemoved")
        self.favourite = favourite
    }
}
