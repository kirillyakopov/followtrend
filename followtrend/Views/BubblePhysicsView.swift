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
import Combine

// MARK: - Pop Particle

fileprivate struct PopParticle {
    var x:  CGFloat
    var y:  CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var opacity: Double
    var radius:  CGFloat
}

// MARK: - Bubble Pop State

fileprivate struct BubblePop {
    let baseColor:   Color
    var cx:          CGFloat
    var cy:          CGFloat
    var mainRadius:  CGFloat
    var mainOpacity: Double
    var particles:   [PopParticle]
    var tick:        Int = 0
    static let maxTicks = 52
}

// MARK: - Merging Particle (visual transition)

struct MergingParticle: Identifiable {
    let id: String
    let symbol: String
    var position: CGPoint
    let targetPosition: CGPoint
    var radius: CGFloat
    var opacity: Double
    let baseColor: Color
}

// MARK: - Temp Child Particle (temporary cluster expand preview)

struct TempChildParticle: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let gain: Double
    let radius: CGFloat
    let isWatchlist: Bool
    var currentPosition: CGPoint = .zero
}

// MARK: - Physics Engine

@MainActor
final class BubblePhysicsEngine: ObservableObject {

    var particles: [BubbleParticle] = []
    fileprivate var pops: [BubblePop] = []
    var mergingParticles: [MergingParticle] = []
    private var expandedClusterPositions: [String: (position: CGPoint, velocity: CGVector)] = [:]
    
    // Temporary expansion preview state
    var tempChildParticles: [TempChildParticle] = []
    var expandedClusterID: String? = nil
    var isTempExpanded: Bool = false
    var expansionProgress: Double = 0.0

    private var canvasSize: CGSize = .zero
    private var tickCount:   Double = 0

    // Correlation matrix injected from PortfolioViewModel
    var correlationMatrix: [AssetPair: Double] = [:]

    @Published var isLayoutReady: Bool = false

