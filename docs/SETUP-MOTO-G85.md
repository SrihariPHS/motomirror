# Set up a Moto G85 for MotoMirror

This guide takes a new Moto G85 from "just unboxed" to "mirroring on the Mac".
It also applies to most Android 11+ phones.

## What you need

- A Mac on macOS 13 Ventura or newer.
- A Moto G85 with Android 11 or newer.
- A USB-C cable that carries **data**. Many cables in accessory boxes are
  charge-only. A charge-only cable powers the phone but never appears in
  `adb devices`.
- MotoMirror dependencies: run `make setup` in the repository. It installs
  `adb` and `scrcpy` with Homebrew.

You do not need root, sudo, a Motorola driver, or an Android Studio install on
macOS.

## 1. Unlock Developer options

1. Open **Settings**.
2. Tap **About phone**.
3. Find **Build number**. On some Moto builds it is under **About phone >
   Software information > Build number**.
4. Tap **Build number** seven times.
5. Enter the phone PIN, pattern, or password when asked.
6. A toast says **You are now a developer!**.

## 2. Turn on USB debugging

1. Open **Settings > System > Developer options**. On builds with an Advanced
   section, the path is **Settings > System > Advanced > Developer options**.
2. Find the **Debugging** section.
3. Turn on **USB debugging**.
4. Optional: turn on **Stay awake** while charging. It helps during long
   mirror sessions.

Leave **Revoke USB debugging authorizations** alone for now.

## 3. Connect the cable and authorize the Mac

1. Unlock the phone.
2. Connect the Mac and the phone with the USB-C data cable.
3. If the phone asks **Use USB for**, choose **File transfer**. This step is
   not required for ADB, but it confirms that the cable carries data.
4. Pull down the notification shade. A notification says **USB debugging
   connected** when ADB is working.
5. A dialog appears on the phone:

```text
Allow USB debugging?
The computer's RSA key fingerprint is:
AB:CD:EF:01:23:45:67:89:...

[ ] Always allow from this computer

            Cancel    Allow
```

The fingerprint is unique to this Mac. Check **Always allow from this
computer**, then tap **Allow**. If you tap **Cancel**, the device stays in the
`unauthorized` state.

If the dialog does not appear:

- Unlock the phone and plug the cable in again.
- Open **Developer options** and tap **Revoke USB debugging authorizations**.
  Reconnect the cable. The RSA dialog appears again.
- Confirm that the phone is not connected only to a charger.

## 4. Verify the connection on the Mac

Run:

```bash
adb devices -l
```

A working USB connection looks like this:

```text
List of devices attached
ZY22ABCDEF    device usb:1-2 product:... model:Moto_G_85 device:... transport_id:1
```

The serial number and `transport_id` differ on every machine. The important
field is the state, directly after the serial number:

