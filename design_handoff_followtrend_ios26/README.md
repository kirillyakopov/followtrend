# Handoff: followtrend — iOS 26 Portfolio App Redesign

## Overview
A complete visual + interaction redesign for **followtrend**, a portfolio tracking app. The goal: feel like an Apple first-party finance app on iOS 26 — calm, premium, minimal, information-rich. Dark monochrome surfaces, one mint-green accent, Liquid Glass materials, native components and transitions, plus a signature **Bubble View** (physics-driven portfolio visualization with clustering).

This package restyles an **existing, already-working app**. Keep the current business logic, data layer and navigation wiring; replace the presentation layer to match these specs.

## About the Design Files
The bundled files are **design references created in HTML** (`followtrend.dc.html` is an interactive prototype; `ios-frame.jsx` is just the device-bezel scaffold for the prototype page). They are NOT production code and must not be shipped or copied directly.

Your task: **recreate these designs in the target codebase's existing environment** — for an iOS app that almost certainly means SwiftUI (or UIKit) with native system components. Where the design mimics a native control, USE the native control rather than rebuilding it. If parts of the app live in another stack (React Native, Flutter…), apply the same tokens/specs using that stack's native-feeling equivalents.

The HTML source is readable and contains every exact value (colors, sizes, spacing, animation curves, physics constants). Treat it as the source of truth when this README is ambiguous.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, copy, and motion are final. Recreate pixel-perfectly using native equivalents (SF Pro is automatic on iOS; use real SF Symbols instead of the prototype's placeholder line-icons; use real system materials instead of CSS blur).

## Design Tokens

### Color — backgrounds (dark only)
- App background: `#020202` (base), top-of-screen wash to `#0A0A0B`
- Elevated list/card surface (opaque): `#101013`, `#0B0B0D` (watchlist rows), `#111113`
- Widget tile: linear-gradient 160° `#151517 → #0B0B0D`
- Glass card (insight cards): linear-gradient 180° `rgba(255,255,255,0.08) → rgba(255,255,255,0.035)`, background blur 26px + saturate 170%, border 0.5px `rgba(255,255,255,0.09)`, inner top highlight `inset 0 1px 0 rgba(255,255,255,0.08)`, shadow `0 14px 30px rgba(0,0,0,0.38)` → in SwiftUI use `.ultraThinMaterial`/`.regularMaterial` (dark) or iOS 26 Liquid Glass APIs
- Sheet surface: `rgba(17,17,19,0.90)` + blur 44px saturate 180%, top border 0.5px `rgba(255,255,255,0.13)` → native sheet with dark material
- Floating bars (tab bar / toolbars / menus): `rgba(22,22,25,0.60–0.66)` + blur 36px saturate 185%, border 0.5px `rgba(255,255,255,0.10)`, shadow `0 14px 36px rgba(0,0,0,0.55)`

### Color — accent & semantics
- **Mint (single accent):** `#7BE0AE` — gains, active states, primary buttons, toggles-on
- Mint on-fill text (dark ink on mint): `#04140C` / `#0A2A1B`
- Gain text tints: `#8FE8BD`, `#DCF8EA` (inside bubbles)
- **Loss (muted, never bright red):** base `#E37B72`; text tint `#F0A198`; destructive swipe `#C0453D`; loss pill fill `#C0665E`
- Neutral/flat: `#8E8E93` family
- Labels: primary `#F2F2F4`; secondary `rgba(235,235,245,0.5–0.58)`; tertiary `rgba(235,235,245,0.30–0.34)`; quaternary `rgba(235,235,245,0.24)`
- Separators: 0.5px `rgba(255,255,255,0.06–0.08)`
- SwiftUI: define these as asset-catalog colors; map gain/loss to custom semantic colors, do NOT use systemRed/systemOrange.

### Typography (SF Pro, system font)
- Large title: 33pt / 800 / letter-spacing −0.7
- Hero value: 41pt / 700 / −1.4, **tabular numerals** (`.monospacedDigit()`)
- Screen-subvalue (bubble header): 25pt / 800
- Section header: 20pt / 800
- Sheet title: 22pt / 800
- Row title: 15pt / 700; row price 15pt / 700 tabular
- Body/detail: 13–14.5pt / 500–650
- Caption: 11–12.5pt / 500–650
- Overline labels: 11pt / 700 / +1.1 tracking / UPPERCASE, tertiary color (e.g. "TOTAL VALUE", "GENERAL")
- All money/percent values: tabular numerals everywhere.

### Radii
- Sheets: 28–30 (top corners) · Cards: 20–26 · List container: 24 · Watchlist row: 18 · Buttons/fields: 12–16 · Pills/segmented/tab bar/toggles: capsule (999)

### Spacing
- Screen horizontal margin: 20 (content), 16 (cards/lists)
- Card padding: 14–18 · Row padding: 11–13 vertical, 14–16 horizontal
- Section rhythm: 16–24 between blocks
- Hit targets ≥ 44pt (34pt round icon buttons have padded tap areas)

### Iconography
SF Symbols only: `plus`, `chart.line.uptrend.xyaxis`, `circle.hexagongrid` (bubbles tab — or `bubbles.and.sparkles`), `eye`, `slider.horizontal.3`, `magnifyingglass`, `arrow.up.arrow.down`, `checkmark`, `info.circle`, `arrow.counterclockwise`, `chevron.right`, `xmark`. Weight: medium/semibold, sizes 12–22pt.

## Screens / Views

### 1. Portfolio (Home tab)
Scrolling stack, content scrolls under a top gradient scrim (`#020202` 88% → transparent, 64pt tall).
1. **Nav row:** date overline left ("TUESDAY, JUL 8", 13pt/600 secondary); right 34pt glass circle button `plus` in mint → Add Asset.
2. **Large title** "Portfolio".
3. **Hero block:** overline "TOTAL VALUE"; value 41pt tabular; change pill (capsule, mint 13% fill, 0.5px mint 16% border, 13pt/650 mint text, e.g. `+$791.24 (+0.81%)`) + range label ("Past Month") 13pt secondary. Pill/value re-bind while scrubbing the chart; negative delta switches pill to loss tints.
4. **Performance chart:** 172pt tall, smoothed line 2.4pt (mint when range is up, muted red when down), gradient area fill (accent 24% → 0), dashed baseline at period start `rgba(255,255,255,0.12)`. Touch scrub: vertical hairline `rgba(255,255,255,0.34)` + 4.4pt dot with 2pt dark ring; hero value/delta track the scrubbed point. Swift Charts + `DragGesture`.
5. **Time selector:** capsule segmented control `1H 1D 1W 1M 3M 1Y MAX`; track `rgba(118,118,128,0.13)`, sliding thumb `rgba(255,255,255,0.14)` capsule (spring ~320ms), active label white, inactive `rgba(235,235,245,0.48)`, 12pt/650.
6. **Insight cards:** horizontal paging carousel, cards 294×164, corner 26, Liquid Glass recipe, `scroll-snap` = `.scrollTargetBehavior(.viewAligned)`. Cards: **PORTFOLIO ALLOCATION** (92pt donut, ring thickness ~38%, segments: mint, mint 55%, white 66%, white 34%, white 16%; legend top-4 with 8pt dots), **REBALANCING** (headline 17pt/700 "Technology is 8.2% overweight", body 13pt secondary, mint capsule chip "Review suggestion"), **DIVERSIFICATION SCORE** (84pt gauge ring, 245°/360° mint arc, center "68" 24pt/800; grade "Good" + one-liner), **RISK OVERVIEW** (3 rows: Beta 1.12 · Volatility 30D 14.8% · Max drawdown −9.4%, each with 4pt track + colored fill bar).
7. **Search field:** 38pt, radius 13, fill `rgba(118,118,128,0.16)`, magnifier 45% opacity, placeholder "Search positions" → `.searchable` or custom; filters list live.
8. **Positions header:** "Positions" 20pt/800 + count in tertiary; right sort chip (glass capsule, `arrow.up.arrow.down` + current sort, 12.5pt/600) opening a **pull-down menu** (radius 16, dark glass, "Sort by" header, options Performance / Name / Allocation / Newest / Oldest, mint checkmark). Use native `Menu`.
9. **Positions list:** one container `#101013`, radius 24, 0.5px border, inset separators. Row (≈68pt): 40pt monogram tile (per-ticker muted hue, radius 12, letter 700) · ticker 15/700 + company 11.5 secondary (truncate) + "42 sh · avg $168.30" 11 tertiary · 52×20 sparkline (mint/red by day change, 1.6pt) · right: price 15/700 tabular + P/L line 11.5/600 colored `+$3,310 (+46.8%)`. **Swipe actions:** Edit (gray `rgba(120,120,128,0.32)`) and Delete (`#C0453D`), 74pt each — native `.swipeActions`. Tap row → Asset Detail sheet.
10. Footer hint 11.5pt quaternary: "Swipe a row for actions · Tap for details".

### 2. Bubble View (signature screen)
- **Header:** overline "PORTFOLIO", value 25pt/800, day change line 12.5/650 colored. Right: two 34pt glass circles — `info.circle` (opens Correlation sheet) and `arrow.counterclockwise` **Restore** with mint count badge (16pt capsule, dark ink) when popped bubbles exist; icon dims to 40% when none.
- **Hint line** (11.5pt, 30% white, centered): "Tap & drag to move · Hold to select or create clusters".
- **Physics field** fills remaining space. Each holding is a circular bubble:
  - **Size = allocation:** radius = `15 + sqrt(value/totalValue) × 76` pt (range ≈ 29–49).
  - **Color = performance** (total return): gain = mint radial gradient (`rgba(123,224,174, 0.21–0.38)` at 32%/28% highlight → 4%), 1px border mint 26%, **soft outer glow only** `0 0 (0.8×r) rgba(94,214,158, ~0.22)`; loss = same recipe in muted red; flat (|return| < 1.5%) = white/neutral. No thick borders. Subtle inner top highlight. Content: ticker 800 (font scales ~0.32×r, 10–19pt) + return % below (650, tabular), tinted per state.
  - **Ghost bubbles (watchlist):** small r=21, transparent fill 2.5%, **1.5px dashed** border `rgba(235,235,245,0.22)`, muted label, no %, no glow. They drift in the field but never count toward value.
  - **Motion:** gentle idle wander (sinusoidal micro-forces), weak pull to field center, pairwise soft collision (mass ∝ r², positional correction ~32% of overlap + small velocity impulse), soft walls, damping 0.945/frame, speed cap. 60fps. iOS: SpriteKit physics or a custom `TimelineView`/`CADisplayLink` loop — mirror constants from the prototype's `physStep()`.
  - **Interactions:** drag moves a bubble (spring-follows finger, scales to 1.06, others yield); **hold ~460ms** enters selection mode (mint ring `0 0 0 3px rgba(123,224,174,0.5)` on selected); in selection mode taps toggle; tap (no move) on an asset opens a small **popover card** (196pt, radius 18, dark glass) with ticker, name, value, all-time P/L and two buttons: **Details** (mint tint) / **Pop** (gray); tap a cluster bubble → Cluster View; tap a ghost → Asset Detail.
  - **Pop:** scale to 1.38 + fade, 320ms ease-in; popped bubbles queue behind the Restore button. **Restore:** re-spawns near center with pop-in (scale 0.2 → 1.08 → 1.0, 550ms, springy `cubic-bezier(0.34,1.45,0.45,1)`). Entering the tab cascades all bubbles in with 42ms stagger.
  - **Clusters:** created from ≥2 selected bubbles; cluster bubble radius = `min(78, sqrt(Σr²) × 1.05)`, shows a two-circles glyph + member count + combined return; spawns at selection centroid; auto-name `"MSFT +2"`.
- **Floating toolbar** (above tab bar, glass capsule): default `[+ Add | ⓘ Correlation | ↺ Restore]`; selection mode `[n selected | Cluster (mint tinted capsule, disabled <2) | Pop (loss tint) | Done]`.

### 3. Add Asset
Full-height sheet (top ≈54pt below status bar), grabber 36×5.
- Nav row: **Cancel** (mint, left) · centered title "Add Asset".
- **Search field embedded above results** (not in the nav bar), placeholder "Ticker or company name", circular clear button when text.
- **SUGGESTED** chips when query empty (capsules, gray glass): NVDA · VOO · SOL · DIS · SCHD — tapping fills the query and switches tab.
- **Segmented control:** Stocks / ETFs / Crypto (radius 12 track, sliding thumb, 13pt/650).
- **Results list** (glass container, radius 20): 36pt monogram · ticker 15/700 (+ tiny mint "OWNED" capsule when already held) + company 12 secondary · right price 14.5/700 + **24h change pill** (solid mint w/ dark ink, or `#C0665E` w/ light ink, 11.5/700). Tap → Asset Detail sheet on top.

### 4. Asset Detail
Sheet (top ≈96pt), grabber; scrollable.
- **Header:** 52pt logo tile · ticker 22/800 + company 12.5 secondary · right: price 21/800 tabular + "+1.63% today" 12/700 colored.
- **Chart:** 118pt, same line/area treatment; footer row "PAST MONTH" + period % (10.5pt overline style).
- **Statistics:** 2-column grid card (radius 20, glass): OPEN · HIGH · LOW · VOLUME · MKT CAP · P/E — key 11pt/600 tertiary, value 14.5/650 tabular, hairline row separators.
- **Context-dependent actions:**
  - *Owned:* "YOUR POSITION" card (mint 7% fill, mint 14% border) with Shares / Avg cost / Return columns, then **Edit Position** (gray glass, full-width, radius 16).
  - *On watchlist:* dashed info strip "On your watchlist — doesn't affect portfolio value." + **Convert to Position** (solid mint, dark ink, 800) + **Set Price Alert** (gray glass).
  - *Neither:* **Add to Portfolio** (solid mint) + **Add to Watchlist** (gray glass).
- **Form mode** (add/edit/convert): overline title; inset grouped fields **Shares** and **Average price** (right-aligned mint 16/600 numeric entry, decimal pad); live helper "≈ $4,320.10 at current price"; primary save button (label varies: Add to Portfolio / Save Changes / Convert to Position); owned positions also get **Remove Position** (loss-tinted glass). Saving updates the list and spawns a bubble; confirmations use a top **toast capsule** (dark glass, mint checkmark, e.g. "Added NFLX to Portfolio").

### 5. Watchlist
- Large title "Watchlist", overline count, mint `plus` button.
- Info strip (dashed border, dashed-circle glyph): "Ghost bubbles — they float in Bubble View but never affect your portfolio value."
- **Rows as separate dashed cards** (radius 18, fill `#0B0B0D`, **1px dashed** `rgba(235,235,245,0.16)`, 10pt gaps): greyscale-muted 38pt logo, ticker/name at 85%/42% opacity, right price + "+0.91% 24h" in *muted* gain/loss tints (~70% opacity).
- **Swipe actions (3):** Convert (`#1E7A54`) · Alert (`#48484E`) · Delete (`#C0453D`), 66pt each. Convert opens the detail form pre-filled; Alert fires a toast.

### 6. Cluster View
Opening a cluster dims + blurs the field (`rgba(2,2,2,0.62)` + blur 16).
- Header: overline cluster name, combined value 27/800, combined return line; X close circle.
- **Children in a radial layout** around center — ring radius `R = clamp(92…132, (2·maxChildR + 12) / (2·sin(π/n)))` so bubbles never overlap; slight vertical ellipse (0.92); faint dashed guide ring. Children scale by share within cluster (r = 25 + sqrt(share)·26), same color language, **staggered pop-in** (55ms/child, springy). Tap child → Asset Detail.
- **Analytics card** (bottom, dark glass, radius 24, slides up like a sheet): rows **Combined value · Combined return · Avg correlation ("+0.62 · High") · Largest holding ("MSFT · 42%") · Top performer ("GOOGL · +41.8%")**; link "What does correlation mean?" (mint, info icon) → Correlation sheet; buttons **Break Up** (loss-tint glass) / **Done** (gray glass).

### 7. Correlation Info Sheet
Medium sheet (top ≈168pt). Title "Correlation" + one-liner "How closely two holdings move together — measured by Pearson's r."
- **Spectrum card:** 10pt gradient bar `#D96A60 → #8E8E93 (50%) → #7BE0AE`, tick labels −1 · −0.7 · −0.3 · 0 · +0.3 · +0.7 · +1 (10pt/600 tabular), floating mint marker pill "You · +0.42" positioned at the portfolio's average; small monospace footnote `r = cov(x, y) / (σx · σy)`.
- **Three glyph cards** (3-col grid): "+1 Move together" (two parallel mini-lines, mint-tinted card), "0 Independent" (neutral), "−1 Move opposite" (mint vs red mirrored lines, red-tinted card). Minimal text.
- **WHY IT MATTERS** card: "Lower average correlation smooths portfolio swings. Bubbles that move together are natural candidates for a cluster." + Done button.

### 8. Settings
Standard inset-grouped style, large title.
- **GENERAL:** Language (English) · Currency (USD) · Theme (Dark) — detail + chevron rows.
- **SECURITY & PRIVACY:** Notifications · Face ID · **Privacy Mode** — native toggles (51×31 capsule, mint when on, white 27pt knob). Footer: "Privacy Mode hides all monetary values across the app and widgets." Privacy Mode replaces every money string app-wide with `$•••••` (percentages stay visible).
- **ABOUT:** Version "1.0 (42)" (no chevron) · Privacy Policy · Rate followtrend.
- Rows 15.5pt/500, detail 14.5 secondary, hairline separators, cards radius 20.

### 9. Home Screen Widgets (WidgetKit)
Dark tiles (gradient `#151517 → #0B0B0D`), mint accent, tabular numerals, tiny brand glyph + wordmark 10pt/700.
- **Small:** portfolio value 19/800, "+0.81% today" 11/700 mint, area sparkline pinned to bottom.
- **Medium:** left — PORTFOLIO overline, value 23/800, day change line, "MARKETS OPEN · 9:41 AM" micro-caption; hairline divider; right — TOP PERFORMER: 26pt logo + ticker + "+79.2%" 15/800 mint + sparkline.
- **Large:** value + day-% pill (solid mint, dark ink); **allocation bar** (9pt, segmented with 2pt gaps, same 5 segment colors) + dot legend; divider; **WATCHLIST** (3 rows: dashed micro-dot, ticker, muted 24h %); footer **Quick Add** (mint-tint capsule) + **Search** (gray capsule) deep-link buttons.

## Interactions & Behavior (system-wide)
- **Navigation:** 4-tab floating glass tab bar (capsule, icons 21pt + 10pt/600 labels; active = mint + `rgba(255,255,255,0.09)` pill). Screen switches crossfade/raise 340ms `cubic-bezier(0.25,0.8,0.3,1)` — native tab transitions are fine.
- **Sheets:** slide up 460ms `cubic-bezier(0.32,0.72,0,1)` (≈ iOS spring), dim `rgba(0,0,0,0.44–0.5)`, grabber, tap-outside dismiss, ~330ms dismiss. Use native `.sheet` + detents.
- **Menus/popovers:** scale-in from anchor 180–220ms with slight overshoot.
- **Toast:** top capsule, 320ms in, auto-dismiss ~2.1s.
- **Bubble motion:** see Bubble View; honor **Reduce Motion** (kill wander, heavier damping, no overshoot springs).
- **Haptics (add in native build):** light impact on bubble grab/selection, success on save/cluster, rigid on pop.

## State Management
- `positions: [{ticker, shares, avgPrice}]` (derived: value, P/L, allocation, day change)
- `watchlist: [ticker]` · `clusters: [{id, name, members}]` · `poppedBubbles: [ticker]`
- UI: `selectedTab`, `chartRange`, `scrubIndex?`, `searchQuery`, `sortBy`, `selectionMode + selectedIDs`, `openCluster?`, presented sheet (add / detail(ticker, mode: view|form|edit) / correlation), `settings {language, currency, theme, notifications, faceID, privacyMode}`, transient toast.
- Flows: add/convert/edit write back to `positions` and remove from `watchlist`; delete/pop/restore mutate accordingly; bubbles/lists re-derive automatically.
- Prototype ships fake deterministic data — wire to your existing models/quotes service.

## Assets
No raster assets. Monogram tiles (per-ticker muted hue, HSL ~24–30% sat / 15–27% light gradient) stand in for logos — swap in your real logo pipeline if you have one, keep 40pt/radius-12 tiles. All icons = SF Symbols. Fonts = system SF Pro.

## Files
- `followtrend.dc.html` — the full interactive prototype (all 8 screens + widgets). Template markup at top; all logic (physics constants, animation curves, data shapes, formatting) in the `Component` class at the bottom. **Reference only.**
- `ios-frame.jsx` — device-bezel scaffold used by the prototype page. Ignore for implementation.

## Suggested Claude Code prompt
> Read `design_handoff_followtrend_ios26/README.md`. Restyle my existing followtrend app to match it exactly, keeping current data/business logic. The HTML file is a design reference, not code to port. Use native SwiftUI/iOS 26 components (searchable, swipeActions, Menu, sheets with detents, segmented Picker, Swift Charts, WidgetKit) and SF Symbols. Build the Bubble View physics with SpriteKit or a CADisplayLink loop using the constants in the README. Work screen by screen, starting with the design tokens, then Portfolio.