    // ── Tuning — calm, floaty, never stuck ────────────────────────────────
    private let gravity:              CGFloat = 0.0025   // gentle centre pull
    private let damping:              CGFloat = 0.94     // strong deceleration for quick settle
    private let collisionRestitution: CGFloat = 0.03     // 97% absorbed — ultra soft rebounds
    private let boundaryBounce:       CGFloat = 0.02     // near-frictionless wall
    private let repulsionPad:         CGFloat = 1.08     // 8% margin — stable no overlap spacing
    private let driftAmplitude:       CGFloat = 0.005    // extremely subtle drift (no spinning)
    private let idleDrift:            CGFloat = 0.0008   // static-like float after settle
    // α scalar for correlation force: keeps forces gentle and frame-rate friendly
    private let correlationAlpha:     CGFloat = 0.0018
    private var spawnTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func sync(particles newParticles: [BubbleParticle], in size: CGSize) {
        canvasSize = size
        tickCount  = 0
        spawnTask?.cancel()
        
        let cx = size.width / 2
        let cy = size.height / 2
        let oldParticles = particles
        let newIds = Set(newParticles.map { $0.id })
        
        // Remove ones that were deleted externally (if not popped)
        particles.removeAll { !newIds.contains($0.id) }
        
        var syncedParticles: [BubbleParticle] = []
        var added: [BubbleParticle] = []
        
        for var p in newParticles {
            if let idx = particles.firstIndex(where: { $0.id == p.id }) {
                var existing = particles[idx]
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    existing.radius = p.radius
                    existing.gain = p.gain
                    existing.isWatchlist = p.isWatchlist
                    existing.isCluster = p.isCluster
                    existing.clusterSymbols = p.clusterSymbols
                    existing.combinedValueText = p.combinedValueText
                    existing.assetsCountText = p.assetsCountText
                }
                syncedParticles.append(existing)
            } else {
                if p.isCluster {
                    // Merged cluster!
                    // Find individual particles in oldParticles that are being merged
                    let oldInvolved = oldParticles.filter { p.clusterSymbols.contains($0.symbol) }
                    
                    let midpoint: CGPoint
                    let avgVelocity: CGVector
                    if !oldInvolved.isEmpty {
                        let sumX = oldInvolved.reduce(0.0) { $0 + $1.position.x * $1.radius }
                        let sumY = oldInvolved.reduce(0.0) { $0 + $1.position.y * $1.radius }
                        let sumR = oldInvolved.reduce(0.0) { $0 + $1.radius }
                        midpoint = sumR > 0 ? CGPoint(x: sumX / sumR, y: sumY / sumR) : CGPoint(x: cx, y: cy)
                        
                        let sumVx = oldInvolved.reduce(0.0) { $0 + $1.velocity.dx }
                        let sumVy = oldInvolved.reduce(0.0) { $0 + $1.velocity.dy }
                        avgVelocity = CGVector(dx: sumVx / CGFloat(oldInvolved.count), dy: sumVy / CGFloat(oldInvolved.count))
                    } else {
                        midpoint = CGPoint(x: cx, y: cy)
                        avgVelocity = .zero
                    }
                    
                    // Add old particles to mergingParticles for animation
                    for oldP in oldInvolved {
                        let isPos = oldP.gain >= 0
                        let isNeutral = abs(oldP.gain) < 0.05
                        let baseColor = oldP.isWatchlist ? Color(hex: "#6366f1") : (isNeutral ? Color.gray : (isPos ? Color.jade : Color.crimson))
                        
                        self.mergingParticles.append(MergingParticle(
                            id: oldP.id,
                            symbol: oldP.symbol,
                            position: oldP.position,
                            targetPosition: midpoint,
                            radius: oldP.radius,
                            opacity: 1.0,
                            baseColor: baseColor
                        ))
                    }
                    
                    p.position = midpoint
                    p.velocity = avgVelocity
                    p.spawnState = .spawning
                    p.spawnProgress = 0.0
                    syncedParticles.append(p)
                } else if let cached = expandedClusterPositions[p.symbol] {
                    // Expanded child! Initialize at cluster's last position
                    let angle = CGFloat.random(in: 0...(2 * .pi))
                    let speed = CGFloat.random(in: 0.8...1.5)
                    p.position = cached.position
                    p.velocity = CGVector(
                        dx: cached.velocity.dx + cos(angle) * speed,
                        dy: cached.velocity.dy + sin(angle) * speed
                    )
                    p.spawnState = .spawning
                    p.spawnProgress = 0.0
                    syncedParticles.append(p)
                    expandedClusterPositions.removeValue(forKey: p.symbol)
                } else {
                    added.append(p)
                }
            }
        }
        
        // Fix Dissolve Bug: Reset temp expansion if the expanded cluster is no longer in the snapshot
        if let expId = expandedClusterID, !syncedParticles.contains(where: { $0.id == expId }) {
            isTempExpanded = false
            expandedClusterID = nil
            tempChildParticles.removeAll()
        }
        
        self.particles = syncedParticles
        
        guard !added.isEmpty else { return }

        // Find threshold for large bubbles (top size or at least 55 radius)
        let maxR = newParticles.map { $0.radius }.max() ?? 0
        let largeThreshold = max(55.0, maxR * 0.75)
        
