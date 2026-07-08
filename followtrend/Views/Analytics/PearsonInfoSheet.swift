//
//  PearsonInfoSheet.swift
//  followtrend
//
//  Correlation info sheet — spectrum bar with live marker, glyph cards,
//  interactive simulation and "why it matters" (iOS 26 redesign, README §7).
//

import SwiftUI
import Combine

struct PearsonTextCache {
    let title: String
    let oneLiner: String
    let whyItMattersTitle: String
    let whyPoint1: String
    let whyPoint2: String
    let whyPoint3: String
    let whyPoint4: String
    let simulationTitle: String
    let simulationSubtitle: String
    let simulationPortfolio: String
    let simulationBenchmark: String
    let simulationLabel: String
    let summaryHigh: String
    let summaryModerate: String
    let summaryWeak: String
    let summaryInverse: String
    let done: String

    init(lm: AppLanguageManager) {
        self.title = lm.t("pearson.title")
        self.oneLiner = lm.t("pearson.shortDescription")
        self.whyItMattersTitle = lm.t("pearson.whyItMatters.title")
        self.whyPoint1 = lm.t("pearson.whyItMatters.point1")
        self.whyPoint2 = lm.t("pearson.whyItMatters.point2")
        self.whyPoint3 = lm.t("pearson.whyItMatters.point3")
        self.whyPoint4 = lm.t("pearson.whyItMatters.point4")
        self.simulationTitle = lm.t("pearson.simulation.title").uppercased()
        self.simulationSubtitle = lm.t("pearson.simulation.subtitle")
        self.simulationPortfolio = lm.t("pearson.simulation.portfolio")
        self.simulationBenchmark = lm.t("pearson.simulation.benchmark")
        self.simulationLabel = lm.t("pearson.simulation.label")
        self.summaryHigh = lm.t("pearson.summaries.high")
        self.summaryModerate = lm.t("pearson.summaries.moderate")
        self.summaryWeak = lm.t("pearson.summaries.weak")
        self.summaryInverse = lm.t("pearson.summaries.inverse")
        self.done = lm.t("common.fertig")
    }
}

@MainActor
final class PearsonViewModel: ObservableObject {
    @Published var texts: PearsonTextCache?

    func load(lm: AppLanguageManager) {
        if texts == nil {
            texts = PearsonTextCache(lm: lm)
        }
    }
}

