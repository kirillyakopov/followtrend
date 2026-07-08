//
//  AssetAllocationChartView.swift
//  followtrend
//

import SwiftUI

// MARK: - Allocation segment palette (README §1.6 — top-5 by weight, in order)

enum AllocationPalette {
    static let segments: [Color] = [
        Color.mintAccent,
        Color.mintAccent.opacity(0.55),
        Color.white.opacity(0.66),
        Color.white.opacity(0.34),
        Color.white.opacity(0.16)
    ]

    static func color(_ rank: Int) -> Color {
        segments[max(0, min(rank, segments.count - 1))]
    }
}

// MARK: - Allocation donut (92pt, ring thickness ≈ 38% of radius)

struct AllocationDonut: View {
    /// Slices pre-ranked by weight (heaviest first); at most the first 5 are drawn.
    let slices: [AssetAllocationSlice]
    var diameter: CGFloat = 92

    var body: some View {
        let thickness = (diameter / 2) * 0.38
        let ringDiameter = diameter - thickness

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: thickness)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(
                        AllocationPalette.color(index),
                        style: StrokeStyle(lineWidth: thickness, lineCap: .butt)
                    )
            }
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .rotationEffect(.degrees(-90))
        .frame(width: diameter, height: diameter)
    }

    private var segments: [(start: CGFloat, end: CGFloat)] {
        let ranked = Array(slices.prefix(AllocationPalette.segments.count))
        let total = max(ranked.reduce(0) { $0 + $1.percentage }, 0.0001)
        var cursor: Double = 0
        return ranked.map { slice in
            let fraction = slice.percentage / total
            defer { cursor += fraction }
            return (CGFloat(cursor), CGFloat(cursor + fraction))
        }
    }
}

// MARK: - Asset allocation card

struct AssetAllocationChartView: View {
    let slices: [AssetAllocationSlice]

    @EnvironmentObject private var lm: AppLanguageManager
    @State private var expandedCategory: AssetCategory?

    private var rankedSlices: [AssetAllocationSlice] {
        slices.sorted { $0.percentage > $1.percentage }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                OverlineLabel(lm.t("allocation.title"))
                Spacer()
                Text(lm.t("allocation.excludesWatchlist"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
            }

            if slices.isEmpty {
                Text(lm.t("allocation.empty"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.labelTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    AllocationDonut(slices: rankedSlices, diameter: 92)

                    VStack(spacing: 10) {
                        ForEach(Array(rankedSlices.enumerated()), id: \.element.id) { index, slice in
                            allocationRow(slice, rank: index)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let expandedCategory,
                   let slice = slices.first(where: { $0.category == expandedCategory }) {
                    expandedAssets(slice)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .cardStyle()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expandedCategory)
        .animation(.easeInOut(duration: 0.35), value: slices)
    }

    private func allocationRow(_ slice: AssetAllocationSlice, rank: Int) -> some View {
        Button {
            haptic(.light)
            expandedCategory = expandedCategory == slice.category ? nil : slice.category
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(AllocationPalette.color(rank))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.t(slice.category.localizationKey))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(CurrencyService.shared.formatConverted(slice.value))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                Text(String(format: "%.1f%%", slice.percentage))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func expandedAssets(_ slice: AssetAllocationSlice) -> some View {
        VStack(spacing: 8) {
            ForEach(slice.assets) { asset in
                HStack {
                    Text(asset.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(asset.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 4)
    }
}
