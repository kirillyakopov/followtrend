//
//  EditPositionView.swift
//  followtrend
//
//  Edit Position sheet — form mode per the iOS 26 redesign handoff.
//

import SwiftUI

struct EditPositionView: View {
    let investment: Investment
    let currentApiPrice: Double
    let onSave: (Double, Double, String, String, String, BrokerAdjustmentDraft?, Bool) -> Void

    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var sharesText: String
    @State private var priceText: String
    @State private var buyDate: Date
    @State private var shakeTrigger = false
    @State private var showBrokerIntegration: Bool
    @State private var brokerPlatform: String
    @State private var brokerPriceText: String
    @State private var brokerCurrency: AppCurrency
    @State private var clearsBrokerAdjustment = false

    private let brokerPlatforms = ["Trade Republic", "Scalable", "IBKR", "Other", "Manual"]

    init(
        investment: Investment,
        currentApiPrice: Double = 0,
        onSave: @escaping (Double, Double, String, String, String, BrokerAdjustmentDraft?, Bool) -> Void
    ) {
        self.investment = investment
        self.currentApiPrice = currentApiPrice
        self.onSave = onSave

        // Initialize state fields
        _sharesText = State(initialValue: String(format: "%.4g", investment.shares))
        _priceText = State(initialValue: String(format: "%.2f", investment.buyPrice))

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let parsedDate = fmt.date(from: investment.buyDate) ?? Date()
        _buyDate = State(initialValue: parsedDate)
        _showBrokerIntegration = State(initialValue: investment.hasBrokerAdjustment)
        _brokerPlatform = State(initialValue: investment.brokerName ?? "Trade Republic")
        _brokerPriceText = State(initialValue: investment.currentBrokerPriceAtEntry.map { String(format: "%.2f", $0) } ?? "")
        _brokerCurrency = State(initialValue: AppCurrency(rawValue: investment.brokerCurrency ?? CurrencyService.shared.selectedCurrency.rawValue) ?? CurrencyService.shared.selectedCurrency)
    }

