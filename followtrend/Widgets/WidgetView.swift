//
//  WidgetView.swift
//  followtrend
//
//  SwiftUI view structures rendering small and medium sizes.
//  iOS 26 redesign — dark gradient tile, mint accent, tabular numerals.
//

import SwiftUI
import WidgetKit

struct WidgetView: View {
    let entry: PortfolioEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Brand Row (tiny glyph + wordmark)

private struct WidgetBrandRow: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.mintAccent)
            Text("followtrend")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.labelSecondary)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: PortfolioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetBrandRow()

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text(formatCurrency(entry.totalValue, currency: entry.currency))
                    .font(.system(size: 19, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(String(format: "%@%.2f%% all time", entry.percentageGain.gainPrefix, entry.percentageGain))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(entry.percentageGain >= 0 ? Color.mintAccent : Color.lossText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: PortfolioEntry

    var body: some View {
        HStack(spacing: 14) {
            // Left column: portfolio value + all-time change
            VStack(alignment: .leading, spacing: 0) {
                WidgetOverline("Portfolio")

                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    Text(formatCurrency(entry.totalValue, currency: entry.currency))
                        .font(.system(size: 23, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(String(format: "%@%.2f%% all time", entry.percentageGain.gainPrefix, entry.percentageGain))
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(entry.percentageGain >= 0 ? Color.mintAccent : Color.lossText)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Text("UPDATED")
                        Text("·")
                        Text(entry.date, style: .time)
                            .monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hairline vertical divider
            Rectangle()
                .fill(Color.separatorHair)
                .frame(width: 0.5)
                .padding(.vertical, 4)

            // Right column: top performer (or allocation placeholder)
            VStack(alignment: .leading, spacing: 0) {
                WidgetOverline("Top performer")

                Spacer()

                if let item = entry.topWatchlistItem {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            monogramTile(for: item.symbol)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.symbol)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(item.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.labelSecondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%@%.1f%%", item.changePercent.gainPrefix, item.changePercent))
                                .font(.system(size: 15, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(item.changePercent >= 0 ? Color.mintAccent : Color.lossText)

                            Spacer()

                            Text(formatCurrency(item.price, currency: entry.currency))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetAllocationBar()
                        Text("No watchlist yet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monogramTile(for symbol: String) -> some View {
        let hue = Color.monogramHue(for: symbol)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hue.bg)
            .frame(width: 26, height: 26)
            .overlay(
                Text(symbol.prefix(2).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hue.fg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Currency Formatter Helper
private func formatCurrency(_ value: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}
