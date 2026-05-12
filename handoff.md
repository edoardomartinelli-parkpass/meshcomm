# handoff — OpenChat (bitchat fork)

## Goal

Build a competition-ready iOS app called **OpenChat** for a Google
"vibehaton". Started life as the user's React Native project
(`/Users/edoardomartinelli/Desktop/Cursor/openchat`) but pivoted to a
fork of [`permissionlesstech/bitchat`](https://github.com/permissionlesstech/bitchat)
because Bluetooth peripheral mode is not feasible to implement on RN
in 2 hours. Native Swift fork lives at
`/Users/edoardomartinelli/Desktop/Cursor/meshcomm-ios` and is pushed
to <https://github.com/edoardomartinelli-parkpass/meshcomm>.

The pitch: BLE mesh peer-to-peer chat for emergencies / no-internet
scenarios, with an SOS broadcast button + map + proximity radar +
direction-of-arrival from GPS fixes shared via SOS payloads.

## Branding

- App display name was rebranded twice: `bitchat` → `meshcomm` →
  `OpenChat`. Latest is **OpenChat** (Info.plist + xcstrings + Settings).
- Bundle identifier still `chat.meshcomm.dev`; folders, scheme name,
  internal queue labels still `bitchat*`. Not changed because the
  Xcode project rename is a bigger refactor than the timebox allows.
- Custom icon: user dropped `iosappicon/AppIcon Exports/` under
  `~/Desktop/Cursor/openchat/`. We use `AppIcon-iOS-Default-1024x1024@1x.png`
  installed into every slot in `AppIcon.appiconset` + `AppIconDebug.appiconset`.
- Launch screen: `bitchat/Assets.xcassets/SplashImage.imageset/` is a
  Higgsfield `gpt_image_2` generation — black bg, faint orange grid,
  centered `OpenChat` wordmark glow. `LaunchScreen.storyboard` hosts
  a single fullscreen `UIImageView` with that asset.

## State of the code (latest commit `b28f512`)

Push log on `main`:

| Commit | What |
|---|---|
| init | initial fork copy |
| `efb7a80` (later overwritten by `init`) | seed |
| `ab68dd6` → squashed | first meshcomm rebrand |
| `666226b` | fix: remove OSM offline tile overlay (HTTP 403) |
| `21f5127` | feat: BLE proximity radar with approaching/receding indicator |
| `7b6d22f` | feat: hamburger menu + settings sheet |
| `86a70d5` | feat: chat bubbles (Telegram/WhatsApp style) |
| `df514b6` | feat: pill composer + shrink-to-content bubbles |
| `1b26ffc` | feat: uniform composer icons |
| `2dd587d` | feat: bulk UX cleanup (drawer scrim, defaults, theme picker) |
| `5172b81` | fix: bump channels AppStorage key to v2 |
| `f2418cf` / `f2860da` | meshcomm app icon iterations (later replaced) |
| `d3e57ec` | HD neon splash screen |
| `b24b1d2` | minimalist grid splash |
| `af40e0d` | feat: rebrand to **OpenChat** + new app icon + matching splash |
| `367d5b2` | fix: dismiss keyboard when opening the side drawer |
| `b28f512` | feat: peer direction sheet from radar tap (LATEST) |

`xcodebuild ... build CODE_SIGNING_ALLOWED=NO` passes on `iPhone 17`
simulator (arm64). Last green log: `/tmp/meshcomm-build36.log`.
On-device build on the user's iPhone 17 worked end-to-end.

### Features live in the app

- Chat bubble UI matching `DESIGN.md` (outgoing accent solid right-
  aligned, incoming `surface2` left-aligned, sender label on top in
  per-nickname deterministic hue, SOS bubbles red-framed).
- Composer: pill capsule, `+` rotating into `x` to reveal an action
  drawer with `sos`/`mappa`/`radar`/`foto` tiles, send/mic round
  button. Plus button shows a red dot when a non-own SOS is unread;
  the mappa tile inherits the same dot inside the drawer.
- Header: hamburger left → SideDrawerView; `#topic` 22pt 600 center
  with accent `#`; trailing envelope (if unread) + ellipsis →
  ChannelMoreSheet. No "canale" caption.
- StatusStrip pill under header: green dot + `mesh attiva · N nodi`
  + battery icon.
- Side drawer: profile card (avatar 40 + nickname + node short id),
  stats row (active nodes, hop max placeholder, real `UIDevice`
  battery), channels list (binding to managed channels), footer
  with only `impostazioni`.
- Channel manager sheet: insetGrouped, swipe-to-delete (`#mesh`
  protected), add field with animated `+` button, persisted as JSON
  in `AppStorage("meshcomm.channels.v2")`. Default seed: a single
  `#global` channel.
- Channel more sheet: silenzia/info canale/membri(n)/cerca/esci.
  No "condividi posizione live" (deduped against the SOS composer
  action).
- Settings sheet: identita' (callsign rename), aspetto (segmented
  picker sistema/chiaro/scuro persisted under
  `meshcomm.themePreference` and applied via `.preferredColorScheme`
  on both ContentView and the sheet itself), strumenti (mappa SOS,
  proximity radar), info (version + fork credit + github link),
  danger zone (emergency wipe).
- SOS:
  - `SOSButton` confirmation → `ChatViewModel.sendSOSMessage`
    (forces mesh broadcast bypassing active channel)
  - `[SOS]` parsed in `ChatViewModel.handlePublicMessage` and
    `sendSOSMessage` to populate `sosPins`
  - SOS map sheet with MKMapView wrapper
  - Unread SOS badge on `+` composer + map tile, cleared on map open
