//
//  PearsonInfoSheet.swift
//  followtrend
//
//  An interactive educational modal explaining the Pearson Correlation coefficient
//  with live simulated paths, a mathematical reference, and risk guidelines.
//

import SwiftUI

struct PearsonInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: AppLanguageManager
    
    @State private var demoCorrelation: Double = 0.5
    
    // Preset returns for deterministic path simulation
    private let benchmarkReturns: [Double] = [0.0, 0.03, -0.015, 0.04, 0.06, -0.05, 0.02, 0.04, -0.01, 0.03, 0.05, -0.03, 0.04, 0.01, 0.025]
    private let noiseReturns: [Double] = [0.0, -0.04, 0.05, -0.02, -0.03, 0.06, -0.01, -0.03, 0.03, -0.04, 0.01, 0.04, -0.03, 0.02, -0.015]

    var body: some View {
        ZStack {
            PremiumDarkBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    Text(lm.t("pearson.title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        haptic(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.textSecondary)
                            .hoverEffect(.highlight)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        
                        // Intro Text
                        Text(LocalizedStringKey(lm.t("pearson.explanation")))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .lineSpacing(4)
                        
                        // Formula Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lm.t("pearson.formula.title").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.0)
                            
                            // Visual math display
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Text("covariance(X, Y)")
                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    Rectangle()
                                        .fill(Color.textPrimary.opacity(0.6))
                                        .frame(height: 1.5)
                                    Text("σX * σY")
                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                }
                                .foregroundStyle(Color.textPrimary)
                                .padding(.vertical, 8)
                                
                                Text("   =   r")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            
                            Divider().background(Color.borderHair)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Label {
                                    Text(LocalizedStringKey(lm.t("pearson.formula.x")))
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Color.jade)
                                }
                                Label {
                                    Text(LocalizedStringKey(lm.t("pearson.formula.y")))
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Label {
                                    Text(LocalizedStringKey(lm.t("pearson.formula.sigma")))
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                        }
                        .cardStyle()
                        
                        // Interactive Visualization Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lm.t("pearson.simulation.title").uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.0)
                            Text(lm.t("pearson.simulation.subtitle"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                        }
                        
                        // Live Canvas Card
                        VStack(spacing: 16) {
                            // The Canvas Graph
                            GeometryReader { geo in
                                let paths = generatePaths(r: demoCorrelation, size: geo.size)
                                ZStack {
                                    // Grid lines
                                    VStack {
                                        Spacer()
                                        Divider().background(Color.borderHair)
                                        Spacer()
                                        Divider().background(Color.borderHair)
                                        Spacer()
                                    }
                                    
                                    // Benchmark Path
                                    Path { path in
                                        guard !paths.benchmark.isEmpty else { return }
                                        path.move(to: paths.benchmark[0])
                                        for i in 1..<paths.benchmark.count {
                                            path.addLine(to: paths.benchmark[i])
                                        }
                                    }
                                    .stroke(Color.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                    
                                    // Portfolio Path
                                    Path { path in
                                        guard !paths.portfolio.isEmpty else { return }
                                        path.move(to: paths.portfolio[0])
                                        for i in 1..<paths.portfolio.count {
                                            path.addLine(to: paths.portfolio[i])
                                        }
                                    }
                                    .stroke(
                                        LinearGradient(
                                            colors: [correlationColor(demoCorrelation), correlationColor(demoCorrelation).opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                                    )
                                    .shadow(color: correlationColor(demoCorrelation).opacity(0.3), radius: 6, x: 0, y: 3)
                                }
                            }
                            .frame(height: 140)
                            .padding(.top, 8)
                            
                            // Legend
                            HStack(spacing: 24) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(correlationColor(demoCorrelation))
                                        .frame(width: 16, height: 3.5)
                                    Text(lm.t("pearson.simulation.portfolio"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                }
                                
                                HStack(spacing: 6) {
                                    // Dashed line representation
                                    HStack(spacing: 3) {
                                        ForEach(0..<3) { _ in
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(Color.textSecondary.opacity(0.6))
                                                .frame(width: 4, height: 2)
                                        }
                                    }
                                    Text(lm.t("pearson.simulation.benchmark"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            
                            // Interactive Slider and Value Display
                            VStack(spacing: 12) {
                                HStack {
                                    Text(lm.t("pearson.simulation.label"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                    Text(String(format: "%@%.2f", demoCorrelation >= 0 ? "+" : "", demoCorrelation))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundStyle(correlationColor(demoCorrelation))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(correlationColor(demoCorrelation).opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                
                                Slider(value: $demoCorrelation, in: -1.0...1.0, step: 0.05) {
                                    Text(lm.t("pearson.simulation.title"))
                                } minimumValueLabel: {
                                    Text("-1.0")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.textMuted)
                                } maximumValueLabel: {
                                    Text("+1.0")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.textMuted)
                                }
                                .tint(correlationColor(demoCorrelation))
                                .onChange(of: demoCorrelation) { _, _ in
                                    haptic(.light)
                                }
                                
                                Text(correlationSummaryText(demoCorrelation))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(correlationColor(demoCorrelation))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 4)
                            }
                        }
                        .cardStyle()
                        
                        // Educational Bands Scale (Correlation Spectrum Card)
                        VStack(alignment: .leading, spacing: 16) {
                            Text(lm.t("pearson.scale.title").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.2)
                            
                            VStack(alignment: .leading, spacing: 22) {
                                spectrumRow(title: lm.t("pearson.scale.perfectPositive.title"), color: Color.crimson, desc: lm.t("pearson.scale.perfectPositive.description"))
                                spectrumRow(title: lm.t("pearson.scale.strongPositive.title"), color: Color.crimson, desc: lm.t("pearson.scale.strongPositive.description"))
                                spectrumRow(title: lm.t("pearson.scale.moderatePositive.title"), color: Color.orange, desc: lm.t("pearson.scale.moderatePositive.description"))
                                spectrumRow(title: lm.t("pearson.scale.noCorrelation.title"), color: Color.jade, desc: lm.t("pearson.scale.noCorrelation.description"))
                                spectrumRow(title: lm.t("pearson.scale.moderateNegative.title"), color: Color.jade, desc: lm.t("pearson.scale.moderateNegative.description"))
                                spectrumRow(title: lm.t("pearson.scale.strongNegative.title"), color: Color.jade, desc: lm.t("pearson.scale.strongNegative.description"))
                                spectrumRow(title: lm.t("pearson.scale.perfectNegative.title"), color: Color.jade, desc: lm.t("pearson.scale.perfectNegative.description"))
                            }
                        }
                        .cardStyle()
                        
                        // Why it matters section
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lm.t("pearson.whyItMatters.title").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(1.0)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                bulletPoint(lm.t("pearson.whyItMatters.point1"))
                                bulletPoint(lm.t("pearson.whyItMatters.point2"))
                                bulletPoint(lm.t("pearson.whyItMatters.point3"))
                                bulletPoint(lm.t("pearson.whyItMatters.point4"))
                            }
                        }
                        
                        // Disclaimer Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.orange)
                                Text(lm.t("pearson.disclaimer.title").uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.orange)
                                    .tracking(1.0)
                            }
                            
                            Text(lm.t("pearson.disclaimer.text"))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.orange.opacity(0.15), lineWidth: 0.5)
                        )
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
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
            return Color.jade
        } else if r < 0.7 {
            return Color.orange
        } else {
            return Color.crimson
        }
    }
    
    private func correlationSummaryText(_ r: Double) -> String {
        if r >= 0.7 {
            return lm.t("pearson.summaries.high")
        } else if r >= 0.3 {
            return lm.t("pearson.summaries.moderate")
        } else if r >= -0.3 {
            return lm.t("pearson.summaries.weak")
        } else {
            return lm.t("pearson.summaries.inverse")
        }
    }
    
    @ViewBuilder
    private func spectrumRow(title: String, color: Color, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                
                if !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.jade)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
        }
    }
}
