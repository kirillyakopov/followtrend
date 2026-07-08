//
//  BubblePhysicsEngine.swift
//  followtrend
//
//  Physics simulation and transition state for the bubble portfolio view.
//

import SwiftUI
import Combine

struct PopParticle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var opacity: Double
    var radius: CGFloat
}

struct BubblePop {
    let baseColor: Color
    var cx: CGFloat
    var cy: CGFloat
    var mainRadius: CGFloat
    var mainOpacity: Double
    var particles: [PopParticle]
    var tick: Int = 0

    static let maxTicks = 52
}

struct MergingParticle: Identifiable {
    let id: String
    let symbol: String
    var position: CGPoint
    let targetPosition: CGPoint
    var radius: CGFloat
    var opacity: Double
    let baseColor: Color
}

struct TempChildParticle: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let gain: Double
    let radius: CGFloat
    let isWatchlist: Bool
    var currentPosition: CGPoint = .zero
}

@MainActor
final class BubblePhysicsEngine: ObservableObject {
    var particles: [BubbleParticle] = []
    var pops: [BubblePop] = []
    var mergingParticles: [MergingParticle] = []
    private var expandedClusterPositions: [String: (position: CGPoint, velocity: CGVector)] = [:]

    var tempChildParticles: [TempChildParticle] = []
    var expandedClusterID: String?
    var isTempExpanded = false
    var expansionProgress: Double = 0.0

    private(set) var canvasSize: CGSize = .zero
    private var tickCount: Double = 0

    var correlationMatrix: [AssetPair: Double] = [:]

    @Published var isLayoutReady = false

    private let gravity: CGFloat = 0.0025          // strong center pull while spawning/settling (gather quickly)
    private let centerPull: CGFloat = 0.00018      // weak pull once active → free float (prototype ≈ 0.00014)
    private let damping: CGFloat = 0.945           // prototype per-frame damping
    private let collisionRestitution: CGFloat = 0.03
    private let boundaryBounce: CGFloat = 0.02
    private let repulsionPad: CGFloat = 1.08
    private let driftAmplitude: CGFloat = 0.005    // settle-time drift (decays to rest)
    private let wanderAmp: CGFloat = 0.012         // perpetual idle wander once active → bubbles stay alive
    private let correlationAlpha: CGFloat = 0.0018
    private var spawnTask: Task<Void, Never>?

