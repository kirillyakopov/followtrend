//
//  PortfolioImportView.swift
//  followtrend
//
//  Paste-based portfolio import (Phase 1 of the import pipeline):
//  designed format explanation → currency selector → paste area → live
//  parse preview with async ticker validation, merge/watchlist notes, and
//  tap-to-edit rows that sync back into the text → one-tap import through
//  the existing addInvestment path (which already merges same-symbol lots).
//

import SwiftUI

struct PortfolioImportView: View {
    @ObservedObject var vm: PortfolioViewModel
    var onImported: (() -> Void)? = nil

    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cs = CurrencyService.shared

    @State private var text: String = ""
    @State private var drafts: [ImportDraft] = []
    @State private var issues: [ImportIssue] = []
    /// Per-symbol (uppercased) resolution verdict; absence == still checking.
    @State private var resolutions: [String: ImportResolution] = [:]
    /// User's disambiguation picks, keyed by uppercased symbol. Survives a full
    /// re-parse (which drops coinId) and marks the row resolved.
    @State private var userChoices: [String: ImportCandidate] = [:]
    @State private var defaultCurrency: AppCurrency = .eur
    @State private var editingDraft: ImportDraft? = nil

    @State private var suppressReparse = false
    @State private var validationTask: Task<Void, Never>? = nil
    @FocusState private var editorFocused: Bool

