//
//  ProfileView.swift
//  followtrend
//
//  User profile tab — iOS 26 inset-grouped settings style.
//  Dark monochrome surfaces, single mint accent, opaque cards.
//

import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @ObservedObject var vm: PortfolioViewModel
    @StateObject private var auth = AppleAuthService.shared
    @StateObject private var cs = CurrencyService.shared
    @EnvironmentObject private var lm: AppLanguageManager

    @State private var isLanguagePickerOpen = false
    @State private var isCurrencyPickerOpen = false
    @State private var isPriceSourcePickerOpen = false

    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerView
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        profileCard

                        generalSection

                        if case .signedIn = auth.authState {
                            accountSection
                        }

                        aboutSection

                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            OverlineLabel(lm.t("portfolio.account_title"))
            Text(lm.t("portfolio.your_profile_title"))
                .font(AppTypography.screenTitle)
                .tracking(-0.7)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.top, 16)
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.mintAccent.opacity(0.12))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.mintAccent.opacity(0.45), Color.mintAccent.opacity(0.08)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )

                    if case .signedIn(_, let name, _) = auth.authState, let initial = name?.first {
                        Text(String(initial))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.mintAccent)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.mintAccent)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if case .signedIn(_, let name, let email) = auth.authState {
                        if let name = name, !name.isEmpty {
                            Text(name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                        } else {
                            Text("Apple User")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        if let email = email {
                            Text(email)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.labelSecondary)
                        }
                    } else {
                        Text(lm.t("profile.nicht_angemeldet"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                Spacer()

                // PRO Badge
                Text("PRO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.mintInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mintAccent)
                    .clipShape(Capsule())
            }

            if case .signedOut = auth.authState {
                signInButton
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.separatorHair, lineWidth: 0.5)
        )
    }

    private var signInButton: some View {
        Button {
            auth.signIn()
            haptic(.medium)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                Text(lm.t("profile.mit_apple_anmelden"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.bgDeep)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("profile.general"))
                .padding(.leading, 16)

            VStack(spacing: 0) {
                currencySelector
                hairlineSeparator
                languageSelector
                hairlineSeparator
                priceSourceSelector
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.separatorHair, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("portfolio.account_title"))
                .padding(.leading, 16)

            VStack(spacing: 0) {
                signOutRow
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.separatorHair, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("profile.about"))
                .padding(.leading, 16)

            HStack {
                Text(lm.t("profile.version"))
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(appVersionString)
                    .font(.system(size: 14.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.separatorHair, lineWidth: 0.5)
            )
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var hairlineSeparator: some View {
        Rectangle()
            .fill(Color.separatorHair)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - Row Label

    private func rowLabel(title: String, detail: String, isOpen: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Currency Row

    private var currencySelector: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCurrencyPickerOpen.toggle()
                }
                haptic()
            } label: {
                rowLabel(
                    title: lm.t("profile.currency"),
                    detail: cs.selectedCurrency.rawValue,
                    isOpen: isCurrencyPickerOpen
                )
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
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.labelSecondary)
                                    .frame(width: 28, alignment: .leading)
                                Text(currency.rawValue)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.mintAccent : Color.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.mintAccent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(isSelected ? Color.mintAccent.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surfaceWatch)
            }
        }
    }

    // MARK: - Language Row

    private var languageSelector: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLanguagePickerOpen.toggle()
                }
                haptic()
            } label: {
                rowLabel(
                    title: lm.t("profile.sprache"),
                    detail: lm.currentLanguage.flag + " " + lm.currentLanguage.displayName,
                    isOpen: isLanguagePickerOpen
                )
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
                            haptic(.medium)
                        } label: {
                            HStack {
                                Text(lang.flag)
                                    .font(.system(size: 15))
                                    .frame(width: 28, alignment: .leading)
                                Text(lang.displayName)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.mintAccent : Color.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.mintAccent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(isSelected ? Color.mintAccent.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surfaceWatch)
            }
        }
    }

    // MARK: - Price Source Row

    private var priceSourceSelector: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isPriceSourcePickerOpen.toggle()
                }
                haptic()
            } label: {
                rowLabel(
                    title: lm.t("profile.price_source"),
                    detail: vm.priceSourceMode.title,
                    isOpen: isPriceSourcePickerOpen
                )
            }
            .buttonStyle(.plain)

            if isPriceSourcePickerOpen {
                VStack(spacing: 0) {
                    ForEach(PriceSourceMode.allCases) { mode in
                        let isSelected = vm.priceSourceMode == mode
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                vm.setPriceSourceMode(mode)
                                isPriceSourcePickerOpen = false
                            }
                            haptic(.medium)
                        } label: {
                            HStack {
                                Text(mode.title)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.mintAccent : Color.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.mintAccent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(isSelected ? Color.mintAccent.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surfaceWatch)
            }
        }
    }

    // MARK: - Sign Out Row

    private var signOutRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                auth.signOut()
            }
            haptic(.medium)
        } label: {
            HStack {
                Text(lm.t("profile.abmelden"))
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Color.lossText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
