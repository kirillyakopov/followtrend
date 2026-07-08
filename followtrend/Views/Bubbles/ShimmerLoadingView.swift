//
//  ShimmerLoadingView.swift
//  followtrend
//

import SwiftUI

struct ShimmerLoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 140, height: 140)
                .blur(radius: 40)
                .scaleEffect(pulse ? 1.15 : 0.85)
                .opacity(pulse ? 0.8 : 0.4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }
}