        if particles.isEmpty && !isLayoutReady {
            // First initialization: pre-layout everything
            var initialParticles: [BubbleParticle] = []
            
            for var p in added {
                let isLarge = p.radius >= largeThreshold
                if isLarge {
                    // Place near center, fully active, no scale-in birth animation
                    let offsetRange: CGFloat = 20.0
                    p.position = CGPoint(
                        x: cx + CGFloat.random(in: -offsetRange...offsetRange),
                        y: cy + CGFloat.random(in: -offsetRange...offsetRange)
                    )
                    p.velocity = .zero
                    p.spawnState = .active
                    p.spawnProgress = 1.0
                } else {
                    // Place off-screen for small/medium bubbles
                    let margin: CGFloat = p.radius + 8
                    let side = Int.random(in: 0..<4)
                    switch side {
                    case 0: p.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: -margin)
                    case 1: p.position = CGPoint(x: size.width + margin, y: CGFloat.random(in: margin...(size.height - margin)))
                    case 2: p.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: size.height + margin)
                    default: p.position = CGPoint(x: -margin, y: CGFloat.random(in: margin...(size.height - margin)))
                    }
                    
                    let ddx = cx - p.position.x, ddy = cy - p.position.y
                    let d   = max(sqrt(ddx * ddx + ddy * ddy), 1)
                    p.velocity = CGVector(dx: ddx / d * 1.5, dy: ddy / d * 1.5)
                    p.spawnState = .spawning
                    p.spawnProgress = 0.0
                }
                initialParticles.append(p)
            }
            
            self.particles = initialParticles
            
            // Run 5 invisible stabilization ticks to resolve initial overlaps and rest points
            for _ in 0..<5 {
                self.tick(date: Date())
            }
            
            // Mark layout as ready
            self.isLayoutReady = true
        } else {
            // Subsequent additions
            spawnTask = Task { @MainActor in
                for var p in added {
                    guard !Task.isCancelled else { break }

                    let margin: CGFloat = p.radius + 8
                    let side = Int.random(in: 0..<4)
                    switch side {
                    case 0: p.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: -margin)
                    case 1: p.position = CGPoint(x: size.width + margin, y: CGFloat.random(in: margin...(size.height - margin)))
                    case 2: p.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: size.height + margin)
                    default: p.position = CGPoint(x: -margin, y: CGFloat.random(in: margin...(size.height - margin)))
                    }

                    let ddx = cx - p.position.x, ddy = cy - p.position.y
                    let d   = max(sqrt(ddx * ddx + ddy * ddy), 1)
                    p.velocity = CGVector(dx: ddx / d * 1.5, dy: ddy / d * 1.5)
                    
                    p.spawnState = .spawning
                    p.spawnProgress = 0.0

                    self.particles.append(p)
                    try? await Task.sleep(nanoseconds: 40_000_000) // 40ms stagger for premium fast cascade
                }
            }
        }
    }

    func prepareForExpansion(clusterId: String, position: CGPoint, velocity: CGVector, symbols: [String]) {
        for sym in symbols {
            expandedClusterPositions[sym] = (position, velocity)
        }
    }

    func updateSize(_ size: CGSize) { canvasSize = size }


    func drag(id: String, to point: CGPoint) {
        guard let i = particles.firstIndex(where: { $0.id == id }) else { return }
        particles[i].position = point
        particles[i].velocity = .zero
        particles[i].spawnState = .active
        particles[i].spawnProgress = 1.0
        tickCount = 0
    }

    // MARK: - Rematerialise (unpop restore)

    /// Inserts a single bubble at a safe screen-edge position with a soft fade-in animation.
    /// The bubble enters with near-zero velocity and integrates naturally into the simulation.
    func rematerializeParticle(_ p: BubbleParticle) {
        // Don't add if already present
        guard !particles.contains(where: { $0.id == p.id }) else { return }

        var spawned = p
        let size    = canvasSize
        let margin  = p.radius + 8

        // Spawn at the nearest canvas edge so it drifts into frame organically
        let edges: [CGPoint] = [
            CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: -margin),
            CGPoint(x: size.width + margin, y: CGFloat.random(in: margin...(size.height - margin)))
        ]
        spawned.position = edges[Int.random(in: 0..<edges.count)]

        // Very gentle inward nudge
        let cx  = size.width / 2, cy = size.height / 2
        let ddx = cx - spawned.position.x
        let ddy = cy - spawned.position.y
        let d   = max(hypot(ddx, ddy), 1)
        spawned.velocity = CGVector(dx: ddx / d * 0.6, dy: ddy / d * 0.6)

        // Set spawn properties for materialization & fly-in
        spawned.spawnState = .spawning
        spawned.spawnProgress = 0.0

        particles.append(spawned)
    }

    // MARK: - Bubble Pop

    func popBubble(id: String) {
        guard let idx = particles.firstIndex(where: { $0.id == id }) else { return }
        let p      = particles[idx]
        
        let popColor: Color
        if p.isWatchlist {
            popColor = Color(hex: "#6366f1")
        } else if p.gain > 0 {
            popColor = Color.jade
        } else if p.gain < 0 {
            popColor = Color.crimson
        } else {
            popColor = Color.gray
        }
        
        let count  = 14
        var parts: [PopParticle] = []

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * .pi * 2 + Double.random(in: -0.25...0.25)
            let speed = CGFloat.random(in: 1.8...5.0)
            parts.append(PopParticle(
                x:  p.position.x,
                y:  p.position.y,
                vx: CGFloat(cos(angle)) * speed,
                vy: CGFloat(sin(angle)) * speed,
                opacity: 1.0,
                radius:  CGFloat.random(in: p.radius * 0.07...p.radius * 0.18)
            ))
        }

        pops.append(BubblePop(
            baseColor:   popColor,
            cx:          p.position.x,
            cy:          p.position.y,
            mainRadius:  p.radius,
            mainOpacity: 1.0,
            particles:   parts
        ))

        particles.remove(at: idx)
        tickCount = 0 // trigger soft re-balance
    }

    // MARK: - Tick

    func tick(date: Date) {
        tickCount += 1

        // ── 1. Pop animations ─────────────────────────────────────────────
        for i in pops.indices {
            pops[i].tick += 1
            let t = Double(pops[i].tick) / Double(BubblePop.maxTicks)

            pops[i].mainOpacity = max(0, 1.0 - t * 2.0)
            pops[i].mainRadius *= 1.012  // slight expansion while fading

            for j in pops[i].particles.indices {
                pops[i].particles[j].x  += pops[i].particles[j].vx
                pops[i].particles[j].y  += pops[i].particles[j].vy
                pops[i].particles[j].vx *= 0.90   // air friction
                pops[i].particles[j].vy *= 0.90
                pops[i].particles[j].vy += 0.10   // slight gravity pull
                pops[i].particles[j].opacity  = max(0, 1.0 - t * 1.4)
                pops[i].particles[j].radius   = max(0.5, pops[i].particles[j].radius * 0.97)
            }
        }
        pops.removeAll { $0.tick >= BubblePop.maxTicks }

        // ── 1b. Merging particles transition ──────────────────────────────
        for i in mergingParticles.indices {
            let dx = mergingParticles[i].targetPosition.x - mergingParticles[i].position.x
            let dy = mergingParticles[i].targetPosition.y - mergingParticles[i].position.y
            
            mergingParticles[i].position.x += dx * 0.09
            mergingParticles[i].position.y += dy * 0.09
            
            mergingParticles[i].opacity = max(0, mergingParticles[i].opacity - 0.03)
            mergingParticles[i].radius = max(0.5, mergingParticles[i].radius * 0.94)
        }
        mergingParticles.removeAll { $0.opacity <= 0.01 }

        // ── 1c. Temporary Expansion preview transition ───────────────────
        if isTempExpanded {
            expansionProgress = min(1.0, expansionProgress + 0.04)
        } else {
            expansionProgress = max(0.0, expansionProgress - 0.04)
        }
        
        if expansionProgress > 0 && !tempChildParticles.isEmpty {
            if let centerParticle = particles.first(where: { $0.id == expandedClusterID }) {
                let count = tempChildParticles.count
                for i in 0..<count {
                    let angle = Double(i) * (2.0 * .pi / Double(count)) + tickCount * 0.003
                    let targetDist = centerParticle.radius + tempChildParticles[i].radius + 18.0
                    let currentDist = targetDist * expansionProgress
                    tempChildParticles[i].currentPosition = CGPoint(
                        x: centerParticle.position.x + cos(angle) * currentDist,
                        y: centerParticle.position.y + sin(angle) * currentDist
                    )
                }
            }
        } else if expansionProgress <= 0 {
            tempChildParticles.removeAll()
            expandedClusterID = nil
        }

        // ── 2. Bubble physics ─────────────────────────────────────────────
        guard !particles.isEmpty else {
            return
        }

        let cx        = canvasSize.width  / 2
        let cy        = canvasSize.height / 2
        let decayBase = max(0.0, 1.0 - tickCount * 0.003)  // decays in ~333 ticks (~5.5s)
        var pts       = particles

        // 2a. Advance spawn progress for all particles
        let spawnStep = 1.0 / 60.0
        for i in pts.indices {
            if pts[i].spawnState == .spawning || pts[i].spawnState == .settling {
                let step = pts[i].radius >= 55.0 ? (1.0 / 36.0) : spawnStep
                pts[i].spawnProgress = min(1.0, pts[i].spawnProgress + step)
                if pts[i].spawnProgress >= 1.0 {
                    pts[i].spawnState = .active
                } else if pts[i].spawnProgress >= 0.4 {
                    pts[i].spawnState = .settling
                }
            }
        }

        // 2b. Gravity + organic drift + damping
        for i in pts.indices {
            let ddx  = cx - pts[i].position.x
            let ddy  = cy - pts[i].position.y
            let seed = CGFloat(i) * 1.7

            let dynamicDrift = driftAmplitude * CGFloat(decayBase)
            let driftX = sin(tickCount * 0.016 + seed) * dynamicDrift
            let driftY = cos(tickCount * 0.011 + seed + 1.2) * dynamicDrift

            // Idle drift keeps bubbles alive even after decay
            let idleX = sin(tickCount * 0.005 + seed * 2) * idleDrift
            let idleY = cos(tickCount * 0.004 + seed * 2 + 0.5) * idleDrift

            // Adjust gravity and damping based on spawnState
            let currentGravity: CGFloat
            let currentDamping: CGFloat
            
            switch pts[i].spawnState {
            case .spawning:
                currentGravity = 0.014 // Stronger attraction pull to fly in fast
                currentDamping = 0.94
            case .settling:
                currentGravity = gravity
                currentDamping = 0.86 // Increased damping for rapid settling
            case .active:
                currentGravity = gravity
                currentDamping = damping
            }

            pts[i].velocity.dx = (pts[i].velocity.dx + ddx * currentGravity + driftX + idleX) * currentDamping
            pts[i].velocity.dy = (pts[i].velocity.dy + ddy * currentGravity + driftY + idleY) * currentDamping
            
            // Limit max velocity during spawning state
            if pts[i].spawnState == .spawning {
                let maxSpawningSpeed: CGFloat = 5.0
                let speed = sqrt(pts[i].velocity.dx * pts[i].velocity.dx + pts[i].velocity.dy * pts[i].velocity.dy)
                if speed > maxSpawningSpeed {
                    pts[i].velocity.dx = (pts[i].velocity.dx / speed) * maxSpawningSpeed
                    pts[i].velocity.dy = (pts[i].velocity.dy / speed) * maxSpawningSpeed
                }
            }

            pts[i].position.x += pts[i].velocity.dx
            pts[i].position.y += pts[i].velocity.dy
        }

        // 2c. Correlation-driven inter-particle forces
        //     Positive r  (> 0.4) → Hooke spring attraction
        //     Negative r  (< 0.0) → inverse-square repulsion
        //     F = α · r_xy · (d − d0)
        if !correlationMatrix.isEmpty {
            for i in 0 ..< pts.count {
                guard !pts[i].isWatchlist else { continue }
                for j in (i + 1) ..< pts.count {
                    guard !pts[j].isWatchlist else { continue }

                    let pair = AssetPair(pts[i].symbol, pts[j].symbol)
                    guard let r = correlationMatrix[pair] else { continue }

                    // Only act on meaningful correlation bands
                    guard r > 0.4 || r < 0.0 else { continue }

                    let ddx  = pts[j].position.x - pts[i].position.x
                    let ddy  = pts[j].position.y - pts[i].position.y
                    let dist = max(sqrt(ddx * ddx + ddy * ddy), 1)
                    let nx   = ddx / dist
                    let ny   = ddy / dist

                    // d0 = sum of radii (natural resting distance)
                    let d0 = pts[i].radius + pts[j].radius

                    // F_interaction = α · r_xy · (d − d0)
                    let force = correlationAlpha * CGFloat(r) * (dist - d0)

                    // Attraction: push both particles toward each other
                    // Repulsion: r < 0 makes force negative → pushes apart
                    pts[i].velocity.dx += force * nx
                    pts[i].velocity.dy += force * ny
                    pts[j].velocity.dx -= force * nx
                    pts[j].velocity.dy -= force * ny
                }
            }
        }

        // 2d. Inelastic collisions with full separation
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let ddx     = pts[j].position.x - pts[i].position.x
                let ddy     = pts[j].position.y - pts[i].position.y
                let minDist = (pts[i].radius + pts[j].radius) * repulsionPad
                let dist    = sqrt(ddx * ddx + ddy * ddy)
                guard dist < minDist, dist > 0 else { continue }

                // Full overlap removal
                var overlap = (minDist - dist) / 2.0
                let nx = ddx / dist, ny = ddy / dist

                // If either is spawning, reduce the collision force
                var restitution = collisionRestitution
                if pts[i].spawnState == .spawning || pts[j].spawnState == .spawning {
                    overlap *= 0.15
                    restitution *= 0.1
                }

                pts[i].position.x -= nx * overlap
                pts[i].position.y -= ny * overlap
                pts[j].position.x += nx * overlap
                pts[j].position.y += ny * overlap

                // Absorb relative velocity (very inelastic)
                let dvx = pts[j].velocity.dx - pts[i].velocity.dx
                let dvy = pts[j].velocity.dy - pts[i].velocity.dy
                let dot = dvx * nx + dvy * ny
                if dot < 0 {
                    let imp = dot * restitution
                    pts[i].velocity.dx += imp * nx
                    pts[i].velocity.dy += imp * ny
                    pts[j].velocity.dx -= imp * nx
                    pts[j].velocity.dy -= imp * ny
                }
            }
        }

        // 2e. Soft boundary clamping
        for i in pts.indices {
            // Skip boundary clamping during spawning state so they can fly in from off-screen
            guard pts[i].spawnState != .spawning else { continue }

            let r = pts[i].radius
            if pts[i].position.x < r {
                pts[i].position.x = r
                pts[i].velocity.dx = abs(pts[i].velocity.dx) * boundaryBounce
            }
            if pts[i].position.x > canvasSize.width - r {
                pts[i].position.x = canvasSize.width - r
                pts[i].velocity.dx = -abs(pts[i].velocity.dx) * boundaryBounce
            }
            if pts[i].position.y < r {
                pts[i].position.y = r
                pts[i].velocity.dy = abs(pts[i].velocity.dy) * boundaryBounce
            }
            if pts[i].position.y > canvasSize.height - r {
                pts[i].position.y = canvasSize.height - r
                pts[i].velocity.dy = -abs(pts[i].velocity.dy) * boundaryBounce
            }
        }

        particles = pts

        // No stop condition needed when driven by TimelineView
    }

    deinit {
        spawnTask?.cancel()
    }
}

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
                        engine.tick(date: timeline.date)
                        
                        // Draw connection lines for temporary expanded clusters
                        if engine.expansionProgress > 0, let centerId = engine.expandedClusterID,
                           let centerParticle = engine.particles.first(where: { $0.id == centerId }) {
                            for child in engine.tempChildParticles {
                                var path = Path()
                                path.move(to: centerParticle.position)
                                path.addLine(to: child.currentPosition)
                                ctx.stroke(path, with: .color(Color.jade.opacity(0.18 * engine.expansionProgress)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            }
                        }
                        
                        // Draw active bubbles
                        for p in engine.particles {
                            if p.id == engine.expandedClusterID {
                                var drawCtx = ctx
                                drawCtx.opacity = max(0.05, 1.0 - engine.expansionProgress)
                                drawSoftBubble(p, ctx: &drawCtx)
                            } else {
                                drawSoftBubble(p, ctx: &ctx)
                            }
                        }
                        
                        // Draw temporary child preview bubbles
                        if engine.expansionProgress > 0 {
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
                        
                        // Draw merging bubbles
                        for mp in engine.mergingParticles {
                            let tempParticle = BubbleParticle(
                                id: mp.id,
                                symbol: mp.symbol,
                                gain: 0.0,
                                radius: mp.radius,
                                position: mp.position,
                                velocity: .zero,
                                isWatchlist: false
                            )
                            var drawCtx = ctx
                            drawCtx.opacity = mp.opacity
                            drawSoftBubble(tempParticle, ctx: &drawCtx)
                        }
                        
                        // Draw pop animations on top
                        for pop in engine.pops {
                            drawPop(pop, ctx: &ctx)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { val in
                                if dragID == nil {
                                    dragID = engine.particles
                                        .first { distPt($0.position, val.startLocation) < $0.radius }?.id
                                }
                                if let id = dragID { engine.drag(id: id, to: val.location) }
                            }
                            .onEnded { _ in dragID = nil }
                    )
                    .onTapGesture { loc in
                        guard dragID == nil else { return }
                        
                        // Handle Selection Mode taps
                        if vm.isBubbleSelectionModeActive {
                            if let tapped = engine.particles.first(where: { distPt($0.position, loc) < $0.radius }) {
                                if !tapped.isCluster && !tapped.isWatchlist {
                                    vm.toggleBubbleSelection(for: tapped.symbol)
                                }
                            } else {
                                // Tap empty space to exit selection mode
                                vm.toggleBubbleSelectionMode()
                            }
                            return
                        }
                        
                        // 1. If currently expanded, handle expanded taps
                        if engine.isTempExpanded, let centerId = engine.expandedClusterID {
                            // Check if tapped a child bubble
                            if let tappedChild = engine.tempChildParticles.first(where: { distPt($0.currentPosition, loc) < $0.radius }) {
                                haptic(.medium)
                                if let inv = vm.investments.first(where: { $0.id == tappedChild.id }) {
                                    selectedInvestment = inv
                                }
                                return
                            }
                            
                            // Check if tapped the center cluster bubble
                            if let centerParticle = engine.particles.first(where: { $0.id == centerId }),
                               distPt(centerParticle.position, loc) < centerParticle.radius {
                                haptic(.medium)
                                // Tap center of expanded cluster -> open ClusterAssetsSheet showing options
                                if let cluster = vm.bubbleClusters.first(where: { $0.id.uuidString == centerId }) {
                                    let particle = BubbleParticle(
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
                                    selectedClusterParticle = particle
                                    showClusterAssetsSheet = true
                                }
                                return
                            }
                            
                            // Tapped background: collapse back
                            haptic(.light)
                            engine.isTempExpanded = false
                            return
                        }
                        
                        // 2. Standard (collapsed) state taps
                        if let tapped = engine.particles.first(where: { distPt($0.position, loc) < $0.radius }) {
                            haptic(.medium)
                            if tapped.isCluster {
                                // Tap collapsed cluster -> temporary expand in place
                                haptic(.rigid)
                                var tempChildren: [TempChildParticle] = []
                                let activeInvestments = vm.investments.filter { !$0.isWatchlist }
                                let totalActiveVal = activeInvestments.reduce(0.0) {
                                    $0 + $1.shares * vm.marketService.getCurrentPrice(for: $1.symbol)
                                }
                                let maxR = min(geo.size.width, geo.size.height) * 0.22
                                let minR: CGFloat = 28
                                
                                for sym in tapped.clusterSymbols {
                                    if let inv = vm.investments.first(where: { $0.symbol == sym }) {
                                        let price = vm.marketService.getCurrentPrice(for: inv.symbol)
                                        let val = inv.shares * price
                                        let weight = totalActiveVal > 0 ? (val / totalActiveVal) : 0.0
                                        let childR = minR + (maxR - minR) * CGFloat(weight)
                                        let gain = inv.totalCost > 0 ? ((val - inv.totalCost) / inv.totalCost) * 100 : 0.0
                                        
                                        tempChildren.append(TempChildParticle(
                                            id: inv.id,
                                            symbol: inv.symbol,
                                            name: inv.name,
                                            gain: gain,
                                            radius: childR,
                                            isWatchlist: false
                                        ))
                                    }
                                }
                                
                                engine.tempChildParticles = tempChildren
                                engine.expandedClusterID = tapped.id
                                engine.isTempExpanded = true
                            } else if let inv = vm.investments.first(where: { $0.id == tapped.id }) {
                                selectedInvestment = inv
                            }
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag):
                                    if let loc = drag?.startLocation {
                                        if let tapped = engine.particles.first(where: { distPt($0.position, loc) < $0.radius }) {
                                            if !tapped.isCluster && !tapped.isWatchlist {
                                                if !vm.isBubbleSelectionModeActive {
                                                    vm.toggleBubbleSelectionMode()
                                                }
                                                if !vm.selectedBubbleSymbols.contains(tapped.symbol) {
                                                    vm.toggleBubbleSelection(for: tapped.symbol)
                                                }
                                            }
                                        }
                                    }
                                default: break
                                }
                            }
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

// MARK: - Shimmer Loading View

struct ShimmerLoadingView: View {
    @State private var pulse = false
    
    var body: some View {
        ZStack {
            Color.bgDeep.ignoresSafeArea()
            
            // Soft circular glow at the center representing the bubble cluster
            Circle()
                .fill(Color.jade.opacity(0.12))
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

// MARK: - Cluster Assets Sheet (Bubble Merge)

struct ClusterAssetsSheet: View {
    let particle: BubbleParticle
    @ObservedObject var vm: PortfolioViewModel
    @EnvironmentObject private var lm: AppLanguageManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgDeep.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(lm.t("bubbles.mergedBubblesTitle"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(1.2)
                            .padding(.horizontal, 4)
                        
                        let clusterInvestments = vm.investments.filter { particle.clusterSymbols.contains($0.symbol) && !$0.isWatchlist }
                        
                        VStack(spacing: 12) {
                            ForEach(clusterInvestments) { inv in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(inv.symbol)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(inv.name)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.textMuted)
                                    }
                                    
                                    Spacer()
                                    
                                    let price = vm.marketService.getCurrentPrice(for: inv.symbol)
                                    let val = inv.shares * price
                                    let gain = val - inv.totalCost
                                    let gainPct = inv.totalCost > 0 ? (gain / inv.totalCost) * 100 : 0
                                    
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(CurrencyService.shared.format(value: val, from: inv.nativeCurrency))
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(String(format: "%@%.1f%%", gainPct >= 0 ? "+" : "", gainPct))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(gainPct.gainColor)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                        .cardStyle()
                    }
                    .padding(20)
                }
            }
            .navigationTitle(particle.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lm.t("common.fertig")) { dismiss() }
                        .foregroundStyle(Color.jade)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let clusterId = UUID(uuidString: particle.id) {
                    Button(role: .destructive) {
                        haptic(.rigid)
                        vm.expandCluster(id: clusterId)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "circle.grid.cross.left.filled")
                            Text(lm.t("bubbles.dissolveCluster"))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