    // Honors the system Reduce Motion setting: no idle wander, heavier damping
    // (mirrors the prototype's `rm ? 0.86 : 0.945`).
    private var reduceMotion = UIAccessibility.isReduceMotionEnabled
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reduceMotion = UIAccessibility.isReduceMotionEnabled
                }
            }
            .store(in: &cancellables)
    }

    func sync(particles newParticles: [BubbleParticle], in size: CGSize) {
        canvasSize = size
        // Do NOT reset tickCount here — resetting it re-excites all existing settled
        // bubbles (decay returns to 1.0 = full drift amplitude) and causes instability.
        // tickCount is only reset during the initial layout pass below.
        spawnTask?.cancel()

        let cx = size.width / 2
        let cy = size.height / 2
        let oldParticles = particles
        let newIds = Set(newParticles.map(\.id))

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
                    existing.symbol = p.symbol
                }
                syncedParticles.append(existing)
            } else if p.isCluster {
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

                for oldP in oldInvolved {
                    let isPos = oldP.gain >= 0
                    let isNeutral = abs(oldP.gain) < 0.05
                    let baseColor = oldP.isWatchlist ? Color.neutralFlat : (isNeutral ? Color.gray : (isPos ? Color.jade : Color.crimson))

                    mergingParticles.append(MergingParticle(
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

        if let expId = expandedClusterID {
            if !syncedParticles.contains(where: { $0.id == expId }) {
                isTempExpanded = false
                expandedClusterID = nil
                tempChildParticles.removeAll()
            } else if let cluster = syncedParticles.first(where: { $0.id == expId }) {
                tempChildParticles.removeAll { !cluster.clusterSymbols.contains($0.symbol) }
            }
        }

        particles = syncedParticles

        if !isLayoutReady && added.isEmpty {
            isLayoutReady = true
        }
        
        guard !added.isEmpty else { return }

        let maxR = newParticles.map(\.radius).max() ?? 0
        let largeThreshold = max(55.0, maxR * 0.75)

        if !isLayoutReady {
            // Initial layout: reset tickCount so decay starts fresh
            tickCount = 0
            var initialParticles: [BubbleParticle] = particles

            for var p in added {
                if p.radius >= largeThreshold {
                    let offsetRange: CGFloat = 20.0
                    p.position = CGPoint(
                        x: cx + CGFloat.random(in: -offsetRange...offsetRange),
                        y: cy + CGFloat.random(in: -offsetRange...offsetRange)
                    )
                    p.velocity = .zero
                    p.spawnState = .active
                    p.spawnProgress = 1.0
                } else {
                    prepareEdgeSpawn(&p, in: size, center: CGPoint(x: cx, y: cy), speed: 1.5)
                }
                initialParticles.append(p)
            }

            particles = initialParticles

            for _ in 0..<5 {
                tick(date: Date())
            }

            isLayoutReady = true
        } else {
            spawnTask = Task { @MainActor in
                for var p in added {
                    guard !Task.isCancelled else { break }
                    self.prepareInteriorSpawn(&p, in: size)
                    self.particles.append(p)
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
            }
        }
    }

    func prepareForExpansion(clusterId: String, position: CGPoint, velocity: CGVector, symbols: [String]) {
        for sym in symbols {
            expandedClusterPositions[sym] = (position, velocity)
        }
    }

    func updateSize(_ size: CGSize) {
        canvasSize = size
    }

    func drag(id: String, to point: CGPoint) {
        guard let i = particles.firstIndex(where: { $0.id == id }) else { return }
        particles[i].position = point
        particles[i].velocity = .zero
        particles[i].spawnState = .active
        particles[i].spawnProgress = 1.0
        // NB: do not reset tickCount here — that would freeze every other bubble's
        // wander phase for the duration of the drag. Let the wander run continuously.
    }

    func rematerializeParticle(_ p: BubbleParticle) {
        guard !particles.contains(where: { $0.id == p.id }) else { return }

        var spawned = p
        let size = canvasSize
        let margin = p.radius + 8

        let edges = [
            CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: -margin),
            CGPoint(x: size.width + margin, y: CGFloat.random(in: margin...(size.height - margin)))
        ]
        spawned.position = edges[Int.random(in: 0..<edges.count)]

        let cx = size.width / 2
        let cy = size.height / 2
        let ddx = cx - spawned.position.x
        let ddy = cy - spawned.position.y
        let d = max(hypot(ddx, ddy), 1)
        spawned.velocity = CGVector(dx: ddx / d * 0.6, dy: ddy / d * 0.6)
        spawned.spawnState = .spawning
        spawned.spawnProgress = 0.0

        particles.append(spawned)
    }

    func popBubble(id: String) {
        guard let idx = particles.firstIndex(where: { $0.id == id }) else { return }
        let p = particles[idx]

        let popColor: Color
        if p.isWatchlist {
            popColor = Color.neutralFlat
        } else if p.gain > 0 {
            popColor = Color.jade
        } else if p.gain < 0 {
            popColor = Color.crimson
        } else {
            popColor = Color.gray
        }

        let count = 14
        var parts: [PopParticle] = []

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * .pi * 2 + Double.random(in: -0.25...0.25)
            let speed = CGFloat.random(in: 1.8...5.0)
            parts.append(PopParticle(
                x: p.position.x,
                y: p.position.y,
                vx: CGFloat(cos(angle)) * speed,
                vy: CGFloat(sin(angle)) * speed,
                opacity: 1.0,
                radius: CGFloat.random(in: p.radius * 0.07...p.radius * 0.18)
            ))
        }

        pops.append(BubblePop(
            baseColor: popColor,
            cx: p.position.x,
            cy: p.position.y,
            mainRadius: p.radius,
            mainOpacity: 1.0,
            particles: parts
        ))

        particles.remove(at: idx)
        tickCount = 0
    }

    func tick(date: Date) {
        tickCount += 1

        updatePops()
        updateMergingParticles()
        updateExpansionPreview()

        guard !particles.isEmpty else { return }

        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        let decayBase = max(0.0, 1.0 - tickCount * 0.003)
        var pts = particles

        advanceSpawnProgress(&pts)
        applyGravityAndDrift(&pts, center: CGPoint(x: cx, y: cy), decayBase: decayBase)
        applyCorrelationForces(&pts)
        // Two passes of collision resolution per frame:
        // - first pass separates most overlaps
        // - second pass catches residuals left after the first repositioning
        resolveCollisions(&pts)
        resolveCollisions(&pts)
        applyClusterExpansionRepulsion(&pts)
        clampToBounds(&pts)

        particles = pts
    }

    private func prepareEdgeSpawn(_ particle: inout BubbleParticle, in size: CGSize, center: CGPoint, speed: CGFloat) {
        let margin = particle.radius + 8
        let side = Int.random(in: 0..<4)
        switch side {
        case 0:
            particle.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: -margin)
        case 1:
            particle.position = CGPoint(x: size.width + margin, y: CGFloat.random(in: margin...(size.height - margin)))
        case 2:
            particle.position = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: size.height + margin)
        default:
            particle.position = CGPoint(x: -margin, y: CGFloat.random(in: margin...(size.height - margin)))
        }

        let ddx = center.x - particle.position.x
        let ddy = center.y - particle.position.y
        let d = max(sqrt(ddx * ddx + ddy * ddy), 1)
        particle.velocity = CGVector(dx: ddx / d * speed, dy: ddy / d * speed)
        particle.spawnState = .spawning
        particle.spawnProgress = 0.0
    }

    /// Spawn a newly-added bubble at a safe interior position near the center
    /// with zero velocity so it doesn't fly to edges.
    private func prepareInteriorSpawn(_ particle: inout BubbleParticle, in size: CGSize) {
        // Guard: never spawn into a zero-size canvas
        guard size.width > 10, size.height > 10 else { return }
        let r = max(particle.radius, 28)
        let cx = size.width / 2
        let cy = size.height / 2
        // Try to find a position that doesn't heavily overlap existing particles.
        // Up to 8 attempts; take the least-overlapping one.
        var bestPos = CGPoint(x: cx, y: cy)
        var bestOverlap: CGFloat = .infinity
        for _ in 0..<8 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let scatter = CGFloat.random(in: r...(min(size.width, size.height) * 0.30))
            let rawX = min(max(cx + cos(angle) * scatter, r + 4), size.width - r - 4)
            let rawY = min(max(cy + sin(angle) * scatter, r + 4), size.height - r - 4)
            let candidate = CGPoint(x: rawX, y: rawY)
            // Measure total overlap with current particles
            let overlap = particles.reduce(CGFloat(0)) { acc, q in
                let dx = q.position.x - rawX
                let dy = q.position.y - rawY
                let dist = sqrt(dx*dx + dy*dy)
                let minD = (r + q.radius) * 1.05
                return acc + max(0, minD - dist)
            }
            if overlap < bestOverlap {
                bestOverlap = overlap
                bestPos = candidate
            }
        }
        particle.position = bestPos
        particle.velocity = .zero
        particle.spawnState = .spawning
        particle.spawnProgress = 0.0
    }

    private func updatePops() {
        for i in pops.indices {
            pops[i].tick += 1
            let t = Double(pops[i].tick) / Double(BubblePop.maxTicks)

            pops[i].mainOpacity = max(0, 1.0 - t * 2.0)
            pops[i].mainRadius *= 1.012

            for j in pops[i].particles.indices {
                pops[i].particles[j].x += pops[i].particles[j].vx
                pops[i].particles[j].y += pops[i].particles[j].vy
                pops[i].particles[j].vx *= 0.90
                pops[i].particles[j].vy *= 0.90
                pops[i].particles[j].vy += 0.10
                pops[i].particles[j].opacity = max(0, 1.0 - t * 1.4)
                pops[i].particles[j].radius = max(0.5, pops[i].particles[j].radius * 0.97)
            }
        }
        pops.removeAll { $0.tick >= BubblePop.maxTicks }
    }

    private func updateMergingParticles() {
        for i in mergingParticles.indices {
            let dx = mergingParticles[i].targetPosition.x - mergingParticles[i].position.x
            let dy = mergingParticles[i].targetPosition.y - mergingParticles[i].position.y
            mergingParticles[i].position.x += dx * 0.09
            mergingParticles[i].position.y += dy * 0.09
            mergingParticles[i].opacity = max(0, mergingParticles[i].opacity - 0.03)
            mergingParticles[i].radius = max(0.5, mergingParticles[i].radius * 0.94)
        }
        mergingParticles.removeAll { $0.opacity <= 0.01 }
    }

    private func updateExpansionPreview() {
        if isTempExpanded {
            expansionProgress = min(1.0, expansionProgress + 0.04)
        } else {
            expansionProgress = max(0.0, expansionProgress - 0.04)
        }

        if expansionProgress > 0 && !tempChildParticles.isEmpty {
            if let centerParticle = particles.first(where: { $0.id == expandedClusterID }) {
                let count = tempChildParticles.count
                let previewRadius = min(110.0, max(70.0, CGFloat(count) * 18.0))
                
                for i in 0..<count {
                    let angle = Double(i) * (2.0 * .pi / Double(count))
                    
                    let targetX = centerParticle.position.x + CGFloat(cos(angle)) * previewRadius
                    let targetY = centerParticle.position.y + CGFloat(sin(angle)) * previewRadius
                    
                    let safePadding: CGFloat = 16.0
                    let childR = tempChildParticles[i].radius
                    
                    let clampedX = min(max(targetX, safePadding + childR), canvasSize.width - safePadding - childR)
                    let clampedY = min(max(targetY, safePadding + childR), canvasSize.height - safePadding - childR)
                    
                    let startX = centerParticle.position.x
                    let startY = centerParticle.position.y
                    
                    tempChildParticles[i].currentPosition = CGPoint(
                        x: startX + (clampedX - startX) * CGFloat(expansionProgress),
                        y: startY + (clampedY - startY) * CGFloat(expansionProgress)
                    )
                }
            }
        } else if expansionProgress <= 0 {
            tempChildParticles.removeAll()
            expandedClusterID = nil
        }
    }

    private func advanceSpawnProgress(_ pts: inout [BubbleParticle]) {
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
    }

    private func applyGravityAndDrift(_ pts: inout [BubbleParticle], center: CGPoint, decayBase: Double) {
        for i in pts.indices {
            let ddx = center.x - pts[i].position.x
            let ddy = center.y - pts[i].position.y

            // Stabilization window: for the very first ~20 ticks of a spawning bubble
            // (spawnProgress < 0.35 at 1/60 step), suppress ALL external forces.
            // This prevents the bubble from being immediately yanked by drift or
            // correlation before it has had a chance to settle into a valid position.
            let isEarlySpawn = pts[i].spawnState == .spawning && pts[i].spawnProgress < 0.35

            if isEarlySpawn {
                // Only apply a very gentle center pull — no drift, no idle noise.
                pts[i].velocity.dx = (pts[i].velocity.dx + ddx * 0.004) * 0.80
                pts[i].velocity.dy = (pts[i].velocity.dy + ddy * 0.004) * 0.80
            } else {
                let seed = CGFloat(i) * 1.7
                let isActive = pts[i].spawnState == .active
                // Perpetual gentle wander once active (never decays → bubbles stay alive);
                // during settling a small decaying drift lets them come to rest.
                // Reduce Motion: no wander at all — bubbles settle and hold still.
                let amp = isActive
                    ? (reduceMotion ? 0 : wanderAmp)
                    : (driftAmplitude * CGFloat(decayBase))
                let driftX = sin(tickCount * 0.0070 + seed) * amp
                let driftY = cos(tickCount * 0.0058 + seed * 1.7) * amp

                let currentGravity: CGFloat
                let currentDamping: CGFloat

                switch pts[i].spawnState {
                case .spawning:
                    currentGravity = 0.006   // gentler than before (was 0.014)
                    currentDamping = 0.88
                case .settling:
                    currentGravity = gravity
                    currentDamping = 0.86
                case .active:
                    currentGravity = centerPull                      // weak → free float
                    currentDamping = reduceMotion ? 0.86 : damping   // heavier damping under Reduce Motion
                }

                pts[i].velocity.dx = (pts[i].velocity.dx + ddx * currentGravity + driftX) * currentDamping
                pts[i].velocity.dy = (pts[i].velocity.dy + ddy * currentGravity + driftY) * currentDamping
            }

            // Sanitise NaN / Inf
            if pts[i].velocity.dx.isNaN || pts[i].velocity.dx.isInfinite { pts[i].velocity.dx = 0 }
            if pts[i].velocity.dy.isNaN || pts[i].velocity.dy.isInfinite { pts[i].velocity.dy = 0 }

            // Speed cap: tighter for spawning bubbles
            let maxSpeed: CGFloat = isEarlySpawn ? 1.5 : (pts[i].spawnState == .spawning ? 2.5 : 8.0)
            let spd = sqrt(pts[i].velocity.dx * pts[i].velocity.dx + pts[i].velocity.dy * pts[i].velocity.dy)
            if spd > maxSpeed {
                pts[i].velocity.dx = (pts[i].velocity.dx / spd) * maxSpeed
                pts[i].velocity.dy = (pts[i].velocity.dy / spd) * maxSpeed
            }

            pts[i].position.x += pts[i].velocity.dx
            pts[i].position.y += pts[i].velocity.dy

            // Sanitise position
            if pts[i].position.x.isNaN || pts[i].position.x.isInfinite { pts[i].position.x = canvasSize.width / 2 }
            if pts[i].position.y.isNaN || pts[i].position.y.isInfinite { pts[i].position.y = canvasSize.height / 2 }
        }
    }

    private func applyCorrelationForces(_ pts: inout [BubbleParticle]) {
        guard !correlationMatrix.isEmpty else { return }

        for i in 0..<pts.count {
            guard !pts[i].isWatchlist else { continue }
            // Skip spawning bubbles — don't pull/push them with correlation yet
            guard pts[i].spawnState == .active else { continue }
            for j in (i + 1)..<pts.count {
                guard !pts[j].isWatchlist else { continue }
                guard pts[j].spawnState == .active else { continue }

                let pair = AssetPair(pts[i].symbol, pts[j].symbol)
                guard let r = correlationMatrix[pair], r > 0.4 || r < 0.0 else { continue }

                let ddx = pts[j].position.x - pts[i].position.x
                let ddy = pts[j].position.y - pts[i].position.y
                let dist = max(sqrt(ddx * ddx + ddy * ddy), 1)
                let nx = ddx / dist
                let ny = ddy / dist
                let d0 = pts[i].radius + pts[j].radius
                // Cap the force magnitude so no single pair can spike velocity
                let rawForce = correlationAlpha * CGFloat(r) * (dist - d0)
                let force = max(-0.04, min(0.04, rawForce))

                pts[i].velocity.dx += force * nx
                pts[i].velocity.dy += force * ny
                pts[j].velocity.dx -= force * nx
                pts[j].velocity.dy -= force * ny
            }
        }
    }

    private func resolveCollisions(_ pts: inout [BubbleParticle]) {
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let ddx = pts[j].position.x - pts[i].position.x
                let ddy = pts[j].position.y - pts[i].position.y
                let minDist = (pts[i].radius + pts[j].radius) * repulsionPad
                let dist = sqrt(ddx * ddx + ddy * ddy)
                guard dist < minDist, dist > 0 else { continue }

                let nx = ddx / dist
                let ny = ddy / dist

                let isSpawning = pts[i].spawnState == .spawning || pts[j].spawnState == .spawning

                if isSpawning {
                    // Gentle nudge only — prevents teleport while spawning
                    let overlap = min((minDist - dist) / 2.0, 1.0)
                    pts[i].position.x -= nx * overlap
                    pts[i].position.y -= ny * overlap
                    pts[j].position.x += nx * overlap
                    pts[j].position.y += ny * overlap
                    // No velocity impulse while spawning
                } else {
                    // Full overlap resolution for active-active pairs
                    let overlap = (minDist - dist) / 2.0
                    pts[i].position.x -= nx * overlap
                    pts[i].position.y -= ny * overlap
                    pts[j].position.x += nx * overlap
                    pts[j].position.y += ny * overlap

                    // Velocity impulse only when approaching
                    let dvx = pts[j].velocity.dx - pts[i].velocity.dx
                    let dvy = pts[j].velocity.dy - pts[i].velocity.dy
                    let dot = dvx * nx + dvy * ny
                    if dot < 0 {
                        let imp = dot * collisionRestitution
                        pts[i].velocity.dx += imp * nx
                        pts[i].velocity.dy += imp * ny
                        pts[j].velocity.dx -= imp * nx
                        pts[j].velocity.dy -= imp * ny
                    }
                }
            }
        }
    }

    private func clampToBounds(_ pts: inout [BubbleParticle]) {
        let w = canvasSize.width
        let h = canvasSize.height
        guard w > 0, h > 0 else { return }
        for i in pts.indices {
            let r = pts[i].radius
            // Softer bounce for spawning bubbles (don't slam into boundary)
            let bounce: CGFloat = pts[i].spawnState == .spawning ? 0.1 : 0.5

            if pts[i].position.x < r {
                pts[i].position.x = r
                pts[i].velocity.dx = abs(pts[i].velocity.dx) * bounce
            }
            if pts[i].position.x > w - r {
                pts[i].position.x = w - r
                pts[i].velocity.dx = -abs(pts[i].velocity.dx) * bounce
            }
            if pts[i].position.y < r {
                pts[i].position.y = r
                pts[i].velocity.dy = abs(pts[i].velocity.dy) * bounce
            }
            if pts[i].position.y > h - r {
                pts[i].position.y = h - r
                pts[i].velocity.dy = -abs(pts[i].velocity.dy) * bounce
            }
        }
    }

    private func applyClusterExpansionRepulsion(_ pts: inout [BubbleParticle]) {
        guard expansionProgress > 0,
              isTempExpanded,
              let centerId = expandedClusterID,
              let centerIndex = pts.firstIndex(where: { $0.id == centerId }) else { return }
        
        let centerParticle = pts[centerIndex]
        let count = tempChildParticles.count
        let previewRadius = min(110.0, max(70.0, CGFloat(count) * 18.0))
        let maxChildRadius = tempChildParticles.map { $0.radius }.max() ?? 30.0
        let focusRadius = (previewRadius + maxChildRadius + 20.0) * CGFloat(expansionProgress)
        
        for i in pts.indices {
            if pts[i].id != centerId {
                let dx = pts[i].position.x - centerParticle.position.x
                let dy = pts[i].position.y - centerParticle.position.y
                let dist = max(sqrt(dx*dx + dy*dy), 0.1)
                let requiredDistance = focusRadius + pts[i].radius
                
                if dist < requiredDistance {
                    let nx = dx / dist
                    let ny = dy / dist
                    let overlap = requiredDistance - dist
                    
                    // Smoothly slide them out based on distance
                    let push = overlap * 0.2
                    pts[i].position.x += nx * push
                    pts[i].position.y += ny * push
                    
                    // Dampen velocity heavily to prevent chaotic bouncing
                    pts[i].velocity.dx *= 0.5
                    pts[i].velocity.dy *= 0.5
                    
                    // Kill any inward velocity
                    let dot = pts[i].velocity.dx * nx + pts[i].velocity.dy * ny
                    if dot < 0 {
                        pts[i].velocity.dx -= dot * nx
                        pts[i].velocity.dy -= dot * ny
                    }
                }
            }
        }
    }

    deinit {
        spawnTask?.cancel()
    }
}
