
//
//  SparklineChart.swift
//  followtrend
//
//  Tiny row sparkline (52×20) + shared chart path/format helpers
//  used by ChartView and PortfolioChartView.
//

import SwiftUI

// MARK: - Shared chart path builder (Catmull-Rom smoothing)

enum ChartPathBuilder {

    /// Smoothed line through the mapped points (Catmull-Rom → cubic Bézier,
    /// mirrors the design prototype's `smoothPath`).
    static func smoothedLine(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 2 else {
            if pts.count == 2 { path.addLine(to: pts[1]) }
            return path
        }
        for i in 1..<pts.count {
            let p0 = pts[max(i - 2, 0)]
            let p1 = pts[i - 1]
            let p2 = pts[i]
            let p3 = pts[min(i + 1, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Closed area under the smoothed line, down to `height`.
    static func area(points pts: [CGPoint], height: CGFloat) -> Path {
        var path = smoothedLine(pts)
        guard let first = pts.first, let last = pts.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Shared scrub-label value formatting (tabular, currency-agnostic)

enum ChartValueFormat {
    private static let twoDigits: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let noDigits: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func scrub(_ value: Double) -> String {
        let f = abs(value) > 9999 ? noDigits : twoDigits
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Sparkline Chart View

struct SparklineChart: View {
    let points: [Double]
    let positive: Bool
    var showGradient: Bool = true

    private var accent: Color { positive ? .mintAccent : .lossBase }

    var body: some View {
        GeometryReader { geo in
            let mapped = mapPoints(points, in: geo.size)

            ZStack {
                if showGradient, mapped.count > 1 {
                    ChartPathBuilder.area(points: mapped, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.24), accent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // Clean 1.6pt line — no dots, no axes
                ChartPathBuilder.smoothedLine(mapped)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: Point mapping

    private func mapPoints(_ pts: [Double], in size: CGSize) -> [CGPoint] {
        guard pts.count > 1 else { return [] }
        let lo = pts.min()!
        let hi = pts.max()!
        let span = hi == lo ? 1.0 : hi - lo
        // Scale padding down for tiny (52×20) renders so the line keeps amplitude.
        let padY: CGFloat = max(1.6, min(8, size.height * 0.12))
        return pts.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(pts.count - 1)
            let ratio = CGFloat((v - lo) / span)
            let y = size.height - padY - ratio * (size.height - padY * 2)
            return CGPoint(x: x, y: y)
        }
    }
}
