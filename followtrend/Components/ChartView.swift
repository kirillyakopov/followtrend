//
//  ChartView.swift
//  followtrend
//
//  Real OHLC/close chart with loading state, error fallback,
//  gradient fill, scrub interaction, and timeframe switching.
//

import SwiftUI

// MARK: - Chart View

struct ChartView: View {
    let symbol:    String
    let coinId:    String?        // non-nil for crypto
    let isPositive: Bool
    let priceAdjustmentFactor: Double?
    let displayBrokerAdjustedChart: Bool

    @State private var chartState: ChartLoadState = .idle
    @State private var timeframe:  Timeframe = .oneMonth
    @State private var loadTask:   Task<Void, Never>?
    @State private var scrubIndex: Int? = nil

    private var accent: Color { isPositive ? .mintAccent : .lossBase }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chart area
            Group {
                switch chartState {
                case .idle, .loading:
                    loadingView
                case .loaded(let points):
                    lineChart(points: points)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .error(let msg):
                    errorView(msg)
                }
            }
            .frame(height: 118)
            .animation(.easeInOut(duration: 0.4), value: chartState.isLoading)

            // Time selector (capsule segmented control)
            timeframeBar
                .padding(.top, 14)
        }
        .onAppear { load() }
        .onChange(of: timeframe) { _, _ in load() }
    }

    // MARK: - Timeframe bar (native segmented control)

    private var timeframeBar: some View {
        Picker("", selection: $timeframe) {
            ForEach(Timeframe.allCases) { tf in
                Text(tf.rawValue).tag(tf)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: timeframe)
    }

    // MARK: - Line chart (§1.4 treatment)

    @ViewBuilder
    private func lineChart(points: [ChartPoint]) -> some View {
        GeometryReader { geo in
            let closes = points.map(\.close)
            let mapped = mapPoints(closes, in: geo.size)
            let first  = closes.first ?? 0
            let last   = closes.last  ?? 0
            let trend  = last >= first
            let lineColor = trend ? Color.mintAccent : Color.lossBase

            ZStack {
                // Dashed baseline at period start value
                if let start = mapped.first {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: start.y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: start.y))
                    }
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                // Gradient area fill (accent 24% → 0)
                ChartPathBuilder.area(points: mapped, height: geo.size.height)
                    .fill(
                        LinearGradient(
                            colors: [lineColor.opacity(0.24), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // Smoothed 2.4pt line
                ChartPathBuilder.smoothedLine(mapped)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                // Scrub overlay
                if let idx = scrubIndex, mapped.indices.contains(idx), closes.indices.contains(idx) {
                    let pt = mapped[idx]

                    // Vertical hairline
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: 0))
                        p.addLine(to: CGPoint(x: pt.x, y: geo.size.height))
                    }
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)

                    // 4.4pt-radius dot with 2pt dark ring
                    Circle()
                        .fill(lineColor)
                        .frame(width: 8.8, height: 8.8)
                        .overlay(Circle().stroke(Color.bgDeep, lineWidth: 2))
                        .position(pt)

                    // Floating tabular label — signed % vs. first visible point
                    // (candle data is native-currency, so absolute values would
                    // disagree with the FX-converted headers).
                    Text(first == 0
                         ? "—"
                         : String(format: "%+.2f%%", (closes[idx] - first) / first * 100))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.surface))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                        .position(x: min(max(pt.x, 40), geo.size.width - 40), y: 12)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard closes.count > 1 else { return }
                        let frac = max(0, min(1, g.location.x / max(geo.size.width, 1)))
                        let idx = Int((frac * CGFloat(closes.count - 1)).rounded())
                        if idx != scrubIndex { scrubIndex = idx }
                    }
                    .onEnded { _ in scrubIndex = nil }
            )
        }
    }

    // MARK: - Loading state (mint ProgressView)

    private var loadingView: some View {
        ProgressView()
            .tint(Color.mintAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
            Text(msg)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.labelTertiary)
                .multilineTextAlignment(.center)
            Button(AppLanguageManager.shared.t("chart.retry")) { load() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mintAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Async data load

    private func load() {
        loadTask?.cancel()
        scrubIndex = nil
        chartState = .loading

        loadTask = Task {
            do {
                let points: [ChartPoint]
                if let id = coinId {
                    points = try await CryptoDataService.shared.fetchCandles(coinId: id, timeframe: timeframe)
                } else {
                    points = try await MarketDataService.shared.fetchCandles(symbol: symbol, timeframe: timeframe)
                }
                let displayPoints = adjustedPoints(points)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation {
                        if displayPoints.isEmpty {
                            chartState = .error(AppLanguageManager.shared.t("chart.no_data"))
                        } else {
                            chartState = .loaded(displayPoints)
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation { chartState = .error(error.localizedDescription) }
                }
            }
        }
    }

    private func adjustedPoints(_ points: [ChartPoint]) -> [ChartPoint] {
        guard displayBrokerAdjustedChart,
              let factor = priceAdjustmentFactor,
              factor.isFinite,
              factor > 0 else {
            return points
        }
        return points.map { point in
            ChartPoint(
                timestamp: point.timestamp,
                close: point.close * factor,
                open: point.open.map { $0 * factor },
                high: point.high.map { $0 * factor },
                low: point.low.map { $0 * factor },
                volume: point.volume
            )
        }
    }

    // MARK: - Point mapping

    private func mapPoints(_ vals: [Double], in size: CGSize) -> [CGPoint] {
        guard vals.count > 1 else { return [] }
        let lo = vals.min()!, hi = vals.max()!
        let span = hi == lo ? 1.0 : hi - lo
        let padY: CGFloat = 10
        return vals.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(vals.count - 1)
            let y = size.height - padY - CGFloat((v - lo) / span) * (size.height - padY * 2)
            return CGPoint(x: x, y: y)
        }
    }
}
