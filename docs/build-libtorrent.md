# Building with libtorrent-rasterbar

## Prerequisites

- macOS Tahoe (26.0) or later
- Xcode 26 with SDK 26
- Homebrew

## Install

```bash
brew install libtorrent-rasterbar
```

This installs libtorrent-rasterbar 2.0.x as a shared library. The formula also pulls in Boost and OpenSSL as dependencies.

Default install paths:

| Artifact | Path |
|---|---|
| Headers | `/opt/homebrew/Cellar/libtorrent-rasterbar/<version>/include/libtorrent/` |
| Dylib | `/opt/homebrew/Cellar/libtorrent-rasterbar/<version>/lib/libtorrent-rasterbar.dylib` |
| OpenSSL headers | `/opt/homebrew/opt/openssl@3/include` |
| OpenSSL libs | `/opt/homebrew/opt/openssl@3/lib` |

Verify the install:

```bash
pkg-config --modversion libtorrent-rasterbar
pkg-config --cflags --libs libtorrent-rasterbar
```

## How the Xcode project links against it

The `EngineService` target (both Debug and Release configurations) has these build settings:

**`HEADER_SEARCH_PATHS`**
```
/opt/homebrew/include
/opt/homebrew/Cellar/libtorrent-rasterbar/2.0.12/include
/opt/homebrew/opt/openssl@3/include
```

**`LIBRARY_SEARCH_PATHS`**
```
/opt/homebrew/lib
/opt/homebrew/Cellar/libtorrent-rasterbar/2.0.12/lib
/opt/homebrew/opt/openssl@3/lib
```

**`OTHER_LDFLAGS`**
```
-ltorrent-rasterbar -lssl -lcrypto
```

**`GCC_PREPROCESSOR_DEFINITIONS`** (merged with existing defines)
```
TORRENT_LINKING_SHARED=1
BOOST_ASIO_ENABLE_CANCELIO=1
BOOST_ASIO_NO_DEPRECATED=1
TORRENT_USE_OPENSSL=1
TORRENT_USE_LIBCRYPTO=1
TORRENT_SSL_PEERS=1
```

The ObjC++ bridge files live in `EngineService/Bridge/`. The Swift-ObjC bridging header at `EngineService/Bridge/EngineService-Bridging-Header.h` exposes the bridge to Swift code in the same target.

## Upgrading libtorrent

When upgrading the Homebrew formula, update the version-pinned paths in the `HEADER_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` build settings for both Debug and Release configs in `ButterBar.xcodeproj/project.pbxproj`.

## Verifying the setup

Build the EngineService target without code signing:

```bash
xcodebuild -scheme EngineService build CODE_SIGN_IDENTITY=- 2>&1 | tail -30
```

A successful build ends with `** BUILD SUCCEEDED **`. The `TorrentBridgeSmokeTest.mm` file is compiled as part of this target, confirming that libtorrent headers resolve and the dylib links correctly.

If you see linker errors about missing `-ltorrent-rasterbar`, confirm:

1. `brew list libtorrent-rasterbar` shows the expected version.
2. The version in `LIBRARY_SEARCH_PATHS` matches the Homebrew Cellar path.
3. `ls /opt/homebrew/Cellar/libtorrent-rasterbar/2.0.12/lib/` lists the dylib.
