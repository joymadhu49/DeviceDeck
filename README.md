# DeviceDeck

DeviceDeck is a macOS app for managing your Apple devices from one place. It discovers your other Macs (and the iPhone companion app) on the local network using MultipeerConnectivity, shows a live dashboard of each device, and makes it effortless to move files between them.

## Features

- **Device discovery** — automatically finds other DeviceDeck instances on your local network, no setup required.
- **Live device dashboard** — see each device's model, OS version, CPU, memory, free disk space, battery level, IP address, and uptime at a glance.
- **Drag-and-drop file sharing** — drop files onto a connected Mac to send them directly over the local network.
- **Clipboard sharing** — push your clipboard text to another device with one click.
- **AirDrop hand-off** — share files via the system AirDrop sheet for devices that aren't running DeviceDeck.
- **iPhone companion** — a companion iOS app lives in `companion-ios/` so your iPhone can join the deck too.

## Building

From the project root:

```sh
./scripts/build-app.sh
```

This builds the release binary with Swift Package Manager, bundles it into a proper `.app` with an icon and `Info.plist`, ad-hoc code-signs it, and prints the final path:

```
build/DeviceDeck.app
```

Open it with `open build/DeviceDeck.app` or double-click it in Finder.

## First launch: Local Network permission

The first time you launch DeviceDeck, macOS will ask:

> "DeviceDeck" would like to find and connect to devices on your local network.

This is expected — DeviceDeck uses Bonjour/MultipeerConnectivity to discover your other devices. Click **Allow**. If you accidentally deny it, you can re-enable it later in **System Settings > Privacy & Security > Local Network**.

## Received files

Files sent to you by other devices are saved to:

```
~/Downloads/DeviceDeck
```

The folder is created automatically on the first incoming transfer.

## Troubleshooting

**No devices show up?**

- Make sure both devices are on the **same Wi-Fi network** (or connected via Ethernet to the same router). Guest networks and some corporate networks block peer-to-peer traffic.
- Check the **macOS firewall** (System Settings > Network > Firewall). If it's on, allow incoming connections for DeviceDeck, or temporarily disable the firewall to test.
- Verify Local Network permission is granted on **both** devices: **System Settings > Privacy & Security > Local Network** — DeviceDeck must be toggled on.
- Make sure DeviceDeck is actually running on the other device.
- Toggling Wi-Fi off and on, or relaunching the app, often kicks discovery back into gear.

**Transfers fail or stall?**

- Weak Wi-Fi signal between the devices is the most common cause; move them closer to the router.
- Make sure neither Mac goes to sleep mid-transfer.
