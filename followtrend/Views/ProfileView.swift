//
//  ProfileView.swift
//  followtrend
//
//  User profile sheet with Sign In with Apple (Liquid Glass styled).
//

import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @ObservedObject var vm: PortfolioViewModel
    @StateObject private var auth = AppleAuthService.shared
    @StateObject private var cs = CurrencyService.shared
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var isLanguagePickerOpen = false
    @State private var isCurrencyPickerOpen = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // ── Avatar ─────────────────────────────────────────
                        avatarSection

                        // ── Auth section ───────────────────────────────────
                        authSection

                        // ── Language Selector ──────────────────────────────
                        languageSelector

                        // ── Currency Selector ──────────────────────────────
                        currencySelector

                        // ── Price Source Selector ──────────────────────────
                        priceSourceSelector

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle(lm.t("profile.profil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.t("common.fertig")) { dismiss() }
                        .foregroundStyle(Color.jade)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.jade.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.jade.opacity(0.5), Color.jade.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.jade.opacity(0.2), radius: 16)

                if case .signedIn(_, let name, _) = auth.authState, let initial = name?.first {
                    Text(String(initial))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.jade)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.jade)
                }
            }

            if case .signedIn(_, let name, let email) = auth.authState {
                if let name = name, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                if let email = email {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Text(lm.t("profile.nicht_angemeldet"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        VStack(spacing: 16) {
            if case .signedOut = auth.authState {
                // Sign In with Apple — Liquid Glass styled
                signInButton

                Text(lm.t("profile.daten_apple_verknuepft"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                // Signed in info card
                signedInCard

                // Sign out
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        auth.signOut()
                    }
                    haptic(.medium)
                } label: {
                    Text(lm.t("profile.abmelden"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.crimson.opacity(0.8))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.crimson.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.crimson.opacity(0.2), lineWidth: 0.7)
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sign In Button (Liquid Glass)

    private var signInButton: some View {
        Button {
            auth.signIn()
            haptic(.medium)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))
                Text(lm.t("profile.mit_apple_anmelden"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.7)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.08), .clear],
                                center: .init(x: 0.5, y: 0.0),
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.30), .white.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                }
            }
            .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: .capsule)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signed In Card

    private var signedInCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.jade)
            VStack(alignment: .leading, spacing: 3) {
                Text(lm.t("profile.apple_id_verknuepft"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(lm.t("profile.deine_daten_sicher"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.jade.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.jade.opacity(0.2), lineWidth: 0.7)
                )
        }
    }

    // MARK: - Language Selector
    
    private var languageSelector: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLanguagePickerOpen.toggle()
                }
                haptic()
            } label: {
                HStack {
                    Text(lm.t("profile.sprache"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(lm.currentLanguage.flag + " " + lm.currentLanguage.displayName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(isLanguagePickerOpen ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
            .buttonStyle(.plain)

            if isLanguagePickerOpen {
                VStack(spacing: 0) {
                    ForEach(lm.supportedLanguages) { lang in
                        let isSelected = lm.currentLanguage == lang
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                lm.setLanguage(lang)
                                isLanguagePickerOpen = false
                            }
                        } label: {
                            HStack {
                                Text(lang.flag)
                                    .font(.system(size: 18))
                                Text(lang.displayName)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.jade : Color.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.jade)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color.jade.opacity(0.06) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        
                        if lang != lm.supportedLanguages.last {
                            Divider().background(Color.white.opacity(0.06))
                                .padding(.leading, 42)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular.tint(Color.white.opacity(0.02)), in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
    }
    
    // MARK: - Currency Selector
    
    private var currencySelector: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCurrencyPickerOpen.toggle()
                }
                haptic()
            } label: {
                HStack {
                    Text("Currency")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(cs.selectedCurrency.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(isCurrencyPickerOpen ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
            .buttonStyle(.plain)

            if isCurrencyPickerOpen {
                VStack(spacing: 0) {
                    ForEach(AppCurrency.allCases) { currency in
                        let isSelected = cs.selectedCurrency == currency
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                cs.selectedCurrency = currency
                                isCurrencyPickerOpen = false
                            }
                            haptic(.medium)
                        } label: {
                            HStack {
                                Text(currency.symbol)
                                    .font(.system(size: 18))
                                Text(currency.rawValue)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.jade : Color.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.jade)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color.jade.opacity(0.06) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        
                        if currency != AppCurrency.allCases.last {
                            Divider().background(Color.white.opacity(0.06))
                                .padding(.leading, 42)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular.tint(Color.white.opacity(0.02)), in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
    }

    private var priceSourceSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price Source Mode")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .tracking(1.2)

            Picker("Price Source Mode", selection: Binding(
                get: { vm.priceSourceMode },
                set: { vm.setPriceSourceMode($0) }
            )) {
                ForEach(PriceSourceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Market Price keeps raw API values. Broker Adjusted applies saved broker alignment factors where available.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