    /// Search-field fill per spec: rgba(118,118,128,0.16)
    private let fieldFill = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.16)

    private var ownedSymbols: Set<String> {
        Set(vm.investments.filter { !$0.isWatchlist }.map { $0.symbol.uppercased() })
    }
    private var importableDrafts: [ImportDraft] {
        drafts.filter { let s = rowState(for: $0); return s != .notFound && s != .ambiguous }
    }
    private var notFoundCount: Int {
        drafts.filter { rowState(for: $0) == .notFound }.count
    }
    private var needsChoiceCount: Int {
        drafts.filter { rowState(for: $0) == .ambiguous }.count
    }

    /// 1-based number of the line still being typed (editor focused, no trailing
    /// newline). A half-finished line shouldn't be scolded as an error.
    private var inProgressLine: Int? {
        guard editorFocused, !text.isEmpty, !text.hasSuffix("\n") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let idx = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        return idx + 1
    }
    /// The in-progress line's problem, shown as a calm hint instead of a red alarm.
    private var pendingIssue: ImportIssue? {
        guard let line = inProgressLine else { return nil }
        return issues.first { $0.line == line }
    }
    /// Problems on lines the user has finished — these get the red card.
    private var settledIssues: [ImportIssue] {
        guard let line = inProgressLine else { return issues }
        return issues.filter { $0.line != line }
    }

    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                header.padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        formatSection
                        currencySection
                        pasteSection
                        if !drafts.isEmpty || !issues.isEmpty { previewSection }
                        Spacer(minLength: 110)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                }
            }

            VStack {
                Spacer()
                if !importableDrafts.isEmpty {
                    importButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: drafts)
        .onAppear { defaultCurrency = cs.selectedCurrency }
        .onChange(of: text) { _, newValue in
            if suppressReparse {
                suppressReparse = false
            } else {
                let r = PortfolioImportParser.parse(newValue)
                drafts = applyUserChoices(to: r.drafts)
                issues = r.issues
            }
            scheduleValidation()
        }
        .sheet(item: $editingDraft) { d in
            ImportRowEditView(
                draft: d,
                defaultCurrency: defaultCurrency,
                candidates: candidates(for: d),
                chosen: userChoices[d.symbol.uppercased()],
                onSave: applyEdit,
                onDelete: deleteDraft
            )
            .environmentObject(lm)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(lm.t("import.title"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 70)

            HStack {
                Button {
                    haptic(.light)
                    dismiss()
                } label: {
                    Text(lm.t("add.abbrechen"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mintAccent)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, AppLayout.contentHorizontalPadding)
        .padding(.top, 14)
    }

    // MARK: - Format explanation

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(lm.t("import.format_title"))

            VStack(alignment: .leading, spacing: 0) {
                Text(lm.t("import.format_intro"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.bottom, 14)

                fieldRow(icon: "textformat",    key: "import.field_symbol",   descKey: "import.field_symbol_desc",   required: true)
                fieldRow(icon: "number",        key: "import.field_shares",   descKey: "import.field_shares_desc",   required: true)
                fieldRow(icon: "tag",           key: "import.field_price",    descKey: "import.field_price_desc",    required: true)
                fieldRow(icon: "eurosign.circle", key: "import.field_currency", descKey: "import.field_currency_desc", required: false)
                fieldRow(icon: "calendar",      key: "import.field_date",     descKey: "import.field_date_desc",     required: false)
                fieldRow(icon: "circle.dashed", key: "import.field_watchlist", descKey: "import.field_watchlist_desc", required: false, last: true)
            }
            .padding(16)
            .background(surfaceCard(radius: 20))

            VStack(alignment: .leading, spacing: 8) {
                OverlineLabel(lm.t("import.example_title"), color: .labelQuaternary)
                Text("""
                AAPL 12 @ 175.30 2024-01-15
                BTC 0.45 @ 43200 EUR
                NVDA 5 @ $91.40 "NVIDIA Corp"
                TSLA
                """)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.gainText)
                .lineSpacing(4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceCard(radius: 16, fill: Color.surfaceWatch, border: 0.06))

            Text(lm.t("import.csv_hint"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
        }
    }

    @ViewBuilder
    private func fieldRow(icon: String, key: String, descKey: String, required: Bool, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mintAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.mintAccent.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lm.t(key))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(lm.t(required ? "import.required" : "import.optional"))
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(required ? Color.mintAccent : Color.labelTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(required ? Color.mintAccent.opacity(0.13) : Color.white.opacity(0.05)))
                }
                Text(lm.t(descKey))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, last ? 0 : 13)
    }

    // MARK: - Currency selector

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(lm.t("import.currency_title"))
            Picker("", selection: $defaultCurrency) {
                ForEach(AppCurrency.allCases) { c in
                    Text("\(c.symbol)  \(c.rawValue)").tag(c)
                }
            }
            .pickerStyle(.segmented)
            Text(lm.t("import.currency_hint"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Paste area

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineLabel(lm.t("import.paste_title"))

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(lm.t("import.paste_placeholder"))
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .frame(minHeight: 128, maxHeight: 190)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .background(surfaceCard(radius: 13, fill: fieldFill, border: 0.07))

            Button {
                haptic(.light)
                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                    text = text.isEmpty ? clip : text + "\n" + clip
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 12, weight: .semibold))
                    Text(lm.t("import.paste_button")).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.mintAccent)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OverlineLabel(lm.t("import.preview_title"))
                if !drafts.isEmpty {
                    Text(lm.t("import.tap_to_edit"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                }
                Spacer()
                let pos = importableDrafts.filter { !$0.isWatchlist }.count
                let watch = importableDrafts.filter { $0.isWatchlist }.count
                if pos > 0 { countBadge("\(pos)", tint: .mintAccent) }
                if watch > 0 { countBadge("\(watch)", tint: .labelSecondary, dashed: true) }
            }

            if needsChoiceCount > 0 {
                Text(String(format: lm.t("import.needs_choice_count"), "\(needsChoiceCount)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mintAccent)
            }

            if notFoundCount > 0 {
                Text(String(format: lm.t("import.not_found_count"), "\(notFoundCount)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.lossText)
            }

            if !drafts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        Button {
                            haptic(.light)
                            editingDraft = draft
                        } label: {
                            draftRow(draft)
                        }
                        .buttonStyle(.plain)
                        if index < drafts.count - 1 {
                            Rectangle().fill(Color.separatorHair).frame(height: 0.5).padding(.leading, 62)
                        }
                    }
                }
                .background(surfaceCard(radius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            // The line the user is still typing gets a calm hint, not a red alarm.
            if let pending = pendingIssue {
                HStack(spacing: 7) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(format: lm.t("import.issue_line"), "\(pending.line)") + " · " + reasonText(pending.reason))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.labelTertiary)
            }

            if !settledIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    OverlineLabel(lm.t("import.issues_title"), color: .lossText)
                    ForEach(settledIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.lossText).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: lm.t("import.issue_line"), "\(issue.line)") + " · " + reasonText(issue.reason))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.lossText)
                                Text(issue.text)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.labelTertiary).lineLimit(1)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(surfaceCard(radius: 16, fill: Color.lossBase.opacity(0.07), border: 0.0, borderColor: Color.lossBase.opacity(0.16)))
            }
        }
    }

    @ViewBuilder
    private func draftRow(_ draft: ImportDraft) -> some View {
        let merges = !draft.isWatchlist && ownedSymbols.contains(draft.symbol.uppercased())
        let state = rowState(for: draft)
        HStack(spacing: 12) {
            MonogramTile(symbol: draft.symbol, size: 38)
                .opacity(draft.isWatchlist ? 0.55 : 1.0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(draft.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(state == .notFound ? Color.lossText : Color.textPrimary)
                    if state == .notFound {
                        statusPill(lm.t("import.not_found"), color: .lossBase, textColor: .lossText)
                    } else if state == .ambiguous {
                        statusPill(lm.t("import.choose"), color: .mintAccent, textColor: .mintAccent, filled: true)
                    } else if state == .unverified {
                        statusPill(lm.t("import.unverified"), color: .neutralFlat, textColor: .labelSecondary)
                    } else if merges {
                        statusPill(lm.t("import.merge_note"), color: .mintAccent, textColor: .mintAccent, filled: true)
                    } else if draft.isWatchlist {
                        statusPill(lm.t("import.to_watchlist"), color: .labelTertiary, textColor: .labelSecondary, dashed: true)
                    }
                }
                Text(subtitle(for: draft))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if state == .checking {
                ProgressView().tint(Color.labelTertiary).scaleEffect(0.7)
            } else if let shares = draft.shares, let price = draft.price {
                Text(cs.format(value: shares * price, from: effectiveCurrency(draft).rawValue))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.labelQuaternary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(state == .notFound ? Color.lossBase.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }

    private func subtitle(for draft: ImportDraft) -> String {
        if draft.isWatchlist { return draft.name ?? lm.t("import.watchlist_sub") }
        var parts: [String] = []
        if let s = draft.shares { parts.append("\(PortfolioImportParser.numberString(s)) ×") }
        if let p = draft.price { parts.append("\(PortfolioImportParser.numberString(p)) \(effectiveCurrency(draft).symbol)") }
        parts.append("· " + (draft.dateString ?? lm.t("import.date_today")))
        return parts.joined(separator: " ")
    }

    // MARK: - Import CTA

    private var importButton: some View {
        Button { performImport() } label: {
            Text(importButtonLabel)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.mintInk)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.mintAccent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var importButtonLabel: String {
        lm.t("import.import_button").replacingOccurrences(of: "{count}", with: "\(importableDrafts.count)")
    }

    private func performImport() {
        let today: String = {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; return fmt.string(from: Date())
        }()
        for draft in importableDrafts {
            vm.addInvestment(
                symbol:   draft.symbol,
                shares:   draft.shares ?? 1.0,
                buyPrice: draft.price ?? 0.0,
                buyDate:  draft.dateString ?? today,
                name:     draft.name ?? draft.symbol,
                coinId:   resolvedCoinId(for: draft),
                nativeCurrency: effectiveCurrency(draft).rawValue,
                isWatchlist: draft.isWatchlist,
                brokerAdjustment: nil
            )
        }
        hapticSuccess()
        dismiss()
        onImported?()
    }

    // MARK: - Inline edit sync

    private func applyEdit(_ edited: ImportDraft, chosen: ImportCandidate?) {
        var lines = text.components(separatedBy: "\n")
        let li = edited.line - 1
        let sym = edited.symbol.uppercased()

        // A disambiguation pick carries the coinId that serialize() can't encode;
        // stash it so it survives both the save below and any later full re-parse.
        var stored = edited
        if let chosen {
            userChoices[sym] = chosen
            stored.coinId = chosen.coinId
        } else {
            // Manual symbol edit with no pick → drop any stale choice and re-validate.
            userChoices[sym] = nil
            resolutions[sym] = nil
        }

        if lines.indices.contains(li) {
            lines[li] = PortfolioImportParser.serialize(stored)
        }
        if let i = drafts.firstIndex(where: { $0.id == stored.id }) {
            drafts[i] = stored
        }
        suppressReparse = true                        // keep our in-place draft identity
        text = lines.joined(separator: "\n")
        editingDraft = nil
    }

    private func deleteDraft(_ d: ImportDraft) {
        var lines = text.components(separatedBy: "\n")
        let li = d.line - 1
        if lines.indices.contains(li) { lines.remove(at: li) }
        // Removing a line shifts subsequent line numbers → let it fully re-parse.
        suppressReparse = false
        text = lines.joined(separator: "\n")
        editingDraft = nil
    }

    // MARK: - Validation

    /// UI state for a draft row, folding in any user disambiguation choice.
    private func rowState(for draft: ImportDraft) -> ImportRowState {
        let sym = draft.symbol.uppercased()
        if userChoices[sym] != nil { return .resolved }   // a pick unblocks the row
        switch resolutions[sym] {
        case .none:                       return .checking
        case .stock?, .crypto?:           return .resolved
        case .ambiguous?:                 return .ambiguous
        case .notFound?:                  return .notFound
        case .unverified?:                return .unverified
        }
    }

    /// Disambiguation options to offer in the edit sheet (empty unless ambiguous).
    private func candidates(for draft: ImportDraft) -> [ImportCandidate] {
        if case .ambiguous(let list)? = resolutions[draft.symbol.uppercased()] { return list }
        return []
    }

    /// coinId for import: user pick > auto-resolved crypto > whatever the parser set.
    private func resolvedCoinId(for draft: ImportDraft) -> String? {
        let sym = draft.symbol.uppercased()
        if let chosen = userChoices[sym] { return chosen.coinId }
        if case .crypto(let c)? = resolutions[sym] { return c.coinId }
        return draft.coinId
    }

    /// Re-apply saved disambiguation picks after a fresh parse (which drops coinId).
    private func applyUserChoices(to ds: [ImportDraft]) -> [ImportDraft] {
        guard !userChoices.isEmpty else { return ds }
        return ds.map { d in
            var d = d
            if let chosen = userChoices[d.symbol.uppercased()] { d.coinId = chosen.coinId }
            return d
        }
    }

    private func effectiveCurrency(_ d: ImportDraft) -> AppCurrency {
        if let c = d.currency, let ac = AppCurrency(rawValue: c.uppercased()) { return ac }
        return defaultCurrency
    }

    private func scheduleValidation() {
        validationTask?.cancel()
        validationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await validate()
        }
    }

    @MainActor
    private func validate() async {
        // Unique symbols still needing a verdict (skip resolved / user-picked;
        // retry only the transient .unverified ones).
        var seen = Set<String>()
        var pending: [String] = []
        for d in drafts {
            let s = d.symbol.uppercased()
            guard !seen.contains(s) else { continue }
            seen.insert(s)
            if userChoices[s] != nil { continue }
            let cur = resolutions[s]
            if cur == nil || cur == .unverified {
                pending.append(s)
            }
        }
        guard !pending.isEmpty else { return }
        for s in pending { resolutions[s] = nil }     // → checking (spinner)

        // Bounded concurrency (≤6) to stay polite to the APIs.
        for chunk in pending.chunked(into: 6) {
            await withTaskGroup(of: (String, ImportResolution).self) { group in
                for sym in chunk {
                    group.addTask { (sym, await ImportTickerResolver.resolve(symbol: sym)) }
                }
                for await (sym, res) in group {
                    resolutions[sym] = res
                }
            }
            if Task.isCancelled { return }
        }
    }

    // MARK: - Small helpers

    private func countBadge(_ label: String, tint: Color, dashed: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold)).monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background {
                if dashed { Capsule().strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                else { Capsule().fill(tint.opacity(0.13)) }
            }
    }

    private func statusPill(_ label: String, color: Color, textColor: Color, filled: Bool = false, dashed: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .heavy)).tracking(0.4)
            .foregroundStyle(textColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background {
                if dashed { Capsule().strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                else { Capsule().fill(color.opacity(filled ? 0.13 : 0.13)) }
            }
    }

    private func reasonText(_ reason: ImportIssue.Reason) -> String {
        switch reason {
        case .invalidSymbol: return lm.t("import.issue_symbol")
        case .invalidShares: return lm.t("import.issue_shares")
        case .missingPrice:  return lm.t("import.issue_price")
        case .invalidDate:   return lm.t("import.issue_date")
        }
    }

    private func surfaceCard(radius: CGFloat, fill: Color = Color.surface, border: Double = 0.08, borderColor: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor ?? Color.white.opacity(border), lineWidth: 0.5)
            )
    }
}

