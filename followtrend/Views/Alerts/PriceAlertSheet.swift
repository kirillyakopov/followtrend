//
//  PriceAlertSheet.swift
//  followtrend
//

import SwiftUI

struct PriceAlertSheet: View {
    let investment: Investment
    let livePrice: Double
    let existingAlert: PriceAlert?
    let onSave: (PriceAlert) -> Void

    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var currencyService = CurrencyService.shared

    @State private var kind: PriceAlertKind
    @State private var thresholdText: String
    @State private var isEnabled: Bool

    init(
        investment: Investment,
        livePrice: Double,
        existingAlert: PriceAlert?,
        onSave: @escaping (PriceAlert) -> Void
    ) {
        self.investment = investment
        self.livePrice = livePrice
        self.existingAlert = existingAlert
        self.onSave = onSave

        _kind = State(initialValue: existingAlert?.kind ?? .priceAbove)
        _thresholdText = State(initialValue: Self.initialThresholdText(
            investment: investment,
            livePrice: livePrice,
            existingAlert: existingAlert
        ))
        _isEnabled = State(initialValue: existingAlert?.isEnabled ?? true)
    }

    private var inputDisplayValue: Double {
        Double(thresholdText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool {
        !kind.requiresThreshold || inputDisplayValue > 0
    }

    private var selectedCurrency: AppCurrency { currencyService.selectedCurrency }
    // The alert threshold is compared against the LIVE quote, so the alert's
    // base currency is the asset's `priceCurrency` (EUR for crypto, USD for
    // stocks) — NOT the cost-basis `nativeCurrency`.
    private var assetBaseCurrency: AppCurrency {
        AppCurrency(rawValue: investment.priceCurrency.uppercased()) ?? .usd
    }

    private var storedBaseValue: Double {
        guard kind != .dailyChangeAbove else { return inputDisplayValue }
        return currencyService.convert(
            value: inputDisplayValue,
            from: selectedCurrency,
            to: assetBaseCurrency
        )
    }

    private var displayValue: Double {
        guard kind != .dailyChangeAbove else { return storedBaseValue }
        return currencyService.convert(
            value: storedBaseValue,
            from: assetBaseCurrency,
            to: selectedCurrency
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    OverlineLabel(lm.t("alerts.title"))
                        .padding(.leading, 4)

                    header

                    VStack(spacing: 14) {
                        Toggle(isOn: $isEnabled) {
                            Text(lm.t("alerts.enabled"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.mintAccent)

                        hairline

                        Picker(lm.t("alerts.condition"), selection: $kind) {
                            ForEach(PriceAlertKind.allCases) { alertKind in
                                Text(lm.t(alertKind.localizationKey)).tag(alertKind)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.textPrimary)

                        if kind.requiresThreshold {
                            hairline

                            HStack {
                                Text(kind == .dailyChangeAbove ? lm.t("alerts.thresholdPercent") : lm.t("alerts.thresholdPrice"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.labelSecondary)
                                Spacer()
                                TextField("0.00", text: $thresholdText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 16, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.mintAccent)
                                    .frame(maxWidth: 130)
                            }
                        }
                    }
                    .cardStyle(cornerRadius: 16)

                    Text(lm.t("alerts.pushReady"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    saveButton
                }
                .padding(20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t("add.abbrechen")) { dismiss() }
                        .foregroundStyle(Color.mintAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: investment.symbol, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(investment.symbol)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(CurrencyService.shared.format(value: livePrice, from: investment.priceCurrency))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.mintAccent)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.separatorHair)
            .frame(height: 0.5)
    }

    private var saveButton: some View {
        Button {
            guard canSave else {
                haptic(.rigid)
                return
            }

            logAlertConversion()

            let alert = PriceAlert(
                id: existingAlert?.id ?? UUID().uuidString,
                investmentID: investment.id,
                symbol: investment.symbol,
                kind: kind,
                baseCurrency: assetBaseCurrency.rawValue,
                targetPriceBase: storedBaseValue,
                displayCurrencyAtCreation: selectedCurrency.rawValue,
                originalInputValue: inputDisplayValue,
                isEnabled: isEnabled,
                createdAt: existingAlert?.createdAt ?? Date()
            )
            onSave(alert)
            haptic(.medium)
            dismiss()
        } label: {
            Text(lm.t("alerts.save"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.mintInk)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.mintAccent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .disabled(!canSave)
    }

    private static func initialThresholdText(
        investment: Investment,
        livePrice: Double,
        existingAlert: PriceAlert?
    ) -> String {
        let currencyService = CurrencyService.shared

        guard let existingAlert else {
            // Prefill from the live quote, which is denominated in priceCurrency.
            let base = AppCurrency(rawValue: investment.priceCurrency.uppercased()) ?? .usd
            let display = currencyService.convert(
                value: livePrice,
                from: base,
                to: currencyService.selectedCurrency
            )
            return String(format: "%.2f", display)
        }

        if existingAlert.kind == .dailyChangeAbove {
            return String(format: "%.2f", existingAlert.originalInputValue)
        }

        let base = AppCurrency(rawValue: existingAlert.baseCurrency.uppercased()) ?? .usd
        let display = currencyService.convert(
            value: existingAlert.targetPriceBase,
            from: base,
            to: currencyService.selectedCurrency
        )
        return String(format: "%.2f", display)
    }

    private func logAlertConversion() {
        let fxRate: Double
        if selectedCurrency == assetBaseCurrency {
            fxRate = 1
        } else if selectedCurrency == .eur && assetBaseCurrency == .usd {
            fxRate = currencyService.eurToUsdRate
        } else {
            fxRate = currencyService.usdToEurRate
        }

        print("""
        PriceAlert Debug [\(investment.symbol)]
        typed input: \(inputDisplayValue)
        selected currency: \(selectedCurrency.rawValue)
        asset base currency: \(assetBaseCurrency.rawValue)
        FX rate used: \(fxRate)
        stored base value: \(storedBaseValue)
        displayed converted value: \(displayValue)
        """)
    }
}
