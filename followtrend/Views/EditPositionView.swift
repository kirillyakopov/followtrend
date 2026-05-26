//
//  EditPositionView.swift
//  followtrend
//
//  Edit/Redact Position sheet with Liquid Glass UI.
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

    private var isValid: Bool {
        let shares = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return shares > 0 && price > 0
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
            displayCurrency: CurrencyService.shared.selectedCurrency
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
                    VStack(spacing: 20) {
                        // ── Asset Header Preview ──────────────────────────
                        assetHeaderCard

                        // ── Position Info Card ────────────────────────────
                        sectionCard(title: lm.t("add.kauf_informationen")) {
                            numberRow(label: lm.t("add.stueckzahl"), placeholder: "0.00", text: $sharesText)
                            Divider().background(Color.borderHair)
                            priceRow
                            Divider().background(Color.borderHair)
                            DatePicker(lm.t("detail.kaufdatum"),
                                       selection: $buyDate,
                                       in: ...Date(),
                                       displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.jade)
                                .foregroundStyle(Color.textPrimary)
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
                            colors: [.clear, Color.black.opacity(0.85), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
            }
            .navigationTitle(lm.t("actions.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t("add.abbrechen")) { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Asset Header Card

    private var assetHeaderCard: some View {
        HStack(spacing: 14) {
            let sfSymbolName: String? = {
                switch investment.symbol.uppercased() {
                case "AAPL": return "apple.logo"
                case "BTC": return "bitcoinsign.circle.fill"
                default: return nil
                }
            }()
            
            let colors: [(Color, Color)] = [
                (.jade.opacity(0.12),               .jade),
                (Color(hex: "#5eead4").opacity(0.10), Color(hex: "#5eead4")),
                (Color(hex: "#2dd4bf").opacity(0.10), Color(hex: "#2dd4bf")),
                (Color(hex: "#0f766e").opacity(0.15), Color(hex: "#34d399")),
                (Color(hex: "#ff4a6a").opacity(0.12), Color(hex: "#ff4a6a")),
                (Color(hex: "#86a69a").opacity(0.12), Color(hex: "#9ccfbe")),
            ]
            let pair = colors[abs(investment.symbol.hashValue) % colors.count]

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(pair.0)
                    .frame(width: 32, height: 32)
                if let sfSymbolName {
                    Image(systemName: sfSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pair.1)
                } else {
                    Text(String(investment.symbol.prefix(2)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(pair.1)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(investment.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(investment.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.bgCard.opacity(0.74))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Price Row

    private var priceRow: some View {
        HStack {
            Text(lm.t("add.kaufpreis_eur").replacingOccurrences(of: " (€)", with: "").replacingOccurrences(of: " ($)", with: ""))
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("0.00", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.jade)
                .frame(maxWidth: 140)
        }
    }

    // MARK: - Save CTA Button

    private var saveButton: some View {
        let glowColor = isValid ? Color.jade : Color(white: 0.3)
        return LiquidGlassButton(glowColor: glowColor) {
            guard isValid else {
                shakeTrigger.toggle()
                haptic(.rigid)
                return
            }
            let shares = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 1.0
            let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 1.0
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            
            onSave(
                shares,
                price,
                fmt.string(from: buyDate),
                investment.notes,
                investment.tags,
                brokerAdjustmentDraft,
                clearsBrokerAdjustment
            )
            haptic(.medium)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(lm.t("detail.save_changes"))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(isValid ? Color.textPrimary : Color.textMuted)
        }
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.45)
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
                        .foregroundStyle(Color.jade)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Align with broker")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Optional: update the current broker price to recalculate the adjustment factor.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(showBrokerIntegration ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showBrokerIntegration {
                Divider().background(Color.borderHair)

                Picker("Broker Platform", selection: $brokerPlatform) {
                    ForEach(brokerPlatforms, id: \.self) { platform in
                        Text(platform).tag(platform)
                    }
                }
                .pickerStyle(.menu)
                .disabled(clearsBrokerAdjustment)

                Divider().background(Color.borderHair)

                numberRow(label: "Current Broker Price", placeholder: "0.00", text: $brokerPriceText)
                    .disabled(clearsBrokerAdjustment)
                    .opacity(clearsBrokerAdjustment ? 0.45 : 1)

                Divider().background(Color.borderHair)

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
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        Text(String(format: "%.4f", factor))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }
                } else if parsedBrokerPrice > 0 && currentApiPrice <= 0 && !clearsBrokerAdjustment {
                    Text("A current market API price is required before an adjustment factor can be saved.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
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
                    .tint(Color.crimson)
                }
            }
        }
    }

    private var brokerWarningView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#f59e0b"))
            Text("The broker price differs significantly from market data. Please verify currency, exchange, or symbol.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(hex: "#f59e0b").opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .tracking(1.2)
            content()
        }
        .cardStyle()
    }

    @ViewBuilder
    private func numberRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.jade)
                .frame(maxWidth: 140)
        }
    }
}
