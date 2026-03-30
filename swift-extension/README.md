# Greywall Transparent Proxy – System Extension (PoC)

Minimal macOS system extension using `NETransparentProxyProvider` to intercept TCP/UDP flows at the socket layer. This is a proof-of-concept for validating transparent traffic capture before full integration with greywall/greyproxy.

**Step 1 (current):** passive logging – intercepts all outbound flows, logs PID + app signing ID + remote hostname, and passes everything through. No traffic is modified.

## Prerequisites

- macOS 12+ (Monterey)
- Xcode 15+
- **Paid Apple Developer Program** ($99/year) – personal/free accounts cannot use the Network Extensions entitlement
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Project Structure

```
swift-extension/
├── project.yml                              # xcodegen spec
├── GreywallProxy.xcodeproj/                 # generated Xcode project
├── GreywallProxy/                           # container app (activates the extension)
│   ├── AppDelegate.swift
│   ├── GreywallProxy.entitlements
│   └── Info.plist
└── GreywallProxyExtension/                  # system extension (NETransparentProxyProvider)
    ├── main.swift
    ├── TransparentProxyProvider.swift
    ├── GreywallProxyExtension.entitlements
    └── Info.plist
```

## Setup

### 1. Set your Team ID

Find your Team ID:

```sh
security find-identity -p codesigning -v
# Look for the OU field in the certificate subject, or check Xcode > Settings > Accounts
```

Edit `project.yml` and replace the `DEVELOPMENT_TEAM` value with your Team ID:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

### 2. Generate the Xcode project

```sh
xcodegen generate
```

**Important:** xcodegen clears the entitlements files on every regeneration. After running xcodegen, either:

- Restore entitlements manually (see [Entitlements](#entitlements) below), or
- Open the project in Xcode and set capabilities via Signing & Capabilities tab (easier):
  - **GreywallProxy** target: enable "System Extension" + "Network Extensions" (App Proxy Provider)
  - **GreywallProxyExtension** target: enable "Network Extensions" (App Proxy Provider)

### 3. Build

From Xcode (Product > Run), or from the command line:

```sh
xcodebuild -project GreywallProxy.xcodeproj -scheme GreywallProxy \
  -configuration Debug -allowProvisioningUpdates build
```

## Testing

### 1. Launch the app to activate the extension

```sh
open ~/Library/Developer/Xcode/DerivedData/GreywallProxy-*/Build/Products/Debug/GreywallProxy.app
```

Two approval dialogs will appear:

1. **System Settings > Privacy & Security**: "GreywallProxy" system extension – click Allow
2. **"Allow GreywallProxy to filter network content?"** – click Allow

### 2. Watch the logs

```sh
log stream --predicate 'subsystem == "io.greywall.proxy"' --level info
```

### 3. Generate traffic

In another terminal:

```sh
curl https://example.com
```

Expected log output:

```
TCP flow: pid=12345 app=com.apple.curl host=example.com dest=93.184.216.34:443
```

This confirms: traffic interception works, PID metadata is available, `remoteHostname` provides domain visibility, and passthrough does not break the connection.

### 4. Uninstall

```sh
systemextensionsctl list
systemextensionsctl uninstall YOUR_TEAM_ID io.greywall.proxy.extension
```

## Entitlements

If xcodegen clears the entitlements, restore them manually:

**GreywallProxy/GreywallProxy.entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.system-extension.install</key>
    <true/>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>app-proxy-provider-systemextension</string>
    </array>
</dict>
</plist>
```

**GreywallProxyExtension/GreywallProxyExtension.entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>app-proxy-provider-systemextension</string>
    </array>
</dict>
</plist>
```

## References

- [mitmproxy/mitmproxy_rs](https://github.com/mitmproxy/mitmproxy_rs/tree/main/mitmproxy-macos/redirector) – reference implementation of the same approach
- [Apple: NETransparentProxyProvider](https://developer.apple.com/documentation/NetworkExtension/NETransparentProxyProvider)
- [Apple: Network Extension entitlement (no special approval needed)](https://developer.apple.com/forums/thread/67613)
- [Research notes](../macos-proxy-notes-simplified.md)
