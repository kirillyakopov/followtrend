# M2: Portfolio Health Coach

## User Value

Users can understand the health of their portfolio at a glance and see plain-language coaching cards that explain the biggest risks, changes, and possible next steps.

## Feature List

- Add a portfolio health score derived from existing analytics.
- Add insight cards for concentration, volatility, correlation, allocation imbalance, cash exposure, and insufficient data.
- Explain what changed, why it matters, and what the user may consider doing.
- Add a dashboard surface for the score and top insights.
- Localize all coaching copy.

## Implementation Notes

- Reuse `assetAllocation`, `rebalancingSuggestions`, `volatilityBySymbol`, `correlationMatrix`, and `portfolioCorrelation` from `PortfolioViewModel`.
- Add `PortfolioHealthScore`, `PortfolioInsight`, and `PortfolioInsightSeverity`.
- Keep scoring deterministic and testable in a service or calculator independent from SwiftUI.
- Include stablecoins in allocation reporting, but exclude them from volatility and correlation risk scoring where the existing app already excludes them.
- Treat empty portfolios and insufficient market data as explicit states rather than poor health.
- Make insights educational and non-prescriptive.

## Acceptance Criteria

- Portfolio health score appears on the main portfolio screen when there is enough data.
- Empty portfolios show a neutral onboarding state.
- Insufficient market data shows a clear explanation instead of a misleading score.
- Top coaching cards are sorted by severity and relevance.
- Each insight includes a concise title, explanation, and optional action label.
- Score recalculates after price refresh, position edits, deletion, and currency changes.
- Existing rebalancing suggestions remain available.
- New strings exist for all supported locales.

## Test Scenarios

- Empty portfolio returns no score and an onboarding insight.
- Single concentrated position produces a concentration insight.
- Highly correlated assets produce a correlation insight.
- High volatility produces a volatility insight.
- Heavy technology exposure produces a sector concentration insight using current classifier behavior.
- Stablecoin-heavy portfolios do not produce misleading volatility warnings.
- Cash balance affects allocation but does not break health scoring.
- Score output is deterministic for fixed inputs.

## Issue Breakdown

### Issue: Add Health Score Models

Introduce `PortfolioHealthScore`, `PortfolioInsight`, and `PortfolioInsightSeverity`.

Acceptance:

- Models are Codable where useful for future report snapshots.
- Severity is sortable.
- Insights can reference symbols, categories, and optional action identifiers.
- Models are independent from SwiftUI.

### Issue: Add Portfolio Health Calculator

Create a deterministic calculator for score and insight generation.

Acceptance:

- Calculator accepts current investments, allocation slices, correlations, volatility, cash balance, and portfolio value.
- Calculator returns explicit empty and insufficient-data states.
- Score contributors are inspectable for debugging and reports.
- Unit tests cover concentration, volatility, correlation, stablecoins, cash, and empty data.

### Issue: Add Health Coach Dashboard Card

Expose health score and top insights in the portfolio dashboard.

Acceptance:

- Card uses existing design system styling.
- Card handles loading, empty, insufficient-data, and score states.
- Top insights are visible without overwhelming the existing dashboard.
- Tapping an insight can reveal additional detail if needed.

### Issue: Add Coaching Insight Cards

Create reusable insight cards.

Acceptance:

- Cards show severity, title, explanation, and optional action.
- Cards avoid financial-advice language.
- Cards work with dynamic type and compact screens.
- Cards are reusable by reports in M4.

### Issue: Localize Coach Copy

Add all health score and insight strings.

Acceptance:

- Keys exist in `en`, `de`, `fr`, `es`, `uk`, and `ru`.
- Tone is educational and cautious.
- Missing-key fallback is not visible in normal flows.

### Issue: Add Health Analytics Tests

Add unit tests for health scoring.

Acceptance:

- Tests use fixed input data and do not call network services.
- Tests cover score bands and insight ordering.
- Tests cover insufficient-data behavior.
