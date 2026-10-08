# Google Play store listing: PingDuck

Paste these into Play Console → **Grow users → Store presence → Main store
listing**, and the other sections named below. Character limits are Google's;
counts are checked by `compose.py`.

To rebuild the screenshots after UI changes (the demo network "Duck Pond" is
made up, so no real devices appear):

```sh
cd pingduck_app
flutter drive -d emulator-5554 --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/store_screenshots_test.dart   # -> raw/
cd .. && python store/google-play/compose.py               # -> screenshots/, feature-graphic.png
```

## App name (30 max)

```
PingDuck: Network Scanner
```

## Short description (80 max)

```
See every device on your Wi-Fi: names, makers, latency and open ports.
```

## Full description (4000 max)

```
PingDuck finds every device on your Wi-Fi in seconds, then tells you what each one is, how fast it answers and which ports it has open. Playful on the surface, properly technical underneath.

SEE WHO'S ON YOUR NETWORK
• Scan the Wi-Fi network you're on and list every device that responds, with its IP address, name, manufacturer and the services it advertises.
• The latency map plots each device by response time, so slow or struggling devices stand out at a glance.
• PingDuck remembers devices from earlier scans, so you can see what's new and what has gone offline.
• Sort by latency, IP, name, maker or last seen, and filter to online or offline devices.

INSPECT ANY DEVICE
• Live ping with min, average and max latency, jitter and packet loss.
• Quick scan of common ports, or a deep scan of ports 1 to 1024, with hints for risky services such as Telnet and SMB.
• Name devices and keep notes, so "192.168.1.88" becomes "Thermostat".
• Copy a device's details as JSON.

HOW IT FINDS DEVICES
PingDuck combines ICMP ping, mDNS (Bonjour), SSDP/UPnP, NetBIOS and DNS lookups. Manufacturer names come from a built-in copy of the IEEE OUI registry, so lookups work offline.

PRIVATE BY DESIGN
• No sign-up needed. Scanning works the moment you open the app.
• Your device list, names and notes stay on your phone.
• No ads and no tracking.
• Want an account? Create one with your email and a password. Delete it any time from the Account tab.

FREE TO USE
The free plan includes 3 scans a day that you start yourself. The automatic scan when you open the app or reconnect to Wi-Fi doesn't count.

COMING SOON
The Homelab Agent: a small Docker container for your server, NAS or Proxmox box that adds exact MAC addresses, 24/7 history and alerts when an unknown device joins your network. Android doesn't let apps read other devices' MAC addresses, so the agent fills that gap.

Only scan networks you own or have permission to test.
```

## Graphics

| Asset | File | Google's spec |
| --- | --- | --- |
| App icon | `icon-512.png` | 512 × 512 PNG, up to 1 MB |
| Feature graphic | `feature-graphic.png` | 1024 × 500 PNG or JPEG, no transparency |
| Phone screenshots | `screenshots/01-06*.png` | 2–8 images, 1080 × 1920 (9:16), no transparency |

Tablet screenshots are optional; skip them until the layout is checked on a
tablet.

## Store settings

| Field | Value |
| --- | --- |
| App category | Tools |
| Tags | Network tools, Wi-Fi, Utilities (pick from Google's list) |
| Email | support@pingduck.app |
| Website | https://pingduck.app |
| Privacy policy | https://pingduck.app/privacy |
| Ads | No, the app contains no ads |
| Target audience | 18 and over (or 13+; the app isn't designed for children) |

## App content → Data safety

Answers that match what the app does today (see the privacy policy). Review
them against the current build before submitting; update when cloud sync,
the agent, analytics (PostHog) or billing ship.

- **Does your app collect or share any of the required user data types?** Yes.
- **Is all of the user data collected by your app encrypted in transit?** Yes.
- **Do you provide a way for users to request that their data is deleted?**
  Yes: in the app (Account → Delete account) and at
  `https://pingduck.app/delete-account`.

Data types (all **collected, not shared**; service providers acting for you,
like Supabase and Resend, don't count as sharing):

| Category → type | Required or optional | Purposes |
| --- | --- | --- |
| Personal info → Email address | Optional (only if the user creates an account) | Account management |
| Personal info → User IDs (the account ID, including the anonymous one) | Required | App functionality, Account management |
| App activity → App interactions (the daily scan count) | Required | App functionality |

Not collected: location (the permission only reveals the Wi-Fi name, which
stays on the phone), the device list and scan results (they never leave the
phone), contacts, files, and crash or performance data.

Judgment call: Supabase's request logs include IP addresses, kept briefly for
security. Google doesn't require declaring data used only for security and
abuse prevention in server logs unless you use it for other purposes; if you
want to be maximal, declare **Device or other IDs** for security / fraud
prevention.

## App content → Account deletion

Delete account URL: `https://pingduck.app/delete-account`
