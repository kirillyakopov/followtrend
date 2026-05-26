//
//  WidgetView.swift
//  followtrend
//
//  SwiftUI view structures rendering small and medium sizes.
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

// MARK: - Small Widget
struct SmallWidgetView: View {
    let entry: PortfolioEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.jade)
                Text("followtrend")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 12)
            
            Spacer()
            
            // Portfolio Balance
            VStack(alignment: .leading, spacing: 4) {
                Text("BALANCE")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.0)
                
                Text(formatCurrency(entry.totalValue, currency: entry.currency))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                // Return badge
                HStack(spacing: 2) {
                    Image(systemName: entry.percentageGain >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                    Text(String(format: "%@%.1f%%", entry.percentageGain >= 0 ? "+" : "", entry.percentageGain))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(entry.percentageGain.gainColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(entry.percentageGain.gainColor.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget
struct MediumWidgetView: View {
    let entry: PortfolioEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Side: Portfolio Value
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.jade)
                    Text("PORTFOLIO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .tracking(1.0)
                }
                .padding(.bottom, 14)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatCurrency(entry.totalValue, currency: entry.currency))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    HStack(spacing: 2) {
                        Image(systemName: entry.percentageGain >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                        Text(String(format: "%@%.1f%%", entry.percentageGain >= 0 ? "+" : "", entry.percentageGain))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(entry.percentageGain.gainColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(entry.percentageGain.gainColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .background(Color.borderHair)
                .padding(.vertical, 4)
            
            // Right Side: Top Watchlist Item
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#6366f1"))
                    Text("TOP WATCHLIST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .tracking(1.0)
                }
                .padding(.bottom, 14)
                
                Spacer()
                
                if let item = entry.topWatchlistItem {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.symbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        
                        Text(item.name)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatCurrency(item.price, currency: entry.currency))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            
                            Spacer()
                            
                            Text(String(format: "%@%.1f%%", item.changePercent >= 0 ? "+" : "", item.changePercent))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(item.changePercent.gainColor)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No items")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Add in application")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
