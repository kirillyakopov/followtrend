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

    private var canvasSize: CGSize = .zero
    private var tickCount: Double = 0

    var correlationMatrix: [AssetPair: Double] = [:]

    @Published var isLayoutReady = false

    private let gravity: CGFloat = 0.0025
    private let damping: CGFloat = 0.94
    private let collisionRestitution: CGFloat = 0.03
    private let boundaryBounce: CGFloat = 0.02
    private let repulsionPad: CGFloat = 1.08
    private let driftAmplitude: CGFloat = 0.005
    private let idleDrift: CGFloat = 0.0008
    private let correlationAlpha: CGFloat = 0.0018
    private var spawnTask: Task<Void, Never>?

    func sync(particles newParticles: [BubbleParticle], in size: CGSize) {
        canvasSize = size
        tickCount = 0
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
                    let baseColor = oldP.isWatchlist ? Color(hex: "#6366f1") : (isNeutral ? Color.gray : (isPos ? Color.jade : Color.crimson))

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

        if let expId = expandedClusterID, !syncedParticles.contains(where: { $0.id == expId }) {
            isTempExpanded = false
            expandedClusterID = nil
            tempChildParticles.removeAll()
        }

        particles = syncedParticles

        guard !added.isEmpty else { return }

        let maxR = newParticles.map(\.radius).max() ?? 0
        let largeThreshold = max(55.0, maxR * 0.75)

        if particles.isEmpty && !isLayoutReady {
            var initialParticles: [BubbleParticle] = []

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
                    self.prepareEdgeSpawn(&p, in: size, center: CGPoint(x: cx, y: cy), speed: 1.5)
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
        tickCount = 0
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
            popColor = Color(hex: "#6366f1")
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
        resolveCollisions(&pts)
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
            let seed = CGFloat(i) * 1.7
            let dynamicDrift = driftAmplitude * CGFloat(decayBase)
            let driftX = sin(tickCount * 0.016 + seed) * dynamicDrift
            let driftY = cos(tickCount * 0.011 + seed + 1.2) * dynamicDrift
            let idleX = sin(tickCount * 0.005 + seed * 2) * idleDrift
            let idleY = cos(tickCount * 0.004 + seed * 2 + 0.5) * idleDrift

            let currentGravity: CGFloat
            let currentDamping: CGFloat

            switch pts[i].spawnState {
            case .spawning:
                currentGravity = 0.014
                currentDamping = 0.94
            case .settling:
                currentGravity = gravity
                currentDamping = 0.86
            case .active:
                currentGravity = gravity
                currentDamping = damping
            }

            pts[i].velocity.dx = (pts[i].velocity.dx + ddx * currentGravity + driftX + idleX) * currentDamping
            pts[i].velocity.dy = (pts[i].velocity.dy + ddy * currentGravity + driftY + idleY) * currentDamping

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
    }

    private func applyCorrelationForces(_ pts: inout [BubbleParticle]) {
        guard !correlationMatrix.isEmpty else { return }

        for i in 0..<pts.count {
            guard !pts[i].isWatchlist else { continue }
            for j in (i + 1)..<pts.count {
                guard !pts[j].isWatchlist else { continue }

                let pair = AssetPair(pts[i].symbol, pts[j].symbol)
                guard let r = correlationMatrix[pair], r > 0.4 || r < 0.0 else { continue }

                let ddx = pts[j].position.x - pts[i].position.x
                let ddy = pts[j].position.y - pts[i].position.y
                let dist = max(sqrt(ddx * ddx + ddy * ddy), 1)
                let nx = ddx / dist
                let ny = ddy / dist
                let d0 = pts[i].radius + pts[j].radius
                let force = correlationAlpha * CGFloat(r) * (dist - d0)

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

                var overlap = (minDist - dist) / 2.0
                let nx = ddx / dist
                let ny = ddy / dist
                var restitution = collisionRestitution

                if pts[i].spawnState == .spawning || pts[j].spawnState == .spawning {
                    overlap *= 0.15
                    restitution *= 0.1
                }

                pts[i].position.x -= nx * overlap
                pts[i].position.y -= ny * overlap
                pts[j].position.x += nx * overlap
                pts[j].position.y += ny * overlap

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
    }

    private func clampToBounds(_ pts: inout [BubbleParticle]) {
        for i in pts.indices {
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
    }

    deinit {
        spawnTask?.cancel()
    }
}