// MARK: - Row UI state

/// The visual state of a preview row, derived from its resolution + user pick.
private enum ImportRowState: Equatable {
    case checking      // resolver in flight
    case resolved      // stock or crypto (or a user-picked candidate) — clean
    case ambiguous     // multiple matches, needs a choice
    case notFound      // both providers say unknown
    case unverified    // lookup couldn't be completed
}

// MARK: - Chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

// MARK: - Inline row editor

private struct ImportRowEditView: View {
    let draft: ImportDraft
    let defaultCurrency: AppCurrency
    let candidates: [ImportCandidate]
    let onSave: (ImportDraft, ImportCandidate?) -> Void
    let onDelete: (ImportDraft) -> Void

    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var symbol: String
    @State private var isWatchlist: Bool
    @State private var sharesText: String
    @State private var priceText: String
    @State private var currency: AppCurrency
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var name: String
    @State private var chosenCandidate: ImportCandidate?

    init(draft: ImportDraft, defaultCurrency: AppCurrency,
         candidates: [ImportCandidate], chosen: ImportCandidate?,
         onSave: @escaping (ImportDraft, ImportCandidate?) -> Void, onDelete: @escaping (ImportDraft) -> Void) {
        self.draft = draft
        self.defaultCurrency = defaultCurrency
        self.candidates = candidates
        self.onSave = onSave
        self.onDelete = onDelete
        _symbol = State(initialValue: draft.symbol)
        _isWatchlist = State(initialValue: draft.isWatchlist)
        _sharesText = State(initialValue: draft.shares.map { PortfolioImportParser.numberString($0) } ?? "")
        _priceText = State(initialValue: draft.price.map { PortfolioImportParser.numberString($0) } ?? "")
        _currency = State(initialValue: draft.currency.flatMap { AppCurrency(rawValue: $0.uppercased()) } ?? defaultCurrency)
        _name = State(initialValue: draft.name ?? "")
        _chosenCandidate = State(initialValue: chosen)
        let parsed = draft.dateString.flatMap { PortfolioImportView.dateFrom($0) }
        _hasDate = State(initialValue: parsed != nil)
        _date = State(initialValue: parsed ?? Date())
    }