    private var parsedShares: Double {
        Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var parsedPrice: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var isValid: Bool {
        parsedShares > 0 && parsedPrice > 0
    }

    private var parsedBrokerPrice: Double {
        Double(brokerPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var brokerAdjustmentFactor: Double? {
        guard currentApiPrice > 0, parsedBrokerPrice > 0 else { return nil }
        return Investment.adjustmentFactor(
            apiPrice: currentApiPrice,
            apiCurrency: AppCurrency(rawValue: investment.nativeCurrency.uppercased()) ?? .usd,
            brokerPrice: parsedBrokerPrice,
            brokerCurrency: brokerCurrency,
            displayCurrency: CurrencyService.shared.selectedCurrency,
            currencyService: CurrencyService.shared
        )
    }

    private var shouldShowBrokerWarning: Bool {
        guard let factor = brokerAdjustmentFactor else { return false }
        return factor < 0.95 || factor > 1.05
    }

    private var brokerAdjustmentDraft: BrokerAdjustmentDraft? {
        guard showBrokerIntegration, currentApiPrice > 0, parsedBrokerPrice > 0, !clearsBrokerAdjustment else { return nil }
        return BrokerAdjustmentDraft(
            brokerName: brokerPlatform,
            currentBrokerPrice: parsedBrokerPrice,
            brokerCurrency: brokerCurrency,
            currentApiPrice: currentApiPrice
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // ── Overline title ────────────────────────────────
                        OverlineLabel(lm.t("detail.edit_position"))
                            .padding(.leading, 4)

                        // ── Asset Header Preview ──────────────────────────
                        assetHeaderCard

                        // ── Position Info Card ────────────────────────────
                        sectionCard(title: lm.t("add.kauf_informationen")) {
                            numberRow(label: lm.t("add.stueckzahl"), placeholder: "0.00", text: $sharesText)
                            hairline
                            numberRow(
                                label: lm.t("add.kaufpreis_eur").replacingOccurrences(of: " (€)", with: "").replacingOccurrences(of: " ($)", with: ""),
                                placeholder: "0.00",
                                text: $priceText
                            )
                            hairline
                            DatePicker(lm.t("detail.kaufdatum"),
                                       selection: $buyDate,
                                       in: ...Date(),
                                       displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.mintAccent)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.labelSecondary)

                            if isValid {
                                HStack {
                                    Spacer()
                                    Text("≈ \(CurrencyService.shared.format(value: parsedShares * parsedPrice, from: investment.nativeCurrency))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.labelTertiary)
                                }
                            }
                        }

                        brokerIntegrationSection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                    .padding(.top, 16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .background {
                        LinearGradient(
                            colors: [.clear, Color.bgDeep.opacity(0.85), Color.bgDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
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

    // MARK: - Asset Header Card

    private var assetHeaderCard: some View {
        HStack(spacing: 12) {
            MonogramTile(symbol: investment.symbol, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(investment.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(investment.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Save CTA Button (prominent mint glass, dark ink)

    private var saveButton: some View {
        Button {
            guard isValid else {
                shakeTrigger.toggle()
                haptic(.rigid)
                return
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"

            onSave(
                parsedShares,
                parsedPrice,
                fmt.string(from: buyDate),
                investment.notes,
                investment.tags,
                brokerAdjustmentDraft,
                clearsBrokerAdjustment
            )
            hapticSuccess()
            dismiss()
        } label: {
            Text(lm.t("detail.save_changes"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.mintInk)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.mintAccent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .disabled(!isValid)
        .modifier(ShakeModifier(trigger: shakeTrigger))
    }

    private var brokerIntegrationSection: some View {
        sectionCard(title: "Broker Integration") {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBrokerIntegration.toggle()
                }
                haptic()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mintAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Align with broker")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Optional: update the current broker price to recalculate the adjustment factor.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.labelTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.labelTertiary)
                        .rotationEffect(.degrees(showBrokerIntegration ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showBrokerIntegration {
                hairline

                Picker("Broker Platform", selection: $brokerPlatform) {
                    ForEach(brokerPlatforms, id: \.self) { platform in
                        Text(platform).tag(platform)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.textPrimary)
                .disabled(clearsBrokerAdjustment)

                hairline

                numberRow(label: "Current Broker Price", placeholder: "0.00", text: $brokerPriceText)
                    .disabled(clearsBrokerAdjustment)
                    .opacity(clearsBrokerAdjustment ? 0.45 : 1)

                hairline

                Picker("Broker Currency", selection: $brokerCurrency) {
                    ForEach(AppCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(clearsBrokerAdjustment)

                if let factor = brokerAdjustmentFactor, !clearsBrokerAdjustment {
                    HStack {
                        Text("Adjustment factor")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                        Spacer()
                        Text(String(format: "%.4f", factor))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.labelSecondary)
                    }
                } else if parsedBrokerPrice > 0 && currentApiPrice <= 0 && !clearsBrokerAdjustment {
                    Text("A current market API price is required before an adjustment factor can be saved.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.labelTertiary)
                }

                if shouldShowBrokerWarning && !clearsBrokerAdjustment {
                    brokerWarningView
                }

                if investment.hasBrokerAdjustment {
                    Toggle(isOn: $clearsBrokerAdjustment) {
                        Text("Remove broker adjustment")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.lossBase)
                }
            }
        }
    }

    private var brokerWarningView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.lossText)
            Text("The broker price differs significantly from market data. Please verify currency, exchange, or symbol.")
                .font(.system(size: 12))
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.lossBase.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private var hairline: some View {
        Rectangle()
            .fill(Color.separatorHair)
            .frame(height: 0.5)
    }

    @ViewBuilder
    private func sectionCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(title)
            content()
        }
        .cardStyle(cornerRadius: 16)
    }

    @ViewBuilder
    private func numberRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.mintAccent)
                .frame(maxWidth: 140)
        }
    }
}
