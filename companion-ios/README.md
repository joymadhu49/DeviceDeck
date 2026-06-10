# DeviceDeck Mobile (iOS companion)

iPhone/iPad companion app for the DeviceDeck macOS app. Uses MultipeerConnectivity
(service type `devicedeck-fs`) to discover the Mac, exchange device info, share the
clipboard, and send/receive files over the local network.

The four Swift files in `DeviceDeckMobile/` are the complete app source. There is no
Xcode project here — you create one on a machine with full Xcode and drop the files in.

## Requirements

- Xcode 15 or later (iOS 17 SDK)
- An iPhone or iPad running iOS 17 or later
- The DeviceDeck Mac app running on a Mac on the **same Wi-Fi network**
- An Apple ID (a free one is enough for on-device development)

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project…**
2. Choose **iOS → App**, click Next.
3. Set:
   - Product Name: `DeviceDeckMobile`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Pick any team/organization identifier for now and create the project.
5. In the Project navigator, **delete the template `ContentView.swift` and
   `DeviceDeckMobileApp.swift`** that Xcode generated (Move to Trash).
6. Drag these four files from `companion-ios/DeviceDeckMobile/` into the project's
   `DeviceDeckMobile` group (check "Copy items if needed" and add them to the
   DeviceDeckMobile target):
   - `Models.swift`
   - `MultipeerService.swift`
   - `ContentView.swift`
   - `DeviceDeckMobileApp.swift`
7. In the target's **General** tab, set **Minimum Deployments** to **iOS 17.0**.

## 2. Add the required Info.plist keys

Select the project → DeviceDeckMobile target → **Info** tab, and add these keys
(right-click → Add Row). MultipeerConnectivity will not work without the first two.

| Key | Type | Value |
|---|---|---|
| `NSLocalNetworkUsageDescription` | String | `DeviceDeck uses the local network to find your other devices and transfer files.` |
| `NSBonjourServices` | Array | Item 0: `_devicedeck-fs._tcp` — Item 1: `_devicedeck-fs._udp` |
| `UIFileSharingEnabled` (Application supports iTunes file sharing) | Boolean | `YES` |
| `LSSupportsOpeningDocumentsInPlace` (Supports opening documents in place) | Boolean | `YES` |

If you prefer editing the raw plist/source, the same keys look like this:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>DeviceDeck uses the local network to find your other devices and transfer files.</string>
<key>NSBonjourServices</key>
<array>
    <string>_devicedeck-fs._tcp</string>
    <string>_devicedeck-fs._udp</string>
</array>
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` make the app's Documents
folder visible in the Files app, so received files show up under
**Files → On My iPhone → DeviceDeckMobile → DeviceDeck**.

## 3. Signing (free Apple ID)

1. Project → DeviceDeckMobile target → **Signing & Capabilities**.
2. Check **Automatically manage signing**.
3. Under Team, click **Add an Account…** and sign in with your Apple ID
   (a free "Personal Team" is created automatically).
4. If the bundle identifier conflicts, change it to something unique, e.g.
   `com.yourname.DeviceDeckMobile`.

Note: with a free Personal Team the app expires after 7 days and must be re-run
from Xcode; apps are limited to your own devices.

## 4. Run on your device

1. Plug in your iPhone (or use Wi-Fi debugging) and select it as the run destination.
2. Press **Run**. On first install, on the phone go to
   **Settings → General → VPN & Device Management** and trust your developer certificate.
3. On first launch the app triggers the **Local Network permission prompt**
   ("DeviceDeckMobile would like to find and connect to devices on your local
   network"). Tap **Allow** — discovery silently fails without it. If you missed it,
   enable it later in **Settings → Privacy & Security → Local Network**.
4. Make sure the DeviceDeck Mac app is running and both devices are on the
   **same Wi-Fi network** (and not on isolated guest networks).

## 5. Using the app

- The main screen lists nearby DeviceDeck peers with a status dot
  (blue = discovered, yellow = connecting, green = connected). Tap a discovered
  peer to connect; either side can initiate (invitations are auto-accepted).
- Tap a connected peer to see its device info (model, OS, disk, battery, IP) and to:
  - **Send Files** — pick one or more files with the system document picker.
  - **Send Clipboard** — sends your current clipboard text to the peer's clipboard.
  - **Ping** — quick connectivity check.
- Incoming files land in `Documents/DeviceDeck` (collision-safe naming: "name 2.ext",
  "name 3.ext", …) and appear in the **Received Files** section, where you can share
  them with the system share sheet or swipe to delete. They are also accessible from
  the Files app as described above.

## Troubleshooting

- **No peers found:** check the Local Network permission on the iPhone, confirm the
  Mac app is running, confirm both devices share a Wi-Fi network, and toggle Wi-Fi
  off/on. MultipeerConnectivity does not route across different networks.
- **`NSNetServices` / `-72008` errors in the console:** the `NSBonjourServices`
  entries are missing or misspelled — they must be exactly `_devicedeck-fs._tcp`
  and `_devicedeck-fs._udp`.
- **Transfers stall when the phone locks:** MultipeerConnectivity is suspended in
  the background; keep the app in the foreground during large transfers.
