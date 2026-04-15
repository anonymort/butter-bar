#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Minimal smoke test to verify libtorrent links and runs.
@interface TorrentBridgeSmokeTest : NSObject
/// Creates an lt::session, checks it's valid, tears it down. Returns YES on success.
+ (BOOL)runSmokeTest;
@end

NS_ASSUME_NONNULL_END
