# M4: Reports And Sharing

## User Value

Users can review their progress over time and share a clean, understandable portfolio snapshot. Reports make FollowTrend feel useful beyond the moment of checking prices.

## Feature List

- Generate monthly portfolio summaries locally.
- Create immutable report snapshots from portfolio, analytics, goals, alerts, and coach insights.
- Export report snapshots as shareable images or PDFs.
- Add shareable insight cards.
- Add widget summary upgrades using coach and report data.
- Include triggered-alert history in monthly summaries.

## Implementation Notes

- Introduce `PortfolioReportSnapshot` as the report payload.
- Generate reports locally from existing portfolio state and stored alert history.
- Reuse `PortfolioInsight` cards from M2 for shareable insights.
- Include goal progress from M3 when goals exist.
- Use iOS sharing APIs for export.
- Keep report generation deterministic and independent from the export UI.
- Prefer simple local snapshots before adding cloud sync or backend history.

## Acceptance Criteria

- A user can generate a current-month portfolio summary.
- Report includes portfolio value, gain/loss, allocation, top movers, triggered alerts, health score, top insights, and goal progress when available.
- Report generation works offline using locally available data.
- User can share a report snapshot through the system share sheet.
- User can share an individual insight card.
- Widget can show a compact coach summary or report highlight.
- Empty and insufficient-data states are handled gracefully.
- New strings exist for all supported locales.

## Test Scenarios

- Report snapshot generated from fixed portfolio data is deterministic.
- Empty portfolio generates an onboarding-style report state.
- Watchlist-only portfolio does not show misleading performance.
- Triggered-alert history appears in the correct month.
- Goal progress appears only when goals exist.
- Sharing a report does not mutate portfolio data.
- Widget summary handles missing health score.
- Export flow handles cancellation gracefully.

## Issue Breakdown

### Issue: Add Report Snapshot Model

Introduce `PortfolioReportSnapshot`.

Acceptance:

- Snapshot includes period, generated date, portfolio totals, allocation, top movers, triggered alerts, health score, insights, and goal progress.
- Snapshot is Codable where practical.
- Snapshot has no SwiftUI dependency.
- Snapshot can be generated from fixed test data.

### Issue: Add Report Generation Service

Create local report generation.

Acceptance:

- Service builds a snapshot from current portfolio state and local stores.
- Service does not call network APIs directly.
- Service handles empty, watchlist-only, and insufficient-data states.
- Unit tests cover deterministic snapshot generation.

### Issue: Add Monthly Summary UI

Create a report screen or sheet.

Acceptance:

- User can open the current monthly summary.
- Summary shows performance, allocation, top movers, alerts, health, and insights.
- Empty states are polished and localized.
- UI follows existing dark design system.

### Issue: Add Share Export

Allow reports and insights to be shared.

Acceptance:

- User can share a report snapshot through the system share sheet.
- User can share a single insight card.
- Export works as image or PDF based on implementation feasibility.
- Cancelled share actions do not show false success.

### Issue: Upgrade Widget Summary

Add a compact coach or report highlight to the widget.

Acceptance:

- Widget can display health score or top insight when available.
- Widget falls back to existing portfolio/watchlist data when unavailable.
- App Group data remains compact and compatible.
- Widget timeline reload behavior remains reasonable.

### Issue: Add Report Localization And Tests

Localize report copy and add tests.

Acceptance:

- Keys exist in `en`, `de`, `fr`, `es`, `uk`, and `ru`.
- Report tests cover snapshot generation and empty states.
- UI or snapshot tests are added where practical.
