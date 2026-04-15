#import "TorrentBridgeSmokeTest.h"
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>

@implementation TorrentBridgeSmokeTest

+ (BOOL)runSmokeTest {
    lt::session_params params;
    lt::session ses(std::move(params));
    // If we got here, libtorrent linked and initialised.
    return YES;
}

@end
