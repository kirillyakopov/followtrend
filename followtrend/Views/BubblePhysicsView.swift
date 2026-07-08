//
//  BubblePhysicsView.swift
//  followtrend
//
//  Premium physics bubble cluster with:
//  - Staggered spawn from screen edges (calmer entry)
//  - Full no-overlap separation (repulsionPad = 1.05)
//  - Ultra-soft inelastic collisions
//  - Liquid pop-burst animation with particles
//  - Radial-gradient bubbles with top-left highlight + soft outer glow
//  - Tap → StockDetailView with "Pop Bubble" option
//

import SwiftUI

// MARK: - Bubble Physics View

struct BubblePhysicsView: View {

    @ObservedObject var vm: PortfolioViewModel
    var searchText: String = ""
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        drawBubbles(date: timeline.date, ctx: &ctx, canvasSize: size)
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
            .onChange(of: vm.expandedClusterID) { _, newId in
                if newId == nil {
                    engine.isTempExpanded = false
                }
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
                haptic(.rigid)
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
                    vm.dissolveCluster(id: vm.bubbleClusters[idx].id)
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
                ClusterAssetsSheet(particle: particle, vm: vm, engine: engine)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                    .environmentObject(lm)
            }
        }
    }

    // MARK: - Canvas Drawing

    private func drawBubbles(date: Date, ctx: inout GraphicsContext, canvasSize: CGSize) {
        if engine.canvasSize != canvasSize && canvasSize.width > 0 {
            engine.updateSize(canvasSize)
        }
        engine.tick(date: date)
        drawExpandedClusterConnections(ctx: &ctx)
        drawActiveBubbles(ctx: &ctx, canvasSize: canvasSize)
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

    private func drawActiveBubbles(ctx: inout GraphicsContext, canvasSize: CGSize) {
        for particle in engine.particles {
            var renderParticle = particle
            renderParticle.position = renderPosition(for: particle, canvasSize: canvasSize)

            if renderParticle.id == engine.expandedClusterID {
                var drawCtx = ctx
                drawCtx.opacity = max(0.05, 1.0 - engine.expansionProgress)
                drawSoftBubble(renderParticle, ctx: &drawCtx)
            } else {
                drawSoftBubble(renderParticle, ctx: &ctx)
            }
        }
    }

    private func renderPosition(for particle: BubbleParticle, canvasSize: CGSize) -> CGPoint {
        return particle.position
    }

    private func canSelectBubble(_ particle: BubbleParticle) -> Bool {
        guard !particle.isWatchlist else { return false }
        guard !StablecoinClassifier.isStablecoin(symbol: particle.symbol, name: particle.name ?? "") else { return false }
        return true
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
                isWatchlist: child.isWatchlist,
                name: child.name
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
            if dragID != nil { haptic(.light) }   // grab feedback
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
              let loc = drag?.startLocation else { return }

        if engine.isTempExpanded {
            if let tappedChild = engine.tempChildParticles.first(where: { distPt($0.currentPosition, loc) < $0.radius }) {
                if !vm.isBubbleSelectionModeActive {
                    vm.toggleBubbleSelectionMode()
                }
                if !vm.selectedBubbleSymbols.contains(tappedChild.symbol) {
                    vm.toggleBubbleSelection(for: tappedChild.symbol)
                }
                return
            }
        }

        guard let tapped = engine.particles.first(where: { distPt($0.position, loc) < $0.radius }),
              !tapped.isCluster,
              canSelectBubble(tapped) else {
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
        if engine.isTempExpanded {
            if let tappedChild = engine.tempChildParticles.first(where: { distPt($0.currentPosition, location) < $0.radius }) {
                vm.toggleBubbleSelection(for: tappedChild.symbol)
                return
            }
        }

        if let tapped = engine.particles.first(where: { distPt($0.position, location) < $0.radius }) {
            if !tapped.isCluster && canSelectBubble(tapped) {
                vm.toggleBubbleSelection(for: tapped.symbol)
            } else {
                haptic(.light)
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
        vm.expandedClusterID = nil
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
        let previewSymbols = tapped.clusterSymbols
        let previewChildren = vm.bubbleRenderSnapshot.baseParticles.filter {
            previewSymbols.contains($0.symbol)
        }

        var tempChildren: [TempChildParticle] = []
        for p in previewChildren {
            tempChildren.append(TempChildParticle(
                id: p.id,
                symbol: p.symbol,
                name: p.name ?? "",
                gain: p.gain,
                radius: p.radius,
                isWatchlist: p.isWatchlist
            ))
        }

        engine.tempChildParticles = tempChildren
        engine.expandedClusterID = tapped.id
        engine.isTempExpanded = true
        vm.expandedClusterID = UUID(uuidString: tapped.id)
    }

    // MARK: - Extracted Subviews

    private var multiSelectToolbar: some View {
        VStack {
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(vm.selectedBubbleSymbols.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.labelSecondary)
                        .padding(.horizontal, 4)

                    mergeSelectedButton
                    popSelectedButton

                    Button(action: {
                        vm.toggleBubbleSelectionMode()
                    }) {
                        Text(lm.t("common.fertig"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.bottom, 24)
        }
        .transition(
            .move(edge: .bottom)
                .combined(with: .opacity)
                .animation(.spring(response: 0.32, dampingFraction: 0.85))
        )
        .zIndex(10)
    }

    private var popSelectedButton: some View {
        Button(action: {
            vm.popSelectedBubbles()
        }) {
            HStack(spacing: 5) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                Text(lm.t("bubbles.popSelected"))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.lossText)
        }
        .buttonStyle(.glass)
        .tint(Color.lossBase)
        .buttonBorderShape(.capsule)
    }

    private var mergeSelectedButton: some View {
        Button(action: {
            vm.createClusterFromSelectedSymbols(vm.selectedBubbleSymbols)
        }) {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                Text(lm.t("bubbles.mergeSelected"))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.mintInk)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.mintAccent)
        .buttonBorderShape(.capsule)
        .disabled(vm.selectedBubbleSymbols.count < 2)
    }

    // MARK: - Bubble Drawing (radial gradient + top-left highlight + soft glow)

    private func drawSoftBubble(_ p: BubbleParticle, ctx: inout GraphicsContext) {
        let isPos     = p.gain >= 0
        let isNeutral = abs(p.gain) < 0.05
        let baseColor = p.isWatchlist ? Color.neutralFlat : (isNeutral ? Color.gray : (isPos ? Color.jade : Color.crimson))
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

            // Premium spring curve with soft overshoot (plain ease under Reduce Motion)
            let springVal = reduceMotion
                ? materializationProgress
                : 1.0 - exp(-7.0 * materializationProgress) * cos(1.5 * .pi * materializationProgress)
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

        // Dragged bubble scales up slightly (1.06) — feels responsive / alive
        if p.id == dragID && progress >= 1.0 {
            let ds: CGFloat = 1.06
            drawCtx.concatenate(
                CGAffineTransform(translationX: cx, y: cy)
                    .scaledBy(x: ds, y: ds)
                    .translatedBy(x: -cx, y: -cy)
            )
        }

        let isHighlighted = !searchText.isEmpty && (p.symbol.localizedCaseInsensitiveContains(searchText) || (p.name ?? "").localizedCaseInsensitiveContains(searchText))

        if isHighlighted {
            drawCtx.addFilter(.shadow(color: .white.opacity(0.8), radius: 8))
            drawCtx.addFilter(.shadow(color: .white.opacity(0.4), radius: 16))
        }

        if vm.isBubbleSelectionModeActive && !canSelectBubble(p) {
            drawCtx.opacity *= 0.55
        }

        if p.isCluster {
            drawClusterBubble(p, ctx: &drawCtx, baseColor: baseColor, scale: scale, textOpacity: textOpacity, glowOpacityFactor: glowOpacityFactor)
            return
        }

        let rect    = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let ellipse = Path(ellipseIn: rect)

        // ── Ghost (watchlist) bubble: transparent, dashed, no glow, no % ──
        if p.isWatchlist {
            drawCtx.fill(ellipse, with: .color(Color.white.opacity(0.025)))
            drawCtx.stroke(
                ellipse,
                with: .color(Color.labelSecondary.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            if textOpacity > 0.01 {
                var textCtx = drawCtx
                textCtx.opacity = textOpacity
                let symSize: CGFloat = max(10, r * 0.34)
                textCtx.draw(
                    Text(p.symbol)
                        .font(.system(size: symSize, weight: .bold))
                        .foregroundColor(Color.labelSecondary),
                    at: CGPoint(x: cx, y: cy)
                )
            }
            return
        }

        // Performance → colour language (mirrors the prototype's bubbleFace)
        let pct = Double(p.gain)
        let gf  = glowOpacityFactor

        let fillCenter: Color, fillMid: Color, fillOuter: Color
        let borderColor: Color, glowColor: Color, txtCol: Color
        let glowMul: CGFloat
        let glowAlpha: Double

        if pct > 1.5 {
            let a = min(0.30, 0.13 + abs(pct) / 240.0)
            fillCenter  = Color.mintAccent.opacity(a + 0.08)
            fillMid     = Color.mintAccent.opacity(a * 0.42)
            fillOuter   = Color.mintAccent.opacity(0.04)
            borderColor = Color.mintAccent.opacity(0.26)
            glowColor   = Color(hex: "#5ED69E"); glowAlpha = 0.40; glowMul = 0.80
            txtCol      = Color.gainTextBright                 // #DCF8EA
        } else if pct < -1.5 {
            let a = min(0.28, 0.12 + abs(pct) / 240.0)
            fillCenter  = Color.lossBase.opacity(a + 0.07)
            fillMid     = Color.lossBase.opacity(a * 0.42)
            fillOuter   = Color.lossBase.opacity(0.04)
            borderColor = Color.lossBase.opacity(0.24)
            glowColor   = Color(hex: "#D96A60"); glowAlpha = 0.32; glowMul = 0.70
            txtCol      = Color(hex: "#F8DFDB")
        } else {
            fillCenter  = Color.white.opacity(0.13)
            fillMid     = Color.white.opacity(0.05)
            fillOuter   = Color.white.opacity(0.02)
            borderColor = Color.white.opacity(0.15)
            glowColor   = Color.white; glowAlpha = 0.12; glowMul = 0.50
            txtCol      = Color(hex: "#ECECEE")
        }

        // Highlight offset at 32% / 28% → light from top-left, 3D sphere feel
        let hlCenter = CGPoint(x: cx - r * 0.36, y: cy - r * 0.44)

        // ── 1. Soft outer glow (peaks at rim, fades outward) ──────────────
        let outer = r + r * glowMul
        drawCtx.fill(
            Path(ellipseIn: CGRect(x: cx - outer, y: cy - outer, width: outer * 2, height: outer * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: glowColor.opacity(glowAlpha * 0.55 * 0.5 * gf), location: 0.0),
                    .init(color: glowColor.opacity(glowAlpha * 0.55 * gf),       location: r / outer),
                    .init(color: .clear,                                          location: 1.0)
                ]),
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: outer
            )
        )

        // ── 2. Radial body fill (highlight at 32/28) ──────────────────────
        drawCtx.fill(ellipse, with: .radialGradient(
            Gradient(stops: [
                .init(color: fillCenter, location: 0.0),
                .init(color: fillMid,    location: 0.52),
                .init(color: fillOuter,  location: 1.0)
            ]),
            center: hlCenter,
            startRadius: 0,
            endRadius: r * 1.35
        ))

        // ── 3. Glossy specular spot ───────────────────────────────────────
        let spotR = r * 0.55
        drawCtx.fill(
            Path(ellipseIn: CGRect(x: hlCenter.x - spotR, y: hlCenter.y - spotR, width: spotR * 2, height: spotR * 2)),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.10), .clear]),
                center: hlCenter,
                startRadius: 0,
                endRadius: spotR
            )
        )

        // ── 4. Border ─────────────────────────────────────────────────────
        let selected = vm.isBubbleSelectionModeActive && canSelectBubble(p) && vm.selectedBubbleSymbols.contains(p.symbol)
        drawCtx.stroke(ellipse, with: .color(selected ? Color.mintAccent.opacity(0.7) : borderColor), lineWidth: 1)

        // ── 5. Selection ring (0 0 0 3px mint 0.5) ────────────────────────
        if selected {
            let rr = r + 1.5
            drawCtx.stroke(
                Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                with: .color(Color.mintAccent.opacity(0.5)),
                lineWidth: 3
            )
        }

        // ── 6. Labels: ticker (heavy) + return % (tabular) ────────────────
        if textOpacity > 0.01 {
            var textCtx = drawCtx
            textCtx.opacity = textOpacity

            let symSize: CGFloat = max(10, r * 0.32)
            textCtx.draw(
                Text(p.symbol)
                    .font(.system(size: symSize, weight: .heavy))
                    .foregroundColor(txtCol),
                at: CGPoint(x: cx, y: cy - symSize * 0.52)
            )

            let gainStr  = String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
            let gainSize: CGFloat = max(8, r * 0.24)
            textCtx.draw(
                Text(gainStr)
                    .font(.system(size: gainSize, weight: .semibold).monospacedDigit())
                    .foregroundColor(txtCol.opacity(0.92)),
                at: CGPoint(x: cx, y: cy + symSize * 0.66)
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