struct PearsonInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: AppLanguageManager
    @StateObject private var vm = PearsonViewModel()

    @State private var demoCorrelation: Double = 0.42

    // Preset returns for deterministic path simulation
    private let benchmarkReturns: [Double] = [0.0, 0.03, -0.015, 0.04, 0.06, -0.05, 0.02, 0.04, -0.01, 0.03, 0.05, -0.03, 0.04, 0.01, 0.025]
    private let noiseReturns: [Double] = [0.0, -0.04, 0.05, -0.02, -0.03, 0.06, -0.01, -0.03, 0.03, -0.04, 0.01, 0.04, -0.03, 0.02, -0.015]

    var body: some View {
        Group {
            if let texts = vm.texts {
                content(texts: texts)
            } else {
                Color.clear
                    .onAppear {
                        vm.load(lm: lm)
                    }
            }
        }
    }

    @ViewBuilder
    private func content(texts: PearsonTextCache) -> some View {
        VStack(spacing: 0) {
            // Header: title 22/800 + one-liner
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(texts.title)
                        .font(AppTypography.sheetTitle)
                        .tracking(-0.4)
                        .foregroundStyle(Color.textPrimary)
                    Text(texts.oneLiner)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.labelSecondary)
                        .lineSpacing(3)
                }

                Spacer(minLength: 12)

                Button {
                    haptic(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    spectrumCard
                    glyphGrid
                    simulationCard(texts: texts)
                    whyItMattersCard(texts: texts)
                    doneButton(texts: texts)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Spectrum card

    private var spectrumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 7) {
                // Floating mint marker pill, positioned proportionally along the bar.
                // Tracks the interactive simulation's r value below.
                GeometryReader { geo in
                    let clamped = min(1.0, max(-1.0, demoCorrelation))
                    let x = CGFloat((clamped + 1.0) / 2.0) * geo.size.width
                    Text(markerLabel(clamped))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.mintInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.mintAccent))
                        .fixedSize()
                        .position(x: min(max(x, 28), max(geo.size.width - 28, 28)), y: 10)
                }
                .frame(height: 20)

                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: "#D96A60"), location: 0.00),
                                .init(color: Color(hex: "#A97F79"), location: 0.22),
                                .init(color: Color(hex: "#8E8E93"), location: 0.50),
                                .init(color: Color(hex: "#6FB28E"), location: 0.76),
                                .init(color: Color(hex: "#7BE0AE"), location: 1.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 10)

                HStack {
                    Text("−1")
                    Spacer()
                    Text("−0.7")
                    Spacer()
                    Text("−0.3")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("+0.3")
                    Spacer()
                    Text("+0.7")
                    Spacer()
                    Text("+1")
                }
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.labelTertiary)
            }

            Text("r = cov(x, y) / (σx · σy)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 20)
    }

    private func markerLabel(_ r: Double) -> String {
        String(format: "r · %@%.2f", r >= 0 ? "+" : "−", abs(r))
    }

    // MARK: - Glyph cards (3-column grid)

    private enum GlyphKind {
        case together, independent, opposite
    }

    private var glyphGrid: some View {
        HStack(alignment: .top, spacing: 9) {
            glyphCard(kind: .together, number: "+1", caption: lm.t("pearson.glyph_together"))
            glyphCard(kind: .independent, number: "0", caption: lm.t("pearson.glyph_independent"))
            glyphCard(kind: .opposite, number: "−1", caption: lm.t("pearson.glyph_opposite"))
        }
    }

    private func glyphCard(kind: GlyphKind, number: String, caption: String) -> some View {
        let fill: Color
        let border: Color
        switch kind {
        case .together:
            fill = Color.mintAccent.opacity(0.08)
            border = Color.mintAccent.opacity(0.13)
        case .independent:
            fill = Color.white.opacity(0.045)
            border = Color.white.opacity(0.08)
        case .opposite:
            fill = Color.lossBase.opacity(0.08)
            border = Color.lossBase.opacity(0.13)
        }

        return VStack(alignment: .leading, spacing: 0) {
            glyphLines(kind: kind)
                .frame(height: 34)

            Text(number)
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 8)

            Text(caption)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func glyphLines(kind: GlyphKind) -> some View {
        GeometryReader { geo in
            let size = geo.size
            switch kind {
            case .together:
                miniLine([(2, 24), (14, 17), (26, 21), (38, 11), (50, 15), (62, 5)], in: size)
                    .stroke(Color.mintAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                miniLine([(2, 31), (14, 24), (26, 28), (38, 18), (50, 22), (62, 12)], in: size)
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .independent:
                miniLine([(2, 26), (14, 20), (26, 23), (38, 14), (50, 17), (62, 9)], in: size)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                miniLine([(2, 16), (14, 25), (26, 12), (38, 23), (50, 10), (62, 20)], in: size)
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .opposite:
                miniLine([(2, 26), (14, 19), (26, 23), (38, 13), (50, 17), (62, 7)], in: size)
                    .stroke(Color.mintAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                miniLine([(2, 10), (14, 17), (26, 13), (38, 23), (50, 19), (62, 29)], in: size)
                    .stroke(Color.lossBase, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func miniLine(_ points: [(CGFloat, CGFloat)], in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        func map(_ pt: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(x: pt.0 / 64.0 * size.width, y: pt.1 / 36.0 * size.height)
        }
        path.move(to: map(first))
        for pt in points.dropFirst() {
            path.addLine(to: map(pt))
        }
        return path
    }

    // MARK: - Interactive simulation card

    @ViewBuilder
    private func simulationCard(texts: PearsonTextCache) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                OverlineLabel(texts.simulationTitle)
                Text(texts.simulationSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.labelSecondary)
            }

            // The graph
            GeometryReader { geo in
                let paths = generatePaths(r: demoCorrelation, size: geo.size)
                ZStack {
                    // Grid lines
                    VStack {
                        Spacer()
                        Rectangle().fill(Color.separatorHair).frame(height: 0.5)
                        Spacer()
                        Rectangle().fill(Color.separatorHair).frame(height: 0.5)
                        Spacer()
                    }

                    // Benchmark path
                    Path { path in
                        guard !paths.benchmark.isEmpty else { return }
                        path.move(to: paths.benchmark[0])
                        for i in 1..<paths.benchmark.count {
                            path.addLine(to: paths.benchmark[i])
                        }
                    }
                    .stroke(Color.labelSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))

                    // Portfolio path
                    Path { path in
                        guard !paths.portfolio.isEmpty else { return }
                        path.move(to: paths.portfolio[0])
                        for i in 1..<paths.portfolio.count {
                            path.addLine(to: paths.portfolio[i])
                        }
                    }
                    .stroke(correlationColor(demoCorrelation), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 140)

            // Legend
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(correlationColor(demoCorrelation))
                        .frame(width: 16, height: 3)
                    Text(texts.simulationPortfolio)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                }

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.labelSecondary.opacity(0.6))
                                .frame(width: 4, height: 2)
                        }
                    }
                    Text(texts.simulationBenchmark)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            // Slider and readout
            VStack(spacing: 12) {
                HStack {
                    Text(texts.simulationLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text(String(format: "%@%.2f", demoCorrelation >= 0 ? "+" : "", demoCorrelation))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(correlationColor(demoCorrelation))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(correlationColor(demoCorrelation).opacity(0.12)))
                }

                Slider(value: $demoCorrelation, in: -1.0...1.0, step: 0.05) {
                    Text(texts.simulationTitle)
                } minimumValueLabel: {
                    Text("-1.0")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelTertiary)
                } maximumValueLabel: {
                    Text("+1.0")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelTertiary)
                }
                .tint(correlationColor(demoCorrelation))
                .onChange(of: demoCorrelation) { _, _ in
                    haptic(.light)
                }

                Text(correlationSummaryText(demoCorrelation, texts: texts))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(correlationColor(demoCorrelation))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 20)
    }

    // MARK: - Why it matters

    @ViewBuilder
    private func whyItMattersCard(texts: PearsonTextCache) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineLabel(texts.whyItMattersTitle)

            VStack(alignment: .leading, spacing: 8) {
                bulletPoint(texts.whyPoint1)
                bulletPoint(texts.whyPoint2)
                bulletPoint(texts.whyPoint3)
                bulletPoint(texts.whyPoint4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private func doneButton(texts: PearsonTextCache) -> some View {
        Button {
            haptic(.light)
            dismiss()
        } label: {
            Text(texts.done)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .padding(.top, 4)
    }

    // MARK: - Path Generator

    private func generatePaths(r: Double, size: CGSize) -> (benchmark: [CGPoint], portfolio: [CGPoint]) {
        var bPrice = 100.0
        var pPrice = 100.0

        var bPrices: [Double] = [bPrice]
        var pPrices: [Double] = [pPrice]

        let clampedR = min(1.0, max(-1.0, r))

        for t in 1..<benchmarkReturns.count {
            let br = benchmarkReturns[t]
            let nr = noiseReturns[t]

            // Pearson linear correlation formula simulation
            let pr = clampedR * br + sqrt(1.0 - clampedR * clampedR) * nr

            bPrice = bPrice * (1.0 + br)
            pPrice = pPrice * (1.0 + pr)

            bPrices.append(bPrice)
            pPrices.append(pPrice)
        }

        let allValues = bPrices + pPrices
        let minVal = allValues.min() ?? 80.0
        let maxVal = allValues.max() ?? 120.0
        let valRange = maxVal - minVal > 0 ? (maxVal - minVal) : 1.0

        var bPoints: [CGPoint] = []
        var pPoints: [CGPoint] = []

        let count = benchmarkReturns.count
        for i in 0..<count {
            let x = CGFloat(i) / CGFloat(count - 1) * size.width

            // Map 0..1 to height..0 in SwiftUI coordinates
            let yB = size.height - CGFloat((bPrices[i] - minVal) / valRange) * size.height
            let yP = size.height - CGFloat((pPrices[i] - minVal) / valRange) * size.height

            bPoints.append(CGPoint(x: x, y: yB))
            pPoints.append(CGPoint(x: x, y: yP))
        }

        return (bPoints, pPoints)
    }

    // MARK: - Color/Text Helpers

    private func correlationColor(_ r: Double) -> Color {
        if r < 0.3 {
            return Color.mintAccent
        } else if r < 0.7 {
            return Color.neutralFlat
        } else {
            return Color.lossBase
        }
    }

    private func correlationSummaryText(_ r: Double, texts: PearsonTextCache) -> String {
        if r >= 0.7 {
            return texts.summaryHigh
        } else if r >= 0.3 {
            return texts.summaryModerate
        } else if r >= -0.3 {
            return texts.summaryWeak
        } else {
            return texts.summaryInverse
        }
    }

    @ViewBuilder
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.mintAccent)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.labelSecondary)
        }
    }
}

#Preview {
    PearsonInfoSheet()
        .environmentObject(AppLanguageManager.shared)
        .preferredColorScheme(.dark)
}
