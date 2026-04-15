import Foundation

@objc(TorrentFileDTO)
public final class TorrentFileDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let fileIndex: Int32
    /// Relative path within the torrent.
    public let path: NSString
    public let sizeBytes: Int64
    /// Best-effort MIME type hint; may be nil.
    public let mimeTypeHint: NSString?
    /// Engine-side heuristic — true if AVFoundation can play this file.
    public let isPlayableByAVFoundation: Bool

    public init(
        fileIndex: Int32,
        path: NSString,
        sizeBytes: Int64,
        mimeTypeHint: NSString?,
        isPlayableByAVFoundation: Bool
    ) {
        self.schemaVersion = 1
        self.fileIndex = fileIndex
        self.path = path
        self.sizeBytes = sizeBytes
        self.mimeTypeHint = mimeTypeHint
        self.isPlayableByAVFoundation = isPlayableByAVFoundation
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(fileIndex, forKey: "fileIndex")
        coder.encode(path, forKey: "path")
        coder.encode(sizeBytes, forKey: "sizeBytes")
        coder.encode(mimeTypeHint, forKey: "mimeTypeHint")
        coder.encode(isPlayableByAVFoundation, forKey: "isPlayableByAVFoundation")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        fileIndex = coder.decodeInt32(forKey: "fileIndex")
        guard let path = coder.decodeObject(of: NSString.self, forKey: "path") else { return nil }
        sizeBytes = coder.decodeInt64(forKey: "sizeBytes")
        mimeTypeHint = coder.decodeObject(of: NSString.self, forKey: "mimeTypeHint")
        isPlayableByAVFoundation = coder.decodeBool(forKey: "isPlayableByAVFoundation")
        self.path = path
    }
}
