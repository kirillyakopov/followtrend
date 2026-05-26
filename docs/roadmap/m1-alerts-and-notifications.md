# M1: Alerts That Actually Notify

## User Value

Users can create alert rules and trust FollowTrend to notify them when important portfolio or watchlist conditions happen. This turns the app from a passive tracker into an active market companion.

## Feature List

- Request local notification permission from the user.
- Evaluate enabled alerts during live price refresh.
- Trigger local notifications for matching alert conditions.
- Store triggered-alert history for reporting and duplicate prevention.
- Let users manage enabled and disabled alerts from the existing alert UI.
- Localize alert states, notification copy, and history labels.

## Implementation Notes

- Build on `PriceAlertStore` and `PriceAlertSheet`.
- Add a pure `PriceAlertEvaluator` so alert checks are unit-testable without notification APIs.
- Add `AlertEvaluationResult` with enough detail for UI, notification body text, and report history.
- Evaluate alerts after prices update in `PortfolioViewModel.refreshLivePrices()`.
- Use iOS local notifications through `UNUserNotificationCenter`; no backend is required.
- Store triggered history locally, either in `PriceAlertStore` or a closely related alert history store.
- Prevent duplicate notifications for the same alert until the condition resets or a cool-down window passes.

## Acceptance Criteria

- A user can grant or deny notification permission without breaking alert creation.
- Enabled price-above, price-below, and daily-change alerts are evaluated during price refresh.
- Disabled alerts never trigger.
- Triggered alerts create local notification requests when permission is granted.
- Triggered alerts are recorded in local history.
- Duplicate notifications are suppressed while the alert remains continuously true.
- Existing saved alerts continue to decode correctly.
- Alert UI clearly shows enabled state, current rule, and last triggered state when available.
- New strings exist for all supported locales.

## Test Scenarios

- Price above threshold fires only when current price is greater than or equal to threshold.
- Price below threshold fires only when current price is less than or equal to threshold.
- Daily change threshold fires based on percentage movement.
- Disabled alert returns a non-triggered result.
- Missing price data returns a non-triggered result with an explainable reason.
- Repeated evaluation of an already-triggered condition does not create duplicate notifications.
- Alert fires again after the condition resets and crosses the threshold later.
- Notification permission denied still records evaluation state without scheduling a notification.

## Issue Breakdown

### Issue: Add Deterministic Alert Evaluation

Create `AlertEvaluationResult` and `PriceAlertEvaluator`.

Acceptance:

- Evaluator has no SwiftUI or notification dependencies.
- Evaluator supports price above, price below, and daily change above.
- Unsupported alert kinds return a clear not-triggered result until their required market data is available.
- Unit tests cover enabled, disabled, threshold, and duplicate-prevention behavior.

### Issue: Add Triggered Alert History

Persist alert trigger records locally.

Acceptance:

- Trigger history includes alert id, investment id, symbol, kind, trigger value, threshold value, and trigger date.
- History can be queried by investment id and by date range.
- Deleting an investment removes associated alert history when appropriate.
- Existing alerts remain compatible.

### Issue: Schedule Local Notifications

Request permission and schedule notifications for triggered alerts.

Acceptance:

- Permission flow is surfaced before the first notification is needed.
- Notifications include symbol, alert condition, and current value.
- Notification scheduling is skipped gracefully when permission is denied.
- Notification logic is isolated from pure alert evaluation.

### Issue: Integrate Alert Checks With Price Refresh

Run alert evaluation after live prices update.

Acceptance:

- Alert evaluation runs once per completed refresh cycle.
- Evaluation uses current price, previous price or daily change when available, and selected alert threshold.
- Failures do not block portfolio recalculation.
- Debug logging is concise and removable.

### Issue: Improve Alert Management UI

Update alert screens to show rule state and last trigger.

Acceptance:

- Users can enable and disable an alert.
- Existing threshold entry still supports selected currency conversion.
- Last triggered state appears when history exists.
- Empty and permission-denied states are understandable.

### Issue: Add Alert Localization

Add all alert notification and history strings.

Acceptance:

- Keys exist in `en`, `de`, `fr`, `es`, `uk`, and `ru`.
- Copy avoids guaranteed financial outcomes.
- Missing-key fallback is not visible in normal flows.
