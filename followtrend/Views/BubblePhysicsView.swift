//
//  BubblePhysicsView.swift
//  followtrend
//
//  Premium physics bubble cluster with:
//  - Staggered spawn from screen edges (calmer entry)
//  - Full no-overlap separation (repulsionPad = 1.05)
//  - Ultra-soft inelastic collisions
//  - Liquid pop-burst animation with particles
//  - Soft ambient glow — no specular blink, no neon ring
//  - Tap → StockDetailView with "Pop Bubble" option
//

import SwiftUI

// MARK: - Bubble Physics View

struct BubblePhysicsView: View {

    @ObservedObject var vm: PortfolioViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @StateObject private var engine = BubblePhysicsEngine()

    @State private var dragID:            String?
    @State private var selectedInvestment: Investment?
    @State private var pendingPopID:       String?   // ID of bubble waiting to pop

    // Bubble Merge additions
    @State private var selectedClusterParticle: BubbleParticle? = nil
    @State private var showClusterActionSheet: Bool = false
    @State private var showClusterAssetsSheet: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !engine.isLayoutReady {
                    ShimmerLoadingView()
                }
                
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        drawBubbles(date: timeline.date, ctx: &ctx)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged(handleDragChanged)
                            .onEnded(handleDragEnded)
                    )
                    .onTapGesture { handleTap(at: $0, canvasSize: geo.size) }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded(handleLongPressEnded)
                    )
                } // End TimelineView
                .opacity(engine.isLayoutReady ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.3), value: engine.isLayoutReady)
                
                // Multi-Select Toolbar
                if vm.isBubbleSelectionModeActive {
                    multiSelectToolbar
                }
            }
            .onAppear {
                vm.prepareBubblesIfNeeded()
                vm.rebuildBubbleSnapshot(in: geo.size)
                engine.sync(particles: vm.bubbleRenderSnapshot.particles, in: geo.size)
                engine.correlationMatrix = vm.correlationMatrix
            }
            .onChange(of: geo.size) { _, s in
                engine.updateSize(s)
                vm.rebuildBubbleSnapshot(in: s)
                engine.sync(particles: vm.bubbleRenderSnapshot.particles, in: s)
            }
            .onChange(of: vm.bubbleRenderSnapshot) { _, snapshot in
                engine.sync(particles: snapshot.particles, in: geo.size)
            }
            .onChange(of: vm.correlationMatrix) { _, matrix in
                engine.correlationMatrix = matrix
            }
        }
        // Detail sheet — passes onPop, onDelete, and onBuy
        .sheet(item: $selectedInvestment) { inv in
            StockDetailView(
                investment: inv,
                coinId:     inv.coinId,
                priceSourceMode: vm.priceSourceMode,
                onDelete: {
                    vm.removeInvestment(id: inv.id)
                    selectedInvestment = nil
                },
                onPop: {
                    pendingPopID       = inv.id
                    selectedInvestment = nil   // dismiss sheet → triggers onChange below
                },
                onBuy: { shares, price, date in
                    vm.buyWatchlistItem(id: inv.id, shares: shares, price: price, date: date)
                    selectedInvestment = nil
                },
                onEdit: { shares, price, date, notes, tags, brokerDraft, clearsBrokerAdjustment in
                    vm.updateInvestment(id: inv.id, shares: shares, buyPrice: price, buyDate: date, notes: notes, tags: tags, brokerAdjustment: brokerDraft, clearsBrokerAdjustment: clearsBrokerAdjustment)
                    selectedInvestment = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // After sheet dismisses, check if a pop was requested
        .onChange(of: selectedInvestment) { _, newVal in
            guard newVal == nil, let id = pendingPopID else { return }
            // Small delay for sheet dismissal animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                engine.popBubble(id: id)
                // Delete investment after pop animation finishes (~0.85s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    vm.deleteInvestment(id: id)
                    pendingPopID = nil
                }
            }
        }
        .confirmationDialog(
            selectedClusterParticle?.symbol ?? "",
            isPresented: $showClusterActionSheet,
            presenting: selectedClusterParticle
        ) { particle in
            Button(lm.t("bubbles.dissolveCluster")) {
                if let idx = vm.bubbleClusters.firstIndex(where: { $0.id.uuidString == particle.id }) {
                    engine.prepareForExpansion(clusterId: particle.id, position: particle.position, velocity: particle.velocity, symbols: particle.clusterSymbols)
                    vm.expandCluster(id: vm.bubbleClusters[idx].id)
                }
                selectedClusterParticle = nil
            }
            Button(lm.t("bubbles.viewAssets")) {
                showClusterAssetsSheet = true
            }
            Button(lm.t("add.abbrechen"), role: .cancel) {
                selectedClusterParticle = nil
            }
        }
        .sheet(isPresented: $showClusterAssetsSheet, onDismiss: { selectedClusterParticle = nil }) {
            if let particle = selectedClusterParticle {
                ClusterAssetsSheet(particle: particle, vm: vm)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                    .environmentObject(lm)
            }
        }
    }

    // MARK: - Canvas Drawing

    private func drawBubbles(date: Date, ctx: inout GraphicsContext) {
        engine.tick(date: date)
        drawExpandedClusterConnections(ctx: &ctx)
        drawActiveBubbles(ctx: &ctx)
        drawTemporaryChildren(ctx: &ctx)
        drawMergingBubbles(ctx: &ctx)

        for pop in engine.pops {
            drawPop(pop, ctx: &ctx)
        }
    }

    private func drawExpandedClusterConnections(ctx: inout GraphicsContext) {
        guard engine.expansionProgress > 0,
              let centerId = engine.expandedClusterID,
              let centerParticle = engine.particles.first(where: { $0.id == centerId }) else {
            return
        }

        for child in engine.tempChildParticles {
            var path = Path()
            path.move(to: centerParticle.position)
            path.addLine(to: child.currentPosition)
            ctx.stroke(
                path,
                with: .color(Color.jade.opacity(0.18 * engine.expansionProgress)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
        }
    }

    private func drawActiveBubbles(ctx: inout GraphicsContext) {
        for particle in engine.particles {
            if particle.id == engine.expandedClusterID {
                var drawCtx = ctx
                drawCtx.opacity = max(0.05, 1.0 - engine.expansionProgress)
                drawSoftBubble(particle, ctx: &drawCtx)
            } else {
                drawSoftBubble(particle, ctx: &ctx)
            }
        }
    }

    private func drawTemporaryChildren(ctx: inout GraphicsContext) {
        guard engine.expansionProgress > 0 else { return }

        for child in engine.tempChildParticles {
            let tempParticle = BubbleParticle(
                id: child.id,
                symbol: child.symbol,
                gain: child.gain,
                radius: child.radius * engine.expansionProgress,
                position: child.currentPosition,
                velocity: .zero,
                isWatchlist: child.isWatchlist
            )
            var drawCtx = ctx
            drawCtx.opacity = engine.expansionProgress
            drawSoftBubble(tempParticle, ctx: &drawCtx)
        }
    }

    private func drawMergingBubbles(ctx: inout GraphicsContext) {
        for particle in engine.mergingParticles {
            let tempParticle = BubbleParticle(
                id: particle.id,
                symbol: particle.symbol,
                gain: 0.0,
                radius: particle.radius,
                position: particle.position,
                velocity: .zero,
                isWatchlist: false
            )
            var drawCtx = ctx
            drawCtx.opacity = particle.opacity
            drawSoftBubble(tempParticle, ctx: &drawCtx)
        }
    }

    // MARK: - Gestures

    private func handleDragChanged(_ value: DragGesture.Value) {
        if dragID == nil {
            dragID = engine.particles.first { distPt($0.position, value.startLocation) < $0.radius }?.id
        }
        if let id = dragID {
            engine.drag(id: id, to: value.location)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        dragID = nil
    }

    private func handleLongPressEnded(_ value: SequenceGesture<LongPressGesture, DragGesture>.Value) {
        guard case .second(true, let drag) = value,
              let loc = drag?.startLocation,
              let tapped = engine.particles.first(where: { distPt($0.position, loc) < $0.radius }),
              !tapped.isCluster,
              !tapped.isWatchlist else {
            return
        }

        if !vm.isBubbleSelectionModeActive {
            vm.toggleBubbleSelectionMode()
        }
        if !vm.selectedBubbleSymbols.contains(tapped.symbol) {
            vm.toggleBubbleSelection(for: tapped.symbol)
        }
    }

    private func handleTap(at location: CGPoint, canvasSize: CGSize) {
        guard dragID == nil else { return }

        if vm.isBubbleSelectionModeActive {
            handleSelectionModeTap(at: location)
            return
        }

        if engine.isTempExpanded {
            handleExpandedTap(at: location)
            return
        }

        guard let tapped = engine.particles.first(where: { distPt($0.position, location) < $0.radius }) else { return }
        haptic(.medium)

        if tapped.isCluster {
            haptic(.rigid)
            expandClusterPreview(tapped, canvasSize: canvasSize)
        } else if let inv = vm.investments.first(where: { $0.id == tapped.id }) {
            selectedInvestment = inv
        }
    }

    private func handleSelectionModeTap(at location: CGPoint) {
        if let tapped = engine.particles.first(where: { distPt($0.position, location) < $0.radius }) {
            if !tapped.isCluster && !tapped.isWatchlist {
                vm.toggleBubbleSelection(for: tapped.symbol)
            }
        } else {
            vm.toggleBubbleSelectionMode()
        }
    }

    private func handleExpandedTap(at location: CGPoint) {
        if let tappedChild = engine.tempChildParticles.first(where: { distPt($0.currentPosition, location) < $0.radius }) {
            haptic(.medium)
            selectedInvestment = vm.investments.first(where: { $0.id == tappedChild.id })
            return
        }

        guard let centerId = engine.expandedClusterID else { return }

        if let centerParticle = engine.particles.first(where: { $0.id == centerId }),
           distPt(centerParticle.position, location) < centerParticle.radius {
            haptic(.medium)
            presentClusterAssetsSheet(centerId: centerId, centerParticle: centerParticle)
            return
        }

        haptic(.light)
        engine.isTempExpanded = false
    }

    private func presentClusterAssetsSheet(centerId: String, centerParticle: BubbleParticle) {
        guard let cluster = vm.bubbleClusters.first(where: { $0.id.uuidString == centerId }) else { return }
        selectedClusterParticle = BubbleParticle(
            id: cluster.id.uuidString,
            symbol: cluster.name,
            gain: centerParticle.gain,
            radius: centerParticle.radius,
            position: centerParticle.position,
            velocity: .zero,
            isWatchlist: false,
            isCluster: true,
            clusterSymbols: cluster.symbols
        )
        showClusterAssetsSheet = true
    }

    private func expandClusterPreview(_ tapped: BubbleParticle, canvasSize: CGSize) {
        var tempChildren: [TempChildParticle] = []
        let activeInvestments = vm.investments.filter { !$0.isWatchlist }
        let totalActiveVal = activeInvestments.reduce(0.0) {
            $0 + vm.selectedCurrencyValue(for: $1)
        }
        let maxR = min(canvasSize.width, canvasSize.height) * 0.22
        let minR: CGFloat = 28

        for symbol in tapped.clusterSymbols {
            guard let inv = vm.investments.first(where: { $0.symbol == symbol }) else { continue }
            let value = vm.selectedCurrencyValue(for: inv)
            let cost = vm.selectedCurrencyCost(for: inv)
            let weight = totalActiveVal > 0 ? value / totalActiveVal : 0.0
            let childR = minR + (maxR - minR) * CGFloat(weight)
            let gain = cost > 0 ? ((value - cost) / cost) * 100 : 0.0

            tempChildren.append(TempChildParticle(
                id: inv.id,
                symbol: inv.symbol,
                name: inv.name,
                gain: gain,
                radius: childR,
                isWatchlist: false
            ))
        }

        engine.tempChildParticles = tempChildren
        engine.expandedClusterID = tapped.id
        engine.isTempExpanded = true
    }

    // MARK: - Extracted Subviews

    private var multiSelectToolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                popSelectedButton
                mergeSelectedButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.bgCard.opacity(0.8))
            .background(Material.ultraThin)
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(10)
    }

    private var popSelectedButton: some View {
        Button(action: {
            vm.popSelectedBubbles()
        }) {
            HStack {
                Image(systemName: "trash.fill")
                Text(lm.t("bubbles.popSelected"))
            }
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.crimson.opacity(0.15))
            .foregroundColor(.crimson)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.crimson.opacity(0.3), lineWidth: 1))
        }
    }

    private var mergeSelectedButton: some View {
        Button(action: {
            let name = lm.t("bubbles.customCluster")
            vm.mergeSelectedBubbles(name: name, type: .correlation)
        }) {
            HStack {
                Image(systemName: "link.circle.fill")
                Text(lm.t("bubbles.mergeSelected"))
            }
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.jade.opacity(0.15))
            .foregroundColor(.jade)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.jade.opacity(0.3), lineWidth: 1))
        }
        .disabled(vm.selectedBubbleSymbols.count < 2)
        .opacity(vm.selectedBubbleSymbols.count < 2 ? 0.5 : 1.0)
    }

    // MARK: - Soft Ambient Bubble Drawing (no blink, no neon ring)

    private func drawSoftBubble(_ p: BubbleParticle, ctx: inout GraphicsContext) {
        let isPos     = p.gain >= 0
        let isNeutral = abs(p.gain) < 0.05
        let baseColor = p.isWatchlist ? Color(hex: "#6366f1") : (isNeutral ? Color.gray : (isPos ? Color.jade : Color.crimson))
        let r         = p.radius
        let cx        = p.position.x
        let cy        = p.position.y

        // ── Spawn Animation (Scale, Fade, Blur) ─────────────────────────
        let progress = p.spawnProgress
        
        var drawCtx = ctx
        let scale: CGFloat
        let bodyOpacity: Double
        let glowOpacityFactor: Double
        let textOpacity: Double
        
        if progress < 1.0 {
            // Materialization animates over the first 0.5s of the progress (0.0 to 0.5)
            let materializationProgress = min(1.0, progress / 0.5)
            
            // Premium spring curve with soft overshoot
            let springVal = 1.0 - exp(-7.0 * materializationProgress) * cos(1.5 * .pi * materializationProgress)
            scale = CGFloat(0.70 + springVal * 0.30)
            bodyOpacity = max(0.0, min(1.0, springVal))
            
            // Glow appears first
            glowOpacityFactor = min(1.0, materializationProgress / 0.3)
            
            // Text is delayed by ~0.15s (which is 0.3 of materialization progress)
            textOpacity = max(0.0, min(1.0, (materializationProgress - 0.3) / 0.7))
            
            // Slight blur: starts at 4.0, fades to 0
            let blurRadius = (1.0 - materializationProgress) * 4.0
            if blurRadius > 0.1 {
                drawCtx.addFilter(.blur(radius: blurRadius))
            }
            
            // Apply scale transform around bubble center
            let transform = CGAffineTransform(translationX: cx, y: cy)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -cx, y: -cy)
            drawCtx.concatenate(transform)
            drawCtx.opacity = bodyOpacity
        } else {
            scale = 1.0
            bodyOpacity = 1.0
            glowOpacityFactor = 1.0
            textOpacity = 1.0
        }

        if p.isCluster {
            drawClusterBubble(p, ctx: &drawCtx, baseColor: baseColor, scale: scale, textOpacity: textOpacity, glowOpacityFactor: glowOpacityFactor)
            return
        }

        let rect    = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let ellipse = Path(ellipseIn: rect)

        // ── 1. Wide soft ambient glow (radial gradient falloff) ───────────
        let startGlow = r * 0.95
        let endGlow   = r * 1.28
        let glowRect  = CGRect(x: cx - endGlow, y: cy - endGlow, width: endGlow * 2, height: endGlow * 2)
        let baseGlowOpacity = p.isWatchlist ? 0.08 : 0.12
        let secondaryGlowOpacity = p.isWatchlist ? 0.02 : 0.04
        
        let glowGradient = Gradient(stops: [
            .init(color: baseColor.opacity(baseGlowOpacity * glowOpacityFactor), location: 0.0),
            .init(color: baseColor.opacity(secondaryGlowOpacity * glowOpacityFactor), location: 0.4),
            .init(color: .clear, location: 1.0)
        ])
        drawCtx.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                glowGradient,
                center: CGPoint(x: cx, y: cy),
                startRadius: startGlow,
                endRadius: endGlow
            )
        )

        // ── 2. Radial glass fill (near-clear centre → soft tinted rim) ───
        drawCtx.fill(ellipse, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.010),  location: 0.0),
                .init(color: baseColor.opacity(p.isWatchlist ? 0.035 : 0.055),    location: 0.60),
                .init(color: baseColor.opacity(p.isWatchlist ? 0.08 : 0.13),     location: 1.0)
            ]),
            center: CGPoint(x: cx, y: cy),
            startRadius: 0,
            endRadius: r
        ))

        // ── 3. Frosted inner border (very subtle / dashed for watchlist) ─
        if p.isWatchlist {
            drawCtx.stroke(ellipse, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [4, 4]))
        } else {
            drawCtx.stroke(ellipse, with: .color(Color.white.opacity(0.13)), lineWidth: 0.95)
        }
        
        // ── Selection Ring ────────────────────────────────────────────────
        if vm.isBubbleSelectionModeActive && vm.selectedBubbleSymbols.contains(p.symbol) {
            let selectionRect = CGRect(x: cx - r - 4, y: cy - r - 4, width: (r + 4) * 2, height: (r + 4) * 2)
            drawCtx.stroke(Path(ellipseIn: selectionRect), with: .color(Color.jade.opacity(0.85)), lineWidth: 3.0)
        }

        // ── 4. Symbol and Gain labels (with delayed materialization) ──────
        if textOpacity > 0.01 {
            var textCtx = drawCtx
            textCtx.opacity = textOpacity
            
            let symSize: CGFloat = max(11, r * 0.33)
            textCtx.draw(
                Text(p.symbol)
                    .font(.system(size: symSize, weight: .bold))
                    .foregroundColor(.white.opacity(0.90)),
                at: CGPoint(x: cx, y: cy - symSize * 0.52)
            )

            let gainStr  = String(format: "%@%.1f%%", isPos ? "+" : "", p.gain)
            let gainSize: CGFloat = max(8, r * 0.24)
            
            let textColor: Color
            if p.isWatchlist {
                textColor = isPos ? Color(hex: "#818cf8") : Color(hex: "#f43f5e")
            } else {
                textColor = isNeutral ? Color.textSecondary : (isPos ? Color.jade : Color.crimson)
            }

            textCtx.draw(
                Text(gainStr)
                    .font(.system(size: gainSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor),
                at: CGPoint(x: cx, y: cy + symSize * 0.68)
            )
        }
    }

    private func drawClusterBubble(_ p: BubbleParticle, ctx: inout GraphicsContext, baseColor: Color, scale: CGFloat, textOpacity: Double, glowOpacityFactor: Double) {
        let r  = p.radius
        let cx = p.position.x
        let cy = p.position.y
        
        let rect    = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let ellipse = Path(ellipseIn: rect)
        
        // 1. Wide soft ambient glow
        let endGlow   = r * 1.35
        let glowRect  = CGRect(x: cx - endGlow, y: cy - endGlow, width: endGlow * 2, height: endGlow * 2)
        let glowGradient = Gradient(stops: [
            .init(color: baseColor.opacity(0.18 * glowOpacityFactor), location: 0.0),
            .init(color: baseColor.opacity(0.04 * glowOpacityFactor), location: 0.5),
            .init(color: .clear, location: 1.0)
        ])
        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                glowGradient,
                center: CGPoint(x: cx, y: cy),
                startRadius: r * 0.9,
                endRadius: endGlow
            )
        )
        
        // 2. Layered look: background offset path (shadow orb)
        let offset1 = r * 0.08
        let layerRect1 = CGRect(x: cx - r + offset1, y: cy - r + offset1, width: r * 1.85, height: r * 1.85)
        ctx.fill(Path(ellipseIn: layerRect1), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.005), location: 0.0),
                .init(color: baseColor.opacity(0.04), location: 0.6),
                .init(color: baseColor.opacity(0.09), location: 1.0)
            ]),
            center: CGPoint(x: cx + offset1, y: cy + offset1),
            startRadius: 0,
            endRadius: r * 0.9
        ))
        ctx.stroke(Path(ellipseIn: layerRect1), with: .color(Color.white.opacity(0.07)), lineWidth: 0.8)
        
        // 3. Main Glass Fill
        ctx.fill(ellipse, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.012),  location: 0.0),
                .init(color: baseColor.opacity(0.065),    location: 0.60),
                .init(color: baseColor.opacity(0.16),     location: 1.0)
            ]),
            center: CGPoint(x: cx - r * 0.1, y: cy - r * 0.1),
            startRadius: 0,
            endRadius: r
        ))
        
        // 4. Subtle multi-orb reflection (highlight orb)
        let offset2 = -r * 0.15
        let layerRect2 = CGRect(x: cx + offset2, y: cy + offset2, width: r * 0.5, height: r * 0.5)
        ctx.fill(Path(ellipseIn: layerRect2), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.20), location: 0.0),
                .init(color: Color.white.opacity(0.01), location: 1.0)
            ]),
            center: CGPoint(x: cx + offset2 + r * 0.25, y: cy + offset2 + r * 0.25),
            startRadius: 0,
            endRadius: r * 0.25
        ))
        
        // 5. Border
        ctx.stroke(ellipse, with: .color(Color.white.opacity(0.20)), lineWidth: 1.0)
        
        // 6. Text Labels
        if textOpacity > 0.01 {
            var textCtx = ctx
            textCtx.opacity = textOpacity
            
            let nameSize: CGFloat = max(11, r * 0.20)
            textCtx.draw(
                Text(p.symbol)
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundColor(.white.opacity(0.95)),
                at: CGPoint(x: cx, y: cy - r * 0.32)
            )
            
            let countSize: CGFloat = max(8, r * 0.15)
            textCtx.draw(
                Text(p.assetsCountText)
                    .font(.system(size: countSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.60)),
                at: CGPoint(x: cx, y: cy)
            )
            
            let valSize: CGFloat = max(9, r * 0.17)
            let isPos = p.gain >= 0
            let textColor = isPos ? Color.jade : Color.crimson
            textCtx.draw(
                Text(p.combinedValueText)
                    .font(.system(size: valSize, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor),
                at: CGPoint(x: cx, y: cy + r * 0.35)
            )
        }
    }

    // MARK: - Pop Burst Animation Drawing

    private func drawPop(_ pop: BubblePop, ctx: inout GraphicsContext) {
        let base = pop.baseColor

        // Fading main bubble (slight expand)
        if pop.mainOpacity > 0.01 {
            let r    = pop.mainRadius
            let rect = CGRect(x: pop.cx - r, y: pop.cy - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(base.opacity(pop.mainOpacity * 0.10)))
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(Color.white.opacity(pop.mainOpacity * 0.18)),
                       lineWidth: 0.6)
        }

        // Flying liquid droplets
        for particle in pop.particles where particle.opacity > 0.02 {
            let r    = particle.radius
            let rect = CGRect(x: particle.x - r, y: particle.y - r, width: r * 2, height: r * 2)

            // Droplet body
            ctx.fill(Path(ellipseIn: rect), with: .color(base.opacity(particle.opacity * 0.80)))

            // Soft glow halo around each droplet
            let gr   = r * 1.6
            let grect = CGRect(x: particle.x - gr, y: particle.y - gr, width: gr * 2, height: gr * 2)
            ctx.fill(Path(ellipseIn: grect), with: .color(base.opacity(particle.opacity * 0.12)))
        }
    }

    // MARK: - Helpers

    private func distPt(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
