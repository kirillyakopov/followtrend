# M3: Goals And Rebalancing

## User Value

Users can define what a healthy portfolio means for them and see how their current allocation compares to those targets. Rebalancing suggestions become more personal and easier to act on.

## Feature List

- Add target allocation goals by asset category or symbol.
- Persist goals locally with SwiftData.
- Show actual vs target allocation.
- Add deviation calculations and goal-aware rebalancing suggestions.
- Add a goal editor with validation.
- Include goal progress in coaching cards.

## Implementation Notes

- Introduce `AllocationGoal` as a SwiftData-persisted model.
- Support two target types: asset category and symbol.
- Store target percentages as whole-portfolio percentages.
- Validate that active goals do not exceed 100 percent in aggregate within the same goal set.
- Reuse `AssetCategory` and current allocation calculations where possible.
- Extend, rather than replace, existing `RebalancingSuggestion` behavior.
- Include migration-safe defaults so existing users launch without goals.

## Acceptance Criteria

- A user can create, edit, disable, and delete allocation goals.
- Goals persist across app launches.
- Actual allocation can be compared against target allocation.
- Deviations generate goal-aware insights.
- Existing rebalancing suggestions still appear when no goals are configured.
- Invalid target totals are blocked with clear UI feedback.
- Empty portfolios and watchlist-only portfolios do not show misleading goal progress.
- New strings exist for all supported locales.

## Test Scenarios

- No configured goals keeps current rebalancing behavior.
- Category goal deviation is calculated correctly.
- Symbol goal deviation is calculated correctly.
- Disabled goals are ignored.
- Total active target percentage over 100 percent is rejected.
- Empty portfolio produces no misleading deviation.
- Goals persist and reload through SwiftData.
- Goal-aware suggestions are sorted with existing severity rules.

## Issue Breakdown

### Issue: Add Allocation Goal Persistence

Introduce SwiftData storage for allocation goals.

Acceptance:

- `AllocationGoal` supports category and symbol targets.
- Goals include id, target type, target identifier, percentage, enabled state, created date, and updated date.
- Existing users launch with an empty goal set.
- Persistence tests or manual verification cover save, update, disable, and delete.

### Issue: Add Goal Calculation Service

Create deterministic actual-vs-target calculations.

Acceptance:

- Service accepts current allocation, investment values, and active goals.
- Service returns deviation amount, deviation percentage, and status per goal.
- Service handles empty portfolios.
- Unit tests cover category, symbol, disabled, and invalid goal cases.

### Issue: Add Target Allocation Editor

Create UI for managing goals.

Acceptance:

- Users can add category and symbol goals.
- Users can edit target percentage.
- Users can disable or delete goals.
- UI prevents totals above 100 percent in a goal set.
- UI follows existing dark design system.

### Issue: Make Rebalancing Goal-Aware

Extend rebalancing suggestions with goal deviation signals.

Acceptance:

- Suggestions mention target and actual allocation when a goal is meaningfully off track.
- Existing concentration, technology, asset class, and correlation suggestions remain available.
- Goal-aware suggestions use existing severity ordering.
- Copy remains educational and non-prescriptive.

### Issue: Add Goal Progress To Coach Cards

Surface goal progress in the health coach.

Acceptance:

- Top goal deviations can appear as `PortfolioInsight` cards.
- Goal progress does not crowd out critical risk warnings.
- Empty goal state invites setup without blocking other app use.

### Issue: Localize Goal Copy

Add all goal and rebalancing strings.

Acceptance:

- Keys exist in `en`, `de`, `fr`, `es`, `uk`, and `ru`.
- Validation copy is clear and short.
- Missing-key fallback is not visible in normal flows.
