//
//  PortfolioChartView.swift
//  followtrend
//
//  Aggregate chart showing the total portfolio value over time.
//

import SwiftUI

struct PortfolioChartView: View {
    @ObservedObject var vm: PortfolioViewModel
    let isPositive: Bool

    @State private var chartState: ChartLoadState = .idle
    @State private var timeframe:  Timeframe = .oneMonth
    @State private var loadTask:   Task<Void, Never>?

    private var accent: Color { isPositive ? .jade : .crimson }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timeframe strip
            timeframeBar

            // Chart area
            Group {
                switch chartState {
                case .idle, .loading:
                    shimmerSkeleton
                case .loaded(let points):
                    lineChart(points: points)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .error(let msg):
                    errorView(msg)
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.4), value: chartState.isLoading)

            // Dynamic X-Axis Labels from real data timestamps
            if case .loaded(let points) = chartState, let first = points.first, let last = points.last {
                HStack {
                    Text(formatDate(first.timestamp))
                    Spacer()
                    Text(formatDate(last.timestamp))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textMuted)
                .padding(.top, 12)
            }
        }
        .onAppear { load() }
        .onChange(of: timeframe) { _, _ in load() }
        .onChange(of: vm.investments) { _, _ in load() }
    }

    @Namespace private var tfNamespace

    // MARK: - Timeframe bar

    private var timeframeBar: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases) { tf in
                let isActive = timeframe == tf
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        timeframe = tf
                    }
                    haptic(.soft)
                } label: {
                    Text(tf.rawValue)
                        .font(.system(size: 12, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? Color.jade : Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isActive {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .glassEffect(.regular.tint(Color.jade.opacity(0.15)), in: .capsule)
                                    .shadow(color: Color.jade.opacity(0.22), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "timeframeActive", in: tfNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect(.regular.tint(Color.jade.opacity(0.02)), in: .capsule)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Line chart

    @ViewBuilder
    private func lineChart(points: [ChartPoint]) -> some View {
        GeometryReader { geo in
            let closes = points.map(\.close)
            let mapped = mapPoints(closes, in: geo.size)
            let first  = closes.first ?? 0
            let last   = closes.last  ?? 0
            let trend  = last >= first

            ZStack {
                // Gradient fill
                areaPath(mapped, size: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [
                                (trend ? Color.jade : Color.crimson).opacity(0.28),
                                .clear
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // Line stroke
                linePath(mapped)
                    .stroke(
                        trend ? Color.jade : Color.crimson,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                // End-dot
                if let last = mapped.last {
                    Circle()
                        .fill(trend ? Color.jade : Color.crimson)
                        .frame(width: 6, height: 6)
                        .shadow(color: (trend ? Color.jade : Color.crimson).opacity(0.8), radius: 6)
                        .position(last)
                }
            }
        }
    }

    // MARK: - Shimmer skeleton

    private var shimmerSkeleton: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.bgElevated)
            .overlay(
                ShimmerView()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(Color.textMuted)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { load() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.jade)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Async data load

    private func load() {
        if vm.investments.isEmpty {
            chartState = .loaded([])
            return
        }

        loadTask?.cancel()
        chartState = .loading

        loadTask = Task {
            do {
                let points = try await vm.fetchPortfolioCandles(timeframe: timeframe)
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation {
                        if points.isEmpty {
                            chartState = .error("No chart data available")
                        } else {
                            chartState = .loaded(points)
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

    // MARK: - Date Formatting
    
    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        if timeframe == .oneDay {
            fmt.dateFormat = "HH:mm"
        } else if timeframe == .oneYear || timeframe == .max {
            fmt.dateFormat = "MMM yyyy"
        } else {
            fmt.dateFormat = "MMM d"
        }
        return fmt.string(from: date)
    }

    // MARK: - Path helpers

    private func mapPoints(_ vals: [Double], in size: CGSize) -> [CGPoint] {
        guard vals.count > 1 else {
            if vals.count == 1 {
                return [CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)]
            }
            return []
        }
        let lo = vals.min()!, hi = vals.max()!
        let span = hi == lo ? 1.0 : hi - lo
        let padY: CGFloat = 10
        return vals.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(vals.count - 1)
            let y = size.height - padY - CGFloat((v - lo) / span) * (size.height - padY * 2)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            path.addLine(to: pts[i])
        }
        return path
    }

    private func areaPath(_ pts: [CGPoint], size: CGSize) -> Path {
        var path = linePath(pts)
        guard let last = pts.last, let first = pts.first else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
