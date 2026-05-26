# FollowTrend Investor Coach Roadmap

## Product Goal

Evolve FollowTrend from a portfolio tracker into an investor coaching app that helps self-directed investors understand risk, act on portfolio changes, and build healthier long-term habits.

The roadmap builds on the current app foundation:

- SwiftData portfolio persistence through `Investment` and `InvestmentModel`.
- Stock and crypto pricing through `MarketDataService`, `StockMarketService`, and `CryptoDataService`.
- Existing watchlist, widget, currency, and localization infrastructure.
- Existing analytics for allocation, volatility, correlation, rebalancing suggestions, and bubble visualization.
- Existing alert configuration through `PriceAlertStore` and `PriceAlertSheet`.

## Target User

The primary user is a self-directed retail investor who tracks stocks and crypto, wants simple explanations of risk, and prefers actionable guidance over raw analytics.

The product should avoid investment advice that sounds like guaranteed outcomes. Coaching language should explain observations, risk signals, and optional actions.

## Milestone Order

1. **M1: Alerts That Actually Notify**
   - Convert saved alert rules into local notifications.
   - Add deterministic alert evaluation and trigger history.
   - This creates the app's first active coaching loop.

2. **M2: Portfolio Health Coach**
   - Convert existing analytics into a portfolio health score and coaching cards.
   - Explain risk drivers in plain language.
   - This becomes the main investor coach surface.

3. **M3: Goals And Rebalancing**
   - Let users define target allocations.
   - Compare actual portfolio state against those targets.
   - Make rebalancing suggestions goal-aware.

4. **M4: Reports And Sharing**
   - Generate monthly portfolio summaries and shareable snapshots.
   - Package performance, risk, alerts, and coaching into exportable artifacts.
   - Extend widgets with a coaching summary.

## Cross-Milestone Public Interfaces

Introduce these types as stable internal interfaces:

- `AlertEvaluationResult`: describes whether an alert fired, why, current value, threshold value, and duplicate-prevention metadata.
- `PriceAlertEvaluator`: pure evaluation component for deterministic alert checks.
- `PortfolioHealthScore`: aggregate score, grade, contributing factors, and timestamp.
- `PortfolioInsight`: user-facing coaching insight with title, body, severity, related symbols, and optional action.
- `PortfolioInsightSeverity`: ordered severity enum for sorting insight cards.
- `AllocationGoal`: SwiftData-persisted target allocation by asset category or symbol.
- `PortfolioReportSnapshot`: immutable report payload for monthly summaries and sharing.

Compatibility requirements:

- Keep existing `Investment`, `PriceAlert`, and analytics behavior compatible.
- Only add persisted fields with defaults.
- Keep all new user-facing copy localized in `en`, `de`, `fr`, `es`, `uk`, and `ru`.

## Dependencies And Sequencing

- M1 should land before M4 because reports need triggered-alert history.
- M2 should land before M3 because health insights provide the explanation layer for goal deviations.
- M3 should land before M4 because reports should include progress toward allocation goals.
- Localization work must be included in each milestone, not delayed to the end.

## Release Criteria

Each milestone is release-ready when:

- All milestone issues are complete.
- Unit tests cover deterministic calculations and edge cases.
- Main user flows work in a simulator.
- New strings exist in all supported locale JSON files.
- Empty, loading, error, and insufficient-data states are represented in UI.
- The feature avoids prescriptive financial advice and uses coaching language.

## Milestone Artifacts

- [M1: Alerts That Actually Notify](m1-alerts-and-notifications.md)
- [M2: Portfolio Health Coach](m2-portfolio-health-coach.md)
- [M3: Goals And Rebalancing](m3-goals-and-rebalancing.md)
- [M4: Reports And Sharing](m4-reports-and-sharing.md)
