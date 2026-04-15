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

    public init(
        streamID: NSString,
        loopbackURL: NSString,
        contentType: NSString,
        contentLength: Int64
    ) {
        self.schemaVersion = 1
        self.streamID = streamID
        self.loopbackURL = loopbackURL
        self.contentType = contentType
        self.contentLength = contentLength
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(streamID, forKey: "streamID")
        coder.encode(loopbackURL, forKey: "loopbackURL")
        coder.encode(contentType, forKey: "contentType")
        coder.encode(contentLength, forKey: "contentLength")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let streamID = coder.decodeObject(of: NSString.self, forKey: "streamID") else { return nil }
        guard let loopbackURL = coder.decodeObject(of: NSString.self, forKey: "loopbackURL") else { return nil }
        guard let contentType = coder.decodeObject(of: NSString.self, forKey: "contentType") else { return nil }
        contentLength = coder.decodeInt64(forKey: "contentLength")
        self.streamID = streamID
        self.loopbackURL = loopbackURL
        self.contentType = contentType
    }
}