| State | Meaning | Action |
| --- | --- | --- |
| `device` | Ready. | Continue. |
| `unauthorized` | The RSA dialog was not accepted. | Unlock the phone and tap **Allow**. |
| `offline` | The ADB daemon lost the device. | Replug the cable. Run `adb reconnect offline`. |
| `no permissions` | USB access problem, rare on macOS. | Use another cable or port. Reconnect. |
| No line at all | The Mac does not see the phone. | See [When the Mac cannot see the phone](#when-the-mac-cannot-see-the-phone). |

Start the app:

```bash
make app
open dist/MotoMirror.app
```

## 5. Wireless debugging with a pairing code

Use this on Android 11 and newer, including the Moto G85. The phone and the Mac
must be on the same local network. Guest Wi-Fi and client isolation block this
flow.

1. Keep the phone unlocked.
2. Open **Settings > System > Developer options > Wireless debugging**.
3. Turn on **Wireless debugging**.
4. Tap **Pair device with pairing code**.
5. The phone shows **Wi-Fi pairing code**, an address like
   `192.168.1.42:37123`, and a six-digit code. Keep this dialog open.
6. On the Mac, run:

```bash
adb pair 192.168.1.42:37123
```

Use the address from the pairing dialog, not the address on the main Wireless
debugging screen. Enter the six-digit code when `adb` asks for it.

7. Go back to the **Wireless debugging** screen. Under **IP address & Port**,
   note the IP and the connection port. It is usually different from the
   pairing port.
8. Connect with that port:

```bash
adb connect 192.168.1.42:5555
```

Replace `5555` with the port shown on the phone.

9. Verify:

```bash
adb devices -l
```

The wireless device appears as an IP address and port:

```text
List of devices attached
192.168.1.42:5555    device product:... model:Moto_G_85 device:... transport_id:2
```

The pairing code expires quickly. If pairing fails, tap **Pair device with
pairing code** again and use the new code. The pairing port also changes.

MotoMirror shows the same steps in its Wireless panel. After pairing, the phone
appears in the device list like a USB device.

## 6. Alternative: USB to TCP/IP on port 5555

Use this when the pairing-code flow is unavailable or when the app cannot pair.
The connection lasts until the phone reboots.

1. Connect over USB and authorize the phone. Confirm with:

```bash
adb devices -l
```

2. Switch the phone's ADB daemon to TCP/IP:

```bash
adb tcpip 5555
```

The command prints `restarting in TCP mode port: 5555`.

3. Find the phone IP address with **Settings > About phone > Status > IP
   address**, or read the routing table:

```bash
adb shell ip route
```

The address after `src` is the phone:

```text
192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42
```

4. Connect over Wi-Fi:

```bash
adb connect 192.168.1.42:5555
adb devices -l
```

5. Unplug the USB cable. The phone stays connected over Wi-Fi.

If the connection drops after a reboot, run `adb tcpip 5555` over USB again.

## When the Mac cannot see the phone

Work through this list in order.

### Cable and port

1. Use a USB-C data cable. Test the same cable with a file transfer. If the
   phone only charges and never shows a file-transfer option, the cable is
   charge-only.
2. Plug the cable directly into the Mac. Remove USB hubs, docks, and extension
   cables.
3. Try another USB-C port on the Mac.
4. Try another cable. Cable failures are common.
5. Keep the phone unlocked during the first connection.

### Phone settings

1. Confirm **Settings > System > Developer options > USB debugging** is on.
2. Set **Use USB for** to **File transfer** when the notification appears.
3. Tap **Revoke USB debugging authorizations**, then reconnect and accept the
   new RSA dialog.
4. Turn USB debugging off and on again.
5. Restart the phone if the developer menu is missing or ADB stays offline.

### Mac side

1. Restart the ADB server:

```bash
adb kill-server
adb start-server
adb devices -l
```

2. Confirm that `adb` is the Homebrew build:

```bash
which adb
adb version
```

Expected: `/opt/homebrew/bin/adb` on Apple Silicon. If `adb` is missing, run
`make setup` and open a new terminal.

3. Check whether macOS sees a Motorola USB device at all:

```bash
system_profiler SPUSBDataType | grep -i -A 8 -E 'motorola|moto'
```

If this prints nothing, macOS does not see the phone. The problem is the cable,
the port, or the phone. It is not MotoMirror.

4. If another Android tool is running, close it. Two ADB servers on one Mac can
   conflict. Then repeat step 1.

### Wireless-only problems

1. Confirm that the phone and the Mac are on the same network. A phone on
   cellular data cannot pair.
2. Turn off VPNs on both devices.
3. Do not use a guest network. Guest networks often isolate clients.
4. Use the IP address, not a hostname.
5. On the phone, turn **Wireless debugging** off and on. Then pair again with a
   fresh code.
6. Try the USB `adb tcpip 5555` method in section 6.
7. Restart the Mac Wi-Fi and the phone Wi-Fi if the network changed.

Wireless debugging survives a phone reboot only after you reconnect. On Android
11+, the ports can change after a reboot, so read them from the phone again.

## Command summary

```bash
# USB
adb devices -l

# Wireless pairing (use the addresses shown on the phone)
adb pair 192.168.1.42:37123
adb connect 192.168.1.42:5555
adb devices -l

# USB to TCP/IP
adb tcpip 5555
adb shell ip route
adb connect 192.168.1.42:5555
adb devices -l

# Build and run MotoMirror
make app
open dist/MotoMirror.app
```
