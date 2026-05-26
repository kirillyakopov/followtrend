
//
//  SparklineChart.swift
//  followtrend
//

import SwiftUI

// MARK: - Sparkline Chart View

struct SparklineChart: View {
    let points: [Double]
    let positive: Bool
    var showGradient: Bool = true

    private var accent: Color { positive ? .jade : .crimson }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mapped = mapPoints(points, in: geo.size)

            ZStack {
                if showGradient {
                    // Area fill
                    areaPath(mapped, width: w, height: h)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.25), accent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // Line
                linePath(mapped)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: Path builders

    private func mapPoints(_ pts: [Double], in size: CGSize) -> [CGPoint] {
        guard pts.count > 1 else { return [] }
        let lo = pts.min()!
        let hi = pts.max()!
        let span = hi == lo ? 1.0 : hi - lo
        let padY: CGFloat = 8
        return pts.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(pts.count - 1)
            let ratio = CGFloat((v - lo) / span)
            let y = size.height - padY - ratio * (size.height - padY * 2)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        return path
    }

    private func areaPath(_ pts: [CGPoint], width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        guard let first = pts.first, let last = pts.last else { return path }
        path.move(to: CGPoint(x: first.x, y: height))
        path.addLine(to: first)
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.closeSubpath()
        return path
    }
}
