//
//  RebalancingCard.swift
//  followtrend
//

import SwiftUI

struct RebalancingCard: View {
    let suggestions: [RebalancingSuggestion]

    @EnvironmentObject private var lm: AppLanguageManager
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                haptic(.light)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "scale.3d")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.jade)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(lm.t("rebalancing.title"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(1.1)
                        Text(lm.t("rebalancing.subtitle"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    if suggestions.isEmpty {
                        Text(lm.t("rebalancing.empty"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(suggestions) { suggestion in
                            suggestionRow(suggestion)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.25), value: suggestions)
    }

    private func suggestionRow(_ suggestion: RebalancingSuggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(for: suggestion.severity))
                .frame(width: 24, height: 24)
                .background(color(for: suggestion.severity).opacity(0.12))
                .clipShape(Circle())

            Text(localizedMessage(for: suggestion))
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func localizedMessage(for suggestion: RebalancingSuggestion) -> String {
        let template = lm.t(suggestion.localizationKey)
        guard !suggestion.arguments.isEmpty else { return template }
        return String(format: template, arguments: suggestion.arguments)
    }

    private func color(for severity: RebalancingSeverity) -> Color {
        switch severity {
        case .info:
            return Color.jade
        case .warning:
            return Color.orange
        case .critical:
            return Color.crimson
        }
    }
}
