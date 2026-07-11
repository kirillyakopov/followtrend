# followtrend — session handoff

State snapshot for resuming work after a context reset / in a fresh session.

**Resume in one step:** *"Read HANDOFF.md and `git log --oneline -12` on branch
`codex-broker-adjustments-bubble-optimization`, then continue."*

---

## Build & verify

Type-check the whole app with:

```
xcodebuild -project followtrend.xcodeproj -scheme followtrend \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

**Simulators DO work now** (the old "runtime out of date" note is stale). The
machine has the **iPhone 17 family on iOS 26.5** — *not* iPhone 16. List valid
destinations with `xcodebuild -scheme followtrend -showdestinations`. Run tests:

```
xcodebuild test -project followtrend.xcodeproj -scheme followtrend \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

`swiftc -parse <file>` is a fast syntax-only pre-check. `PortfolioImportParser`
is **pure Foundation** (no network) — it also compiles/runs standalone. Test
target `followtrendTests/` now has **`PortfolioImportParserTests` (21 tests) +
`CorrelationServiceTests` (6) — all green.**

## Design system (single source: `DesignSystem/DesignSystem.swift`)

- **Accent is `Color.mintAccent` (#7BE0AE) — NOT `Color.mint`** (that's the
  system teal; a name collision to avoid).
- Loss/negative = muted palette `Color.lossBase` #E37B72 / `.lossText`. **Never**
  `systemRed` or bright red hexes.
- Scroll-list rows use **opaque** `Color.surface` #101013 / `.surfaceWatch`
  #0B0B0D (cheap). Real Liquid Glass (`.glassEffect` / `.glassCard()`) only where
  the spec calls for it (insight cards, floating bars, buttons).
- Native Liquid Glass buttons: `.buttonStyle(.glass)` / `.glassProminent` +
  `.tint()` + `.buttonBorderShape(.capsule)`. Shared: `OverlineLabel`,
  `ChangePill`, `MonogramTile`. SF Pro, tabular numerals on all money/percent.
- Localization: `lm.t("section.key")` (6 langs: en/de/es/fr/ru/uk). A missing key
  renders the raw suffix — every key must exist in all six files.

## Currency model (subtle — read before touching valuation)

Two distinct currencies per `Investment` (`Models/StockModels.swift`):

- **`priceCurrency`** = currency the *live quote* is in: **EUR for crypto**
  (proxy returns `["eur"]`), **USD for stocks** (Yahoo). Convert live price /
  market value from this.
- **`nativeCurrency`** = currency of the *cost basis* (buyPrice/totalCost).
  Convert cost from this.
- Gain/loss: convert **both sides into the selected currency first**, then
  subtract. Never subtract across currencies (that was the crypto bug).
- `CurrencyService.format(value:from:)` converts; `formatConverted(_:)` does NOT
  (use it only for values already in the selected currency). Only EUR & USD exist.

## Data layer (see the API-connectivity notes)

- **Stocks:** Yahoo `query1.finance.yahoo.com/v8/finance/chart` (direct,
  unlicensed, rate-limit risk).
- **Crypto:** Render proxy `crypto-proxy-221x.onrender.com` for prices/candles +
  FX; **CoinGecko** direct for search/resolve (`CryptoDataService.resolveCoins`).
- **Finnhub / Alpha Vantage fully REMOVED** — dead keys, decode structs, the
  `finnhubResolution` var, and `canFetchLiveStockData` are gone; stale comments
  corrected to say Yahoo. `APIConfig` now holds only `proxyBaseURL`,
  `proxySecret` (see secrets note), and `coinGeckoBaseURL`.
- **Proxy secret is no longer committed.** `APIConfig.proxySecret` reads env
  `PROXY_SECRET` → Info.plist `ProxySecret` (populated from `$(PROXY_SECRET)`) →
  `""`. The value lives in gitignored `followtrend/Config/Secrets.xcconfig`
  (template: `Secrets.example.xcconfig`), wired as the app target's base config.
  Absent file ⇒ empty secret ⇒ mock data, build still succeeds.

## What's done (branch `codex-broker-adjustments-bubble-optimization`)

- Full iOS-26 redesign: mint monochrome design system + all screens.
- Bubble physics: 60 Hz fixed step, gravity well, local-only correlation
  repulsion, soft walls, spec sizes, golden-angle cascade entrance, Reduce Motion.
- Native Liquid Glass buttons app-wide; native segmented time selector.
- Portfolio import (paste → parse → **API ticker resolution + "Did you mean?"
  disambiguation** → inline edit synced to text → merge-aware import), per-row
  currency, ghost-bubble import, in-progress-line not flagged as error.
- Insight cards: 4-card native-glass carousel, one card per swipe + page dots;
  Diversification Score gauge (from avg correlation) + Risk Overview
  (portfolio volatility via covariance matrix, max drawdown).
- Crypto currency correctness across home/detail/alert surfaces + chart candle
  aggregation. Debug logging removed.
- Localization across 6 languages for every added string.
- **Cleanup pass (this session):**
  - Watchlist→crypto convert now tags cost basis with the item's `priceCurrency`
    (EUR for crypto), and converts the new lot into the existing position's
    currency before weighted-averaging (`buyWatchlistItem`). Convert-sheet preview
    formats from `priceCurrency` too. *(was open item #2)*
  - Committed secrets removed; Finnhub / Alpha Vantage code deleted. *(#3, #4)*
  - **`PortfolioImportParserTests` (21 tests)** added + wired into the test target.
    Empirically validated against a standalone run of the parser. *(#5)*
  - Fixed two pre-existing bugs that kept the test target from ever going green:
    `CorrelationServiceTests` fed `Double?` into `XCTAssertEqual(…accuracy:)`
    (→ `try XCTUnwrap`); and `CorrelationService.runSelfTests()` used a bogus
    "zero correlation" dataset (`[1,-1,1,-1]` is r≈-0.447) → now `[1,2,2,1]`.

## Open items / known gaps

1. **Old price alerts** keep their pre-fix `baseCurrency` until re-saved (no
   migration written; `PriceAlertStore` untouched).
2. **Proxy secret & git history.** The secret is out of current source, but the
   old literal (`proxySecret`, `finnhubKey`) still exists in past commits. If that
   matters, rotate the proxy token / scrub history (`git filter-repo`) — not done
   (destructive, out of scope). New clones need `Secrets.xcconfig` (copy the
   `.example`) or crypto falls back to mock.
3. **PR not created** (no `gh` CLI / GitHub connector auth). Branch is pushed;
   open via `https://github.com/kirillyakopov/followtrend/pull/new/codex-broker-adjustments-bubble-optimization`.
4. **Beta** metric intentionally omitted from Risk Overview (needs a benchmark
   return series, e.g. SPY). Top-holding concentration took its slot.
5. Import future work: Files-app / share-sheet CSV, batch undo, screenshot OCR
   (Phase 2 Vision — plugs into the same review pipeline).

## Suggested next

Old-alert currency migration (#1) · create the PR (#3) · then feature polish
(SPY-based Beta, CSV import surfaces). Consider adding more parser edge-case tests
and a first test for `CurrencyService` conversions while the target is green.

## Artifacts (design/product docs)

- Import exploration + implementation writeups were published as Claude artifacts
  (portfolio-import). Regenerate/list via the Artifact tool if the URLs are lost.
