# meshcomm design system

Source: Claude design export (`/tmp/meshcomm-design/meshcom.jsx`).
Every new component must reference the tokens below — don't reintroduce
ad-hoc colors, radii or font sizes.

## 1. Color tokens

### Light theme (default)

| token | hex / rgba |
|---|---|
| `bg` | `#FAFAF7` |
| `surface` | `#FFFFFF` |
| `surface2` | `#F2F1EC` |
| `text` | `#15161A` |
| `muted` | `rgba(21,22,26,0.50)` |
| `faint` | `rgba(21,22,26,0.32)` |
| `line` | `rgba(0,0,0,0.06)` |
| `accent` | `#D97757` |
| `accentSoft` | `accent + 15` (alpha 0x15) |
| `incomingBg` | `#F1EFEA` |
| `incomingText` | `#15161A` |
| `outgoingBg` | `accent` (`#D97757`) |
| `outgoingText` | `#FFFFFF` |
| `success` | `#1F8A5B` |
| `danger` | `#C0362C` |
| `info` | `#2A6FDB` |
| `purple` | `#7A5AE0` |
| `pink` | `#C26A8C` |

### Dark theme

| token | hex / rgba |
|---|---|
| `bg` | `#0B0B0C` |
| `surface` | `#141416` |
| `surface2` | `#1C1C1F` |
| `text` | `#F2F2F0` |
| `muted` | `rgba(242,242,240,0.55)` |
| `faint` | `rgba(242,242,240,0.32)` |
| `line` | `rgba(255,255,255,0.08)` |
| `accent` | `#D97757` |
| `accentSoft` | `accent + 22` (alpha 0x22) |
| `incomingBg` | `#1A1A1D` |
| `incomingText` | `#F2F2F0` |
| `outgoingBg` | `accent` |
| `outgoingText` | `#FFFFFF` |

Accent is the *only* brand color; everything else uses neutrals. SOS-related
UI is the single exception (`danger #C0362C`).

## 2. Typography

| role | font | size | weight | tracking |
|---|---|---|---|---|
| display channel name | Geist | 22pt | 600 | -0.02em |
| label sezione (`CANALE`, `PEER IN RAGGIO`, etc) | Geist | 11pt | 500-600 | 0.08em uppercase |
| body / chat bubble | Geist | 15pt | 400 | -0.005em |
| sender label (incoming) | Geist | 11pt | 600 | -0.005em |
| meta / timestamp | Geist | 10.5pt | 400 | tabular nums |
| status strip / pill | Geist | 12pt | 400-500 | tabular nums |
| numeric stats | Geist | 15pt | 600 | tabular nums |
| settings group hint | Geist | 11.5pt | 400 | normal, lineheight 1.45 |
| code / mono | Geist Mono | matching | 400-500 | none |

Fallback stack: `-apple-system, system-ui, sans-serif`.

Status strip and meta use `font-feature-settings: "tnum"` so numbers don't
shift width.

## 3. Iconography

- Line-style SVG, 24x24 viewBox, `stroke: currentColor`, `fill: none`.
- Stroke width 1.5 for outlines, 1.6 for body icons, 1.8 for emphatic
  glyphs (send arrow, check, signal bars).
- Rounded line caps + joins.
- All icons inherit the parent's `text` / `muted` color; only the SOS icon
  and the active send button use `accent` or `danger`.
- Hit target 36x36 (header buttons) or 38x38 (composer round buttons).
- The actual icons used in this app live in `Ic.*` in
  `meshcom.jsx`. SwiftUI replacements pick SF Symbols with `.regular`
  weight and matching point size unless we ship a custom font.

## 4. Spacing & radii

| token | px |
|---|---|
| page edge | 14 |
| section gap | 18-22 |
| stack gap (tight) | 6 |
| stack gap (default) | 8-10 |
| radius small | 10 (rows, list items) |
| radius medium | 12 (status pill, settings group) |
| radius large | 14 (action drawer buttons) |
| radius bubble | 18 |
| radius bubble-tail | 6 (when grouped or sender-side corner) |
| radius round | 999 (text-field, send button, capsule chips) |
| radius card | 16 (settings card) |
| radius sheet top | 22 |

Vertical rhythm: rows of equal kind use `marginTop: 2`, group breaks use
`marginTop: 14`.

## 5. Buttons

### Icon button (header, drawer)
- 36x36, radius 10, transparent background.
- Color = `text`, hover/pressed = `text` w/ 70% opacity.

### Pill button (composer plus/mic)
- 38x38, radius 999, background `surface2`.
- `plus`: rotates 45deg when the action drawer is open.
- `send`: background `accent` when there's text, transparent (mic icon)
  otherwise. Cross-fades over 180ms.

### Action drawer tile (composer expanded)
- Min width 60, radius 14, background `surface2` (`#FEE9E7` for danger
  variant), icon 22pt + 10.5pt label centered.

