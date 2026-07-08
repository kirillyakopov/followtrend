//
//  ConvertWatchlistPositionView.swift
//  followtrend
//

import SwiftUI

struct ConvertWatchlistPositionView: View {
    let investment: Investment
    let livePrice: Double
    let onConfirm: (Double, Double, String) -> Void

    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var sharesText = ""
    @State private var priceText: String
    @State private var buyDate = Date()
    @State private var shakeTrigger = false

    init(investment: Investment, livePrice: Double, onConfirm: @escaping (Double, Double, String) -> Void) {
        self.investment = investment
        self.livePrice = livePrice
        self.onConfirm = onConfirm
        _priceText = State(initialValue: livePrice > 0 ? String(format: "%.2f", livePrice) : "")
    }

    private var isValid: Bool {
        parsedShares > 0 && parsedPrice > 0
    }

    private var parsedShares: Double {
        Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var parsedPrice: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        OverlineLabel(lm.t("detail.convert_to_position"))
                            .padding(.leading, 4)

                        assetHeaderCard

                        sectionCard(title: lm.t("add.kauf_informationen")) {
                            numberRow(label: lm.t("add.stueckzahl"), placeholder: "0.00", text: $sharesText)
                            hairline
                            numberRow(label: lm.t("detail.kaufpreis"), placeholder: "0.00", text: $priceText)
                            hairline
                            DatePicker(
                                lm.t("detail.kaufdatum"),
                                selection: $buyDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
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
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .safeAreaInset(edge: .bottom) {
                convertButton
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

    private var convertButton: some View {
        Button {
            guard isValid else {
                shakeTrigger.toggle()
                haptic(.rigid)
                return
            }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            onConfirm(parsedShares, parsedPrice, fmt.string(from: buyDate))
            hapticSuccess()
            dismiss()
        } label: {
            Text(lm.t("detail.convert_to_position"))
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

    private var hairline: some View {
        Rectangle()
            .fill(Color.separatorHair)
            .frame(height: 0.5)
    }

    private func sectionCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(title)
            content()
        }
        .cardStyle(cornerRadius: 16)
    }

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
