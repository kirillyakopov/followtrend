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
                RadialGradient(
                    colors: [Color.jade.opacity(0.18), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        assetHeaderCard

                        sectionCard(title: lm.t("add.kauf_informationen")) {
                            numberRow(label: lm.t("add.stueckzahl"), placeholder: "0.00", text: $sharesText)
                            Divider().background(Color.borderHair)
                            numberRow(label: lm.t("detail.kaufpreis"), placeholder: "0.00", text: $priceText)
                            Divider().background(Color.borderHair)
                            DatePicker(
                                lm.t("detail.kaufdatum"),
                                selection: $buyDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .tint(.jade)
                            .foregroundStyle(Color.textPrimary)
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
                            colors: [.clear, Color.black.opacity(0.85), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
            }
            .navigationTitle(lm.t("actions.convert"))
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

    private var assetHeaderCard: some View {
        HStack(spacing: 14) {
            let sfSymbolName: String? = {
                switch investment.symbol.uppercased() {
                case "AAPL": return "apple.logo"
                case "BTC": return "bitcoinsign.circle.fill"
                default: return nil
                }
            }()
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#6366f1").opacity(0.16))
                    .frame(width: 32, height: 32)
                if let sfSymbolName {
                    Image(systemName: sfSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#818cf8"))
                } else {
                    Text(String(investment.symbol.prefix(2)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#818cf8"))
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

    private var convertButton: some View {
        LiquidGlassButton(glowColor: isValid ? Color.jade : Color(white: 0.3)) {
            guard isValid else {
                shakeTrigger.toggle()
                haptic(.rigid)
                return
            }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            onConfirm(parsedShares, parsedPrice, fmt.string(from: buyDate))
            haptic(.medium)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(lm.t("actions.convert"))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(isValid ? Color.textPrimary : Color.textMuted)
        }
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.45)
        .modifier(ShakeModifier(trigger: shakeTrigger))
    }

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