    private var canSave: Bool {
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isWatchlist { return true }
        let s = Double(sharesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let p = Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return s > 0 && p > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !candidates.isEmpty {
                            disambiguationSection
                        }

                        labeledField(lm.t("import.edit_ticker")) {
                            TextField("", text: $symbol)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Toggle(isOn: $isWatchlist.animation()) {
                            Text(lm.t("import.edit_is_watchlist"))
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.mintAccent)
                        .padding(14)
                        .background(rowBG)

                        if !isWatchlist {
                            labeledField(lm.t("import.edit_shares")) {
                                TextField("0", text: $sharesText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Color.mintAccent)
                            }
                            labeledField(lm.t("import.edit_price")) {
                                HStack(spacing: 8) {
                                    Text(currency.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.labelTertiary)
                                    TextField("0.00", text: $priceText)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(Color.mintAccent)
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lm.t("import.edit_currency"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.labelSecondary)
                                Picker("", selection: $currency) {
                                    ForEach(AppCurrency.allCases) { c in Text("\(c.symbol)  \(c.rawValue)").tag(c) }
                                }
                                .pickerStyle(.segmented)
                            }

                            Toggle(isOn: $hasDate.animation()) {
                                Text(lm.t("import.edit_has_date"))
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .tint(Color.mintAccent)
                            .padding(14)
                            .background(rowBG)

                            if hasDate {
                                DatePicker(lm.t("import.edit_date"), selection: $date, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(Color.mintAccent)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .padding(14)
                                    .background(rowBG)
                            }
                        }

                        Button {
                            haptic(.rigid)
                            onDelete(draft)
                        } label: {
                            Text(lm.t("import.edit_remove"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.lossText)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(Color.lossBase)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, AppLayout.contentHorizontalPadding)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(lm.t("import.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t("add.abbrechen")) { dismiss() }
                        .foregroundStyle(Color.mintAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.t("import.edit_save")) { save() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSave ? Color.mintAccent : Color.labelTertiary)
                        .disabled(!canSave)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Disambiguation ("Did you mean?")

    private var disambiguationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineLabel(lm.t("import.did_you_mean"))
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, cand in
                    Button {
                        haptic(.light)
                        chosenCandidate = cand
                        symbol = cand.symbol
                        if !cand.name.isEmpty, cand.coinId != nil { name = cand.name }
                    } label: {
                        candidateRow(cand)
                    }
                    .buttonStyle(.plain)
                    if index < candidates.count - 1 {
                        Rectangle().fill(Color.separatorHair).frame(height: 0.5).padding(.leading, 56)
                    }
                }
            }
            .background(rowBG)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func candidateRow(_ cand: ImportCandidate) -> some View {
        let selected = chosenCandidate?.id == cand.id
        let isCrypto = cand.coinId != nil
        HStack(spacing: 12) {
            MonogramTile(symbol: cand.symbol, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(cand.symbol)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(cand.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(isCrypto ? lm.t("import.tag_crypto") : lm.t("import.tag_stock"))
                .font(.system(size: 9.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isCrypto ? Color.mintAccent : Color.labelSecondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill((isCrypto ? Color.mintAccent : Color.neutralFlat).opacity(0.14)))
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.mintAccent : Color.labelQuaternary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var rowBG: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder
    private func labeledField(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
            Spacer(minLength: 12)
            content()
        }
        .padding(14)
        .background(rowBG)
    }

    private func save() {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let shares = isWatchlist ? nil : Double(sharesText.replacingOccurrences(of: ",", with: "."))
        let price  = isWatchlist ? nil : Double(priceText.replacingOccurrences(of: ",", with: "."))
        let dateStr: String? = (!isWatchlist && hasDate) ? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
        }() : nil

        // A pick is only valid if the ticker still matches it (they may have
        // typed a different symbol afterwards).
        let pick = (chosenCandidate?.symbol.uppercased() == sym) ? chosenCandidate : nil
        let coinId = pick?.coinId ?? PortfolioImportParser.knownCrypto[sym]

        let updated = ImportDraft(
            id: draft.id, line: draft.line, symbol: sym,
            name: name.isEmpty ? nil : name,
            shares: shares, price: price,
            currency: isWatchlist ? nil : currency.rawValue,
            dateString: dateStr,
            coinId: coinId
        )
        haptic(.light)
        onSave(updated, pick)
    }
}

extension PortfolioImportView {
    static func dateFrom(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