### Primary save (settings)
- Auto width, radius 999, padding 6 x 12, background `accent`, text white,
  disabled state: transparent bg + `faint` text. Label switches to
  `salvato` for 1400ms after save.

### List row (settings, drawer)
- 100% width, radius 10-16, padding 14 x 14-16, leading icon 18-20pt,
  label 15pt, trailing value `muted` 13pt.
- Danger variant: text + icon `#C0362C`.

## 6. Chat bubble

| direction | bg | text | corners (px) |
|---|---|---|---|
| outgoing single | `outgoingBg` | `outgoingText` | 18 / 18 / 18 / 18 |
| outgoing grouped (not last) | same | same | 18 / 18 / **6** / 18 |
| incoming single | `incomingBg` | `incomingText` | 18 / 18 / 18 / 18 |
| incoming grouped (not first) | same | same | 18 / 18 / 18 / **6** |

- Max width 76%, padding 9 x 13.
- Sender label (incoming only) sits *above* the bubble, color = roster
  `tone` for that peer, 11pt 600.
- Timestamp + read receipt (`Ic.check`) sit *below* the bubble, color
  `faint`, 10.5pt.
- Reaction chip overlaps -8pt above the next sibling, 12pt emoji + count.

## 7. Pin card (shared location)

- Width 240, padding 4, radius 18 with tail 6 on bottom-left.
- Top: 110pt faux topographic map made of:
  - background = radial gradients in `accent` 28/18% alpha + linear
    gradient between `surface2` and `surface`.
  - 8 horizontal sine paths in `faint` 40% alpha.
  - Pin glyph 22x28 in `accent`, halo dot 70x70 with 1.5pt accent border
    at 40% alpha.
- Bottom: 10x10 padding, line 1 = `place` 13pt 600, line 2 = `lat · lon`
  11pt muted tabular nums.
- Footer below the card: `posizione condivisa · HH:mm` 10.5pt `faint`.

## 8. System pill / day separator

- System pill: centered capsule, `surface2` bg, 11pt `muted` text, leading
  12pt icon, radius 999, padding 4 x 10.
- Day separator: uppercase 11pt `faint`, tracking 0.1em, 20pt top margin.

## 9. Side menu (drawer)

- 82% width, max 320pt.
- Background = `bg` (same as chat to maintain depth via shadow only).
- Shadow `4px 0 30px rgba(0,0,0,0.18)` when open.
- Transition: `transform 0.28s cubic-bezier(0.32, 0.72, 0.2, 1)`.
- Sections: profile card (avatar 40 + name + node id + 3-stat row),
  channels list with leading `#` and trailing unread badge, footer
  actions (map, settings).

## 10. Status strip

- 12pt row inside `surface2` pill, leading 6x6 dot with 3pt halo of dot
  color at 18% alpha (`success` for online), trailing battery icon.
- Sits 10pt below the header, 14pt page edge.

## 11. Avatars

Square with `borderRadius = size * 0.35`, background `tone + 22` (alpha
0x22), text color `tone`, 600 weight, initials 2 chars. Roster tones are
deterministic per nickname:

| nickname | tone |
|---|---|
| edoardo | `#D97757` (accent) |
| sofia | `#7A5AE0` |
| marco | `#1F8A5B` |
| luca | `#2A6FDB` |
| giulia | `#C26A8C` |

For other peers, derive the hue from `hash(nickname) % 360`, saturation
0.45-0.55, brightness 0.55-0.92 depending on color scheme.

## 12. Animation timing

- Drawer slide: 280ms `cubic-bezier(0.32, 0.72, 0.2, 1)`.
- Scrim fade: 220ms ease.
- Bottom sheet: 280ms same cubic-bezier, with handle 36x4 radius 2
  centered.
- Full-screen overlay (proximity, settings): 300ms same curve.
- Icon micro-rotation (plus → x): 200ms ease.
- Send/mic cross-fade: 180ms.

## 13. Mapping to SwiftUI

| design token | SwiftUI |
|---|---|
| `bg` | `Color("BgPrimary")` (asset) |
| `surface` | `Color("Surface")` |
| `surface2` | `Color("Surface2")` |
| `accent` | `Color.meshAccent` (`#D97757`) |
| Geist | `.system(...)` (no custom font yet; switch when SPM available) |
| Geist Mono | `.system(..., design: .monospaced)` |

Until we ship the Geist font, every text in this design uses
`.system()` with the size/weight/tracking from §2.

## 14. Out of scope (don't reintroduce)

- Filled `.fill.circle` SF Symbols on the composer (replaced with line
  icons, see §3).
- Heavy/black weight glyphs except the active send arrow.
- Per-button badges/counters on the composer (use the status strip or
  the side-menu unread counts instead).
- OpenStreetMap pre-cache (banned, see commit `666226b`).
