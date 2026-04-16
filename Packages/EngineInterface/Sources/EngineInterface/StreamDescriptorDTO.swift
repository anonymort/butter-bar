import Foundation

@objc(StreamDescriptorDTO)
public final class StreamDescriptorDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let streamID: NSString
    /// Loopback URL, e.g. "http://127.0.0.1:PORT/stream/{streamID}".
    public let loopbackURL: NSString
    /// e.g. "video/mp4"
    public let contentType: NSString
    public let contentLength: Int64
    /// Last byte offset successfully served to the player during a prior session, or 0 if no
    /// prior play history. The app may use this to seek AVPlayer to a reasonable keyframe near
    /// this offset. See spec 05 § Resume offset persistence.
    ///
    /// Schema v2 addition. Decoders reading a v1 archive will receive 0 via NSCoder's
    /// default-zero behaviour for missing Int64 keys — backward compatible.
    public let resumeByteOffset: Int64

    public init(
        streamID: NSString,
        loopbackURL: NSString,
        contentType: NSString,
        contentLength: Int64,
        resumeByteOffset: Int64 = 0
    ) {
        self.schemaVersion = 2
        self.streamID = streamID
        self.loopbackURL = loopbackURL
        self.contentType = contentType
        self.contentLength = contentLength
        self.resumeByteOffset = resumeByteOffset
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(streamID, forKey: "streamID")
        coder.encode(loopbackURL, forKey: "loopbackURL")
        coder.encode(contentType, forKey: "contentType")
        coder.encode(contentLength, forKey: "contentLength")
        coder.encode(resumeByteOffset, forKey: "resumeByteOffset")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let streamID = coder.decodeObject(of: NSString.self, forKey: "streamID") else { return nil }
        guard let loopbackURL = coder.decodeObject(of: NSString.self, forKey: "loopbackURL") else { return nil }
        guard let contentType = coder.decodeObject(of: NSString.self, forKey: "contentType") else { return nil }
        contentLength = coder.decodeInt64(forKey: "contentLength")
        resumeByteOffset = coder.decodeInt64(forKey: "resumeByteOffset")
        self.streamID = streamID
        self.loopbackURL = loopbackURL
        self.contentType = contentType
    }
}