- Proximity radar:
  - `ProximityTracker` singleton in `BLEService.swift` (ring buffer,
    log-distance path-loss model, trend from delta of last vs first
    half of buffer)
  - Hooks in `centralManager(_:didDiscover:...)` and the announce-
    packet handlers
  - Radar sheet refreshes every 1.5s
  - **NEW**: tap on a radar row opens `PeerDirectionSheet` with a
    compass arrow rotated to the bearing computed from CoreLocation
    + the peer's most recent `[SOS]` pin coords; meters via
    `CLLocation.distance(from:)`. Fallback when no GPS or no SOS.

### Persistence keys

- `meshcomm.channels.v2` — JSON-encoded `[ManagedChannel]`
- `meshcomm.sos.lastSeenID` — last seen incoming SOS message id
- `meshcomm.themePreference` — `"system" | "light" | "dark"`

## Files actively edited

| Path | What |
|---|---|
| `bitchat/Views/ContentView.swift` | massive — header, status strip, composer, drawer overlay, SOS badges, side drawer, channel manager, channel more sheet, settings sheet, proximity radar, peer direction sheet |
| `bitchat/Views/Components/TextMessageView.swift` | chat bubble redesign |
| `bitchat/ViewModels/ChatViewModel.swift` | `sendSOSMessage`, `appendSOSPinIfPresent`, `extractSOSCoordinate`, `sosPins` published |
| `bitchat/Services/BLE/BLEService.swift` | `ProximityTracker` singleton + 3 hooks |
| `bitchat/Info.plist` | display name, BLE/camera/mic/photo/location permission strings |
| `bitchatShareExtension/Info.plist` | display name + bundle id |
| `bitchat/Localizable.xcstrings` | 115 string swaps across 29 locales |
| `bitchat/LaunchScreen.storyboard` | rewritten to host fullscreen `UIImageView` of `SplashImage` |
| `bitchat/Assets.xcassets/AppIcon.appiconset/*` | all 11 PNGs swapped |
| `bitchat/Assets.xcassets/AppIconDebug.appiconset/image-1024.png` | swapped |
| `bitchat/Assets.xcassets/SplashImage.imageset/*` | new imageset |
| `Configs/Release.xcconfig` | removed `DEVELOPMENT_TEAM` hardcoded for permissionlesstech |
| `DESIGN.md` | source-of-truth tokens, components, animation timing |
| `handoff.md` | this file |

## Things tried that failed

- **React Native + Expo Go path.** Demo mode worked on simulator,
  but BLE on Expo Go is a non-starter (no native module). Spent
  ~30 min lazy-loading MMKV + ble-plx so the JS bundle could at
  least load in Expo Go; then dropped the whole approach.
- **OpenStreetMap tile prefetch.** Built a `MeshTilePrefetcher` +
  `MeshOfflineTileOverlay`. OSM returned HTTP 403 PNGs ("Access
  blocked") for our user agent. We saved those 403 PNGs as if they
  were tiles, so the SOS map showed "Access blocked" on top of
  Apple Maps. Removed in commit `666226b`; the map cache directory
  is now auto-wiped on first map open. Real offline tiles will need
  Mapbox / MapTiler / Stadia or self-hosted.
- **In-place rename of the Xcode project from `bitchat` to
  `OpenChat`.** Project name still says `bitchat`; folders too.
  Would have required surgery on `project.pbxproj`, scheme XML,
  and `Package.swift`, all on the same path that the Tor local
  package + entitlements reference. We rebranded only what's
  user-visible (display name, splash, settings about row, xcstrings).
- **Higgsfield `--image` flag with a path that contains spaces.**
  CLI reported "neither a UUID nor an existing file path". Workaround
  was to copy the reference to `/tmp/icon-ref.png` before invoking.
- **iOS device signing for "iPhone di Luca"** (user's father's phone).
  Xcode showed `Status: No Accounts` despite the Apple ID being
  configured. The user re-logged from Settings → Apple Accounts and
  the team picker filled in. Then we hit `Missing package product
  'P256K'` because DerivedData was just wiped — fixed by running
  `xcodebuild -resolvePackageDependencies` from the project dir.
  Final status: user was prompted to repeat the trust + Developer
  Mode dance on the iPhone; we did not see whether the on-device
  build went green.

## Next step

1. Confirm the iPhone-di-Luca build actually launches. Most likely
   the trust + Developer Mode steps got skipped. If `Try Again`
   under the provisioning profile error still fails, manually
   register the UDID `00008101-0010796E0E38001E` at
   <https://developer.apple.com/account/resources/devices/list>
   and rerun.
2. Verify the new splash actually appears on the user's iPhone
   ("edoardo") device. They reported still seeing the old splash;
   we wiped DerivedData on the Mac and asked them to uninstall +
   reboot the phone (iOS caches launch screen snapshots until
   reboot). Outcome not yet reported.
3. Decide whether to wire **real unread counts** into the channel
   badges in `ManagedChannel`. Today they're a static `unread: 0`
   field, no observer feeds them from `viewModel.sosPins` or chat
   messages. Mid-priority for the demo.
4. Audit `bitchat://` deep links: still present in `BitchatApp.swift`
   and `MessageListView.swift` URL handlers. Either rename to
   `openchat://` everywhere (also `CFBundleURLSchemes`) or leave
   them for interop with the upstream app. Not a blocker.
5. If the user actually wants to ship to TestFlight / App Store,
   `chat.meshcomm.dev` bundle id needs to become `chat.openchat.<x>`
   and a paid Apple Developer Program slot has to be tied to it.
6. Optional polish backlog: real battery telemetry on macOS,
   custom channel hints (the manager currently writes "creato
   adesso"), member list under `membri (n)` in the channel-more
   sheet (today routes to the bitchat peopleSheet which is the old
   monospaced view), search-in-messages (today no-op).
