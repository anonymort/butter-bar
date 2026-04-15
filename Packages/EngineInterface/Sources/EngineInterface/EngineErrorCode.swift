import Foundation

/// Error domain for all engine-originated NSErrors.
public let EngineErrorDomain = "com.butterbar.engine"

/// Stable error codes for the `com.butterbar.engine` domain.
@objc public enum EngineErrorCode: Int {
    /// The requested method is not yet implemented.
    case notImplemented = 1
    /// The supplied magnet link or torrent data is malformed.
    case invalidInput = 2
    /// The requested torrent ID does not exist.
    case torrentNotFound = 3
    /// The requested file index is out of range for this torrent.
    case fileIndexOutOfRange = 4
    /// The requested stream ID does not exist or has already been closed.
    case streamNotFound = 5
    /// The engine could not open a stream for the requested file.
    case streamOpenFailed = 6
    /// A file bookmark could not be resolved or has gone stale.
    case bookmarkInvalid = 7
    /// The engine's internal store encountered an error.
    case storageError = 8
    /// An operation was attempted while the engine is shutting down.
    case engineShuttingDown = 9
}
