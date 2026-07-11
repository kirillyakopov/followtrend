# followtrend — session handoff

State snapshot for resuming work after a context reset / in a fresh session.

**Resume in one step:** *"Read HANDOFF.md and `git log --oneline -12` on branch
`codex-broker-adjustments-bubble-optimization`, then continue."*

---

## Build & verify (no simulator here)

The local CoreSimulator runtime is out of date, so the app can't be run or
screenshotted in this environment. Type-check the whole app with:

```
xcodebuild -project followtrend.xcodeproj -scheme followtrend \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

`swiftc -parse <file>` is a fast syntax-only pre-check. `PortfolioImportParser`
is now **pure Foundation** (no network) — it compiles/runs standalone, which is
how import parsing is verified. Test target: `followtrendTests/` (has
`CorrelationServiceTests.swift`; parser has no tests yet — easiest high-value add).

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
- **Finnhub / Alpha Vantage are DEAD** — referenced in comments/labels only; no
  calls. `APIConfig.canFetchLiveStockData` is misleading.

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

## Open items / known gaps

1. **Old price alerts** keep their pre-fix `baseCurrency` until re-saved (no
   migration written; `PriceAlertStore` untouched).
2. **Watchlist→crypto convert** tags the new position's cost basis `USD` even
   though the EUR live price was used — *display* math is correct, *write* path
   mis-tags `nativeCurrency`.
3. **Secrets committed** in `Config/APIConfig.swift` (`proxySecret`, a real-looking
   `finnhubKey`). Security debt.
4. **Dead Finnhub / Alpha Vantage** code across ~7 files — cleanup.
5. **Parser unit tests** — `PortfolioImportParser` is pure & runnable; best ROI.
6. **PR not created** (no `gh` CLI / GitHub connector auth). Branch is pushed;
   open via `https://github.com/kirillyakopov/followtrend/pull/new/codex-broker-adjustments-bubble-optimization`.
7. **Beta** metric intentionally omitted from Risk Overview (needs a benchmark
   return series, e.g. SPY). Top-holding concentration took its slot.
8. Import future work: Files-app / share-sheet CSV, batch undo, screenshot OCR
   (Phase 2 Vision — plugs into the same review pipeline).

## Suggested next

Parser unit tests · secrets out + kill dead Finnhub · fix watchlist→crypto cost
tagging (#2) · then feature polish.

## Artifacts (design/product docs)

- Import exploration + implementation writeups were published as Claude artifacts
  (portfolio-import). Regenerate/list via the Artifact tool if the URLs are lost.
