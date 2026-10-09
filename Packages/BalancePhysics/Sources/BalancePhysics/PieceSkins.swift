import BalanceCore
import CoreGraphics
import Foundation
import SpriteKit

/// Colours the play area needs, resolved by the app for the current appearance.
/// Material colours are only used inside the play area (design system rule).
public struct ScenePalette {
    public var wood, woodDark, woodLight: SKColor
    public var stone, stoneDark, stoneLight: SKColor
    public var steel, steelDark, steelLight: SKColor
    public var rope, ropeDark: SKColor
    public var key, keyDark, keyLight: SKColor
    public var outline, ground, crack: SKColor
    public var accent, accentSoft, danger, jade, jadeSoft: SKColor
    public var text, text3, surface, line2: SKColor
    public var isDark: Bool

    public init(wood: SKColor, woodDark: SKColor, woodLight: SKColor, stone: SKColor, stoneDark: SKColor, stoneLight: SKColor,
                steel: SKColor, steelDark: SKColor, steelLight: SKColor, rope: SKColor, ropeDark: SKColor,
                key: SKColor, keyDark: SKColor, keyLight: SKColor, outline: SKColor, ground: SKColor, crack: SKColor,
                accent: SKColor, accentSoft: SKColor, danger: SKColor, jade: SKColor, jadeSoft: SKColor,
                text: SKColor, text3: SKColor, surface: SKColor, line2: SKColor, isDark: Bool) {
        self.wood = wood; self.woodDark = woodDark; self.woodLight = woodLight
        self.stone = stone; self.stoneDark = stoneDark; self.stoneLight = stoneLight
        self.steel = steel; self.steelDark = steelDark; self.steelLight = steelLight
        self.rope = rope; self.ropeDark = ropeDark
        self.key = key; self.keyDark = keyDark; self.keyLight = keyLight
        self.outline = outline; self.ground = ground; self.crack = crack
        self.accent = accent; self.accentSoft = accentSoft; self.danger = danger; self.jade = jade; self.jadeSoft = jadeSoft
        self.text = text; self.text3 = text3; self.surface = surface; self.line2 = line2; self.isDark = isDark
    }

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> SKColor {
        SKColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// The handoff's dark tokens. Used by previews, tests and as a fallback.
    @MainActor public static let dark = ScenePalette(
        wood: rgb(0xB98A5E), woodDark: rgb(0x86603D), woodLight: rgb(0xD1A87D),
        stone: rgb(0xA8A296), stoneDark: rgb(0x7C776D), stoneLight: rgb(0xC2BDB2),
        steel: rgb(0x7E8FA2), steelDark: rgb(0x56647A), steelLight: rgb(0xA6B4C4),
        rope: rgb(0xD9CFB8), ropeDark: rgb(0xA99F88),
        key: rgb(0xD9A85B), keyDark: rgb(0xA57732), keyLight: rgb(0xEDC787),
        outline: rgb(0x000000, 0.6), ground: rgb(0x3A424D), crack: rgb(0x190C00, 0.8),
        accent: rgb(0xD9A85B), accentSoft: rgb(0xD9A85B, 0.15), danger: rgb(0xE0574B), jade: rgb(0x8DBBA0), jadeSoft: rgb(0x8DBBA0, 0.16),
        text: rgb(0xECE7DE), text3: rgb(0x77726A), surface: rgb(0x1C222A), line2: rgb(0xDCD6C8, 0.20), isDark: true)

    @MainActor public static let light = ScenePalette(
        wood: rgb(0xA27146), woodDark: rgb(0x6F4A29), woodLight: rgb(0xBE8E60),
        stone: rgb(0x9A9384), stoneDark: rgb(0x6F695E), stoneLight: rgb(0xB3AC9F),
        steel: rgb(0x62748A), steelDark: rgb(0x435264), steelLight: rgb(0x8597AC),
        rope: rgb(0xBCAB85), ropeDark: rgb(0x8B7C59),
        key: rgb(0xBC7B22), keyDark: rgb(0x8A5612), keyLight: rgb(0xD79E4A),
        outline: rgb(0x1E140A, 0.55), ground: rgb(0xBDB6A8), crack: rgb(0x190C00, 0.75),
        accent: rgb(0xA26518), accentSoft: rgb(0xA26518, 0.11), danger: rgb(0xB8392E), jade: rgb(0x3B7656), jadeSoft: rgb(0x3B7656, 0.11),
        text: rgb(0x1B1E22), text3: rgb(0x8C877D), surface: rgb(0xFFFFFF), line2: rgb(0x1E2228, 0.20), isDark: false)
}

/// Visual state of one piece. Each state has a shape/pattern cue as well as a colour.
public enum PieceVisualState: Equatable, Sendable {
    case normal
    /// Solid amber outline with a 2 pt lift.
    case selected
    /// Tutorial target: dashed amber halo that breathes.
    case tapTarget
    /// Hint: solid amber ring for the hint duration.
    case hint
    /// Collapse replay: the piece that gave way.
    case blamed
}

/// Procedural material textures, cached per (material, size, fixed, palette).
@MainActor
public final class PieceTextureFactory {
    public static let shared = PieceTextureFactory()
    private var cache: [String: SKTexture] = [:]
    public var contentScale: CGFloat = 3

    public func flush() { cache.removeAll() }

    public func texture(for piece: Piece, palette: ScenePalette, muted: Bool = false) -> SKTexture {
        let local = piece.shape.localOutline
        let key = "\(piece.material.rawValue)|\(local.map { "\(Int($0.x * 10)),\(Int($0.y * 10))" }.joined(separator: ";"))|\(piece.fixed)|\(palette.isDark)|\(muted)|\(StableHash.fnv1a64(piece.id) % 16)"
        if let t = cache[key] { return t }
        let t = SKTexture(cgImage: Self.draw(piece: piece, palette: palette, muted: muted, scale: contentScale))
        t.filteringMode = .linear
        cache[key] = t
        return t
    }

    /// Bounding box of the local outline (texture extent).
    public static func localBounds(_ piece: Piece) -> CGRect {
        let r = Rect2.enclosing(piece.shape.localOutline)
        return CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }

    static func draw(piece: Piece, palette p: ScenePalette, muted: Bool, scale: CGFloat) -> CGImage {
        let bounds = localBounds(piece)
        let pw = max(1, Int((bounds.width * scale).rounded(.up))), ph = max(1, Int((bounds.height * scale).rounded(.up)))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)

        let outline = CGMutablePath()
        let pts = piece.shape.localOutline.map(\.cgPoint)
        let radius: CGFloat = piece.material == .stone || piece.material == .rope ? 3 : 2
        if case .rect = piece.shape {
            outline.addRoundedRect(in: bounds, cornerWidth: min(radius, bounds.width / 2), cornerHeight: min(radius, bounds.height / 2))
        } else {
            outline.addLines(between: pts)
            outline.closeSubpath()
        }
        ctx.addPath(outline)
        ctx.clip()

        let w = bounds.width, h = bounds.height
        let horizontal = w >= h
        if muted {
            ctx.setFillColor(p.text3.cgColor)
            ctx.fill(bounds)
            return ctx.makeImage()!
        }

        func gradient(_ colors: [SKColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
            let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: locs)!
            ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        var rng = SplitMix64(seed: StableHash.fnv1a64(piece.id))
        func rand() -> CGFloat { CGFloat(Double(rng.next() % 10_000) / 10_000) }

        switch piece.material {
        case .wood:
            // Grain runs along the length; the gradient runs across it.
            if horizontal {
                gradient([p.woodLight, p.wood, p.woodDark], [0, 0.55, 1], from: CGPoint(x: 0, y: bounds.maxY), to: CGPoint(x: 0, y: bounds.minY))
            } else {
                gradient([p.woodLight, p.wood, p.woodDark], [0, 0.55, 1], from: CGPoint(x: bounds.minX, y: 0), to: CGPoint(x: bounds.maxX, y: 0))
            }
            var o: CGFloat = 3
            let across = horizontal ? h : w
            while o < across {
                let dark = Int(o) % 7 == 3
                ctx.setFillColor((dark ? SKColor(red: 0.24, green: 0.12, blue: 0.04, alpha: 0.22) : SKColor(red: 1, green: 0.93, blue: 0.78, alpha: 0.10)).cgColor)
                if horizontal { ctx.fill(CGRect(x: bounds.minX, y: bounds.minY + o, width: w, height: 1)) }
                else { ctx.fill(CGRect(x: bounds.minX + o, y: bounds.minY, width: 1, height: h)) }
                o += dark ? 4 : 3
            }
            for (f, a, size) in [(0.28, 0.45, CGSize(width: 7, height: 2.5)), (0.74, 0.32, CGSize(width: 5, height: 2))] {
                let s = horizontal ? size : CGSize(width: size.height, height: size.width)
                let c = horizontal ? CGPoint(x: bounds.minX + w * f, y: bounds.midY + (rand() - 0.5) * h * 0.3)
                                   : CGPoint(x: bounds.midX + (rand() - 0.5) * w * 0.3, y: bounds.minY + h * f)
                ctx.setFillColor(SKColor(red: 0.2, green: 0.1, blue: 0.03, alpha: a).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height))
            }
        case .stone:
            gradient([p.stoneLight, p.stone, p.stoneDark], [0, 0.5, 1], from: CGPoint(x: bounds.minX, y: bounds.maxY), to: CGPoint(x: bounds.maxX, y: bounds.minY))
            let count = Int(w * h / 14)
            for i in 0..<count {
                let x = bounds.minX + rand() * w, y = bounds.minY + rand() * h
                let r: CGFloat = i % 3 == 0 ? 1.0 : 0.7
                let light = i % 4 == 1
                ctx.setFillColor((light ? SKColor(white: 1, alpha: 0.18) : SKColor(white: 0, alpha: i % 3 == 0 ? 0.14 : 0.24)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        case .steel:
            if horizontal {
                gradient([p.steelLight, p.steel, p.steelDark], [0, 0.45, 1], from: CGPoint(x: 0, y: bounds.maxY), to: CGPoint(x: 0, y: bounds.minY))
            } else {
                gradient([p.steelLight, p.steel, p.steelDark], [0, 0.45, 1], from: CGPoint(x: bounds.minX, y: 0), to: CGPoint(x: bounds.maxX, y: 0))
            }
            ctx.setFillColor(SKColor(white: 0, alpha: 0.12).cgColor)
            let len = horizontal ? w : h
            var o: CGFloat = 11
            while o < len - 1 {
                if horizontal { ctx.fill(CGRect(x: bounds.minX + o, y: bounds.minY, width: 1, height: h)) }
                else { ctx.fill(CGRect(x: bounds.minX, y: bounds.minY + o, width: w, height: 1)) }
                o += 12
            }
            let rivets = horizontal ? [CGPoint(x: bounds.minX + 7, y: bounds.midY), CGPoint(x: bounds.maxX - 7, y: bounds.midY)]
                                    : [CGPoint(x: bounds.midX, y: bounds.minY + 7), CGPoint(x: bounds.midX, y: bounds.maxY - 7)]
            for c in rivets {
                ctx.setFillColor(p.steelDark.cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 1.9, y: c.y - 1.9, width: 3.8, height: 3.8))
                ctx.setFillColor(p.steelLight.cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4))
            }
        case .brass:
            let a = CGFloat(170 - 90) * .pi / 180
            let d = CGPoint(x: cos(a) * h / 2, y: sin(a) * h / 2)
            gradient([p.keyLight, p.key, p.keyDark], [0, 0.55, 1],
                     from: CGPoint(x: bounds.midX - d.x, y: bounds.midY + d.y), to: CGPoint(x: bounds.midX + d.x, y: bounds.midY - d.y))
            ctx.setFillColor(SKColor(red: 0.31, green: 0.18, blue: 0, alpha: 0.16).cgColor)
            var y = bounds.minY + 4
            while y < bounds.maxY { ctx.fill(CGRect(x: bounds.minX, y: y, width: w, height: 1)); y += 5 }
            for _ in 0..<Int(w * h / 40) {
                let x = bounds.minX + rand() * w, yy = bounds.minY + rand() * h
                ctx.setFillColor(SKColor(red: 1, green: 0.94, blue: 0.78, alpha: 0.28).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - 0.7, y: yy - 0.7, width: 1.4, height: 1.4))
            }
        case .rope:
            ctx.setFillColor(p.rope.cgColor)
            ctx.fill(bounds)
            ctx.setStrokeColor(p.ropeDark.cgColor)
            ctx.setLineWidth(1.2)
            var o = -max(w, h)
            while o < max(w, h) * 2 {
                ctx.move(to: CGPoint(x: bounds.minX + o, y: bounds.minY))
                ctx.addLine(to: CGPoint(x: bounds.minX + o + h * 0.47, y: bounds.maxY))
                o += 6
            }
            ctx.strokePath()
        }

        if piece.fixed {
            // Diagonal hatch + four bolts: can't be removed.
            ctx.setStrokeColor(SKColor(white: 0, alpha: 0.22).cgColor)
            ctx.setLineWidth(1)
            var o = -h
            while o < w {
                ctx.move(to: CGPoint(x: bounds.minX + o, y: bounds.minY))
                ctx.addLine(to: CGPoint(x: bounds.minX + o + h, y: bounds.maxY))
                o += 5
            }
            ctx.strokePath()
            let b: CGFloat = 4.5, inset: CGFloat = 5
            if w > 2 * (b + inset) && h > 2 * (b + inset) {
                for c in [CGPoint(x: bounds.minX + inset, y: bounds.minY + inset), CGPoint(x: bounds.maxX - inset - b, y: bounds.minY + inset),
                          CGPoint(x: bounds.minX + inset, y: bounds.maxY - inset - b), CGPoint(x: bounds.maxX - inset - b, y: bounds.maxY - inset - b)] {
                    ctx.setFillColor(p.steelLight.cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x - 0.8, y: c.y - 0.8, width: b + 1.6, height: b + 1.6))
                    ctx.setFillColor(p.steelDark.cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x, y: c.y, width: b, height: b))
                }
            }
        }

        // 1 pt inner edge + top highlight.
        if piece.material != .brass {
            ctx.addPath(outline)
            ctx.setStrokeColor(p.outline.cgColor)
            ctx.setLineWidth(2)
            ctx.strokePath()
            ctx.setFillColor(SKColor(white: 1, alpha: 0.14).cgColor)
            ctx.fill(CGRect(x: bounds.minX, y: bounds.maxY - 1.5, width: w, height: 1))
        } else {
            ctx.addPath(outline)
            ctx.setStrokeColor(p.outline.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokePath()
        }
        return ctx.makeImage()!
    }
}

/// Builds and updates the visual children of a piece node (texture, overlays, state).
@MainActor
public enum PieceSkin {
    static let skinName = "skin"
    static let overlayName = "overlay"
    static let stateName = "state"
    static let hitName = "hit"

    /// Minimum touch target (44 pt) around every piece, invisible.
    public static let minimumHitSize: CGFloat = 44

    public static func attach(to node: SKNode, piece: Piece, palette: ScenePalette, interactive: Bool) {
        node.childNode(withName: skinName)?.removeFromParent()
        node.childNode(withName: overlayName)?.removeFromParent()
        node.childNode(withName: hitName)?.removeFromParent()
        let bounds = PieceTextureFactory.localBounds(piece)
        let sprite = SKSpriteNode(texture: PieceTextureFactory.shared.texture(for: piece, palette: palette), size: bounds.size)
        sprite.name = skinName
        sprite.position = CGPoint(x: bounds.midX, y: bounds.midY)
        sprite.zPosition = 0
        node.addChild(sprite)
        if piece.material == .brass {
            sprite.shadowCastBitMask = 0
        }
        let overlay = SKNode()
        overlay.name = overlayName
        overlay.zPosition = 2
        node.addChild(overlay)
        if interactive {
            let hit = SKSpriteNode(color: .clear, size: CGSize(width: max(bounds.width, minimumHitSize), height: max(bounds.height, minimumHitSize)))
            hit.name = hitName
            hit.position = sprite.position
            hit.alpha = 0.001
            node.addChild(hit)
        }
    }

    static func overlay(of node: SKNode) -> SKNode? { node.childNode(withName: overlayName) }

    /// Selection / hint / blame decorations.
    public static func setState(_ state: PieceVisualState, on node: SKNode, piece: Piece, palette: ScenePalette, reduceMotion: Bool) {
        guard let overlay = overlay(of: node), let sprite = node.childNode(withName: skinName) else { return }
        overlay.childNode(withName: stateName)?.removeFromParent()
        let bounds = PieceTextureFactory.localBounds(piece)
        sprite.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let holder = SKNode()
        holder.name = stateName
        switch state {
        case .normal:
            return
        case .selected:
            sprite.position.y += 2
            let halo = outlineNode(piece: piece, inset: -5, color: palette.accentSoft, width: 7, dashed: false)
            let line = outlineNode(piece: piece, inset: -2, color: palette.accent, width: 2, dashed: false)
            halo.position.y = 2; line.position.y = 2
            holder.addChild(halo); holder.addChild(line)
        case .tapTarget:
            let halo = outlineNode(piece: piece, inset: -6, color: palette.accent, width: 1.5, dashed: true)
            holder.addChild(halo)
            if !reduceMotion {
                halo.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 1.2), .fadeAlpha(to: 1, duration: 1.2)])))
            }
        case .hint:
            holder.addChild(ring(piece: piece, color: palette.accent, dashed: true))
        case .blamed:
            holder.addChild(outlineNode(piece: piece, inset: -2, color: palette.danger, width: 2, dashed: false))
        }
        overlay.addChild(holder)
    }

    /// Small brass diamond above a goal target, used when targets can't be told apart by name alone.
    public static func setTargetMarker(_ on: Bool, on node: SKNode, piece: Piece, palette: ScenePalette) {
        guard let overlay = overlay(of: node) else { return }
        overlay.childNode(withName: "target")?.removeFromParent()
        guard on else { return }
        let b = PieceTextureFactory.localBounds(piece)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 5)); path.addLine(to: CGPoint(x: 4, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -5)); path.addLine(to: CGPoint(x: -4, y: 0)); path.closeSubpath()
        let marker = SKShapeNode(path: path)
        marker.name = "target"
        marker.fillColor = palette.accent
        marker.strokeColor = palette.surface
        marker.lineWidth = 1
        marker.position = CGPoint(x: b.midX, y: b.midY)
        marker.zPosition = 4
        overlay.addChild(marker)
    }

    /// Cracks + pulse + badge for a tension tier. Each tier adds one crack, so tiers read in grayscale.
    public static func setTension(_ tier: TensionTier, on node: SKNode, piece: Piece, palette: ScenePalette, reduceMotion: Bool) {
        guard let overlay = overlay(of: node) else { return }
        overlay.childNode(withName: "tension")?.removeFromParent()
        guard tier != .none else { return }
        let holder = SKNode()
        holder.name = "tension"
        let bounds = PieceTextureFactory.localBounds(piece)
        let critical = tier == .critical
        let cracks = SKShapeNode(path: crackPath(bounds: bounds, tier: tier))
        cracks.strokeColor = critical ? palette.danger : palette.crack
        cracks.lineWidth = critical ? 1.5 : 1.1
        cracks.lineCap = .round
        cracks.lineJoin = .round
        cracks.zPosition = 1
        holder.addChild(cracks)
        if tier.rawValue >= 2 {
            let pulse = outlineNode(piece: piece, inset: -3, color: critical ? palette.danger : palette.accent, width: 1.5, dashed: false)
            holder.addChild(pulse)
            if !reduceMotion {
                let half = critical ? 0.45 : 0.9
                pulse.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: half), .fadeAlpha(to: 1, duration: half)])))
            }
            let badge = SKShapeNode(circleOfRadius: 9)
            badge.fillColor = critical ? palette.danger : palette.surface
            badge.strokeColor = critical ? palette.danger : palette.accent
            badge.lineWidth = 1.5
            badge.position = CGPoint(x: bounds.maxX + 3, y: bounds.maxY + 3)
            badge.zPosition = 3
            let glyph = SKShapeNode(path: crackGlyph())
            glyph.strokeColor = critical ? .white : palette.accent
            glyph.lineWidth = 1.6
            glyph.lineCap = .round
            badge.addChild(glyph)
            holder.addChild(badge)
        }
        overlay.addChild(holder)
    }

    /// Crack strokes across the piece (mirrors the design kit's crack paths, y up).
    static func crackPath(bounds b: CGRect, tier: TensionTier) -> CGPath {
        let path = CGMutablePath()
        let horizontal = b.width >= b.height
        let sets: [(CGFloat, CGFloat)]
        switch tier {
        case .light: sets = [(0.7, 0.55)]
        case .tense: sets = [(0.7, 0.85), (0.32, 0.5)]
        default: sets = [(0.7, 1), (0.3, 0.85), (0.52, 0.6)]
        }
        for (f, len) in sets {
            if horizontal {
                let x = b.minX + b.width * f, top = b.maxY
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x - 3, y: top - b.height * len * 0.4))
                path.addLine(to: CGPoint(x: x + 2.5, y: top - b.height * len * 0.7))
                path.addLine(to: CGPoint(x: x - 1, y: top - b.height * len))
            } else {
                let y = b.maxY - b.height * f, left = b.minX
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: left + b.width * len * 0.4, y: y - 3))
                path.addLine(to: CGPoint(x: left + b.width * len * 0.7, y: y + 2.5))
                path.addLine(to: CGPoint(x: left + b.width * len, y: y - 1))
            }
        }
        return path
    }

    static func crackGlyph() -> CGPath {
        let p = CGMutablePath()
        let pts = [CGPoint(x: 0.5, y: 4.5), CGPoint(x: -1.2, y: 1.5), CGPoint(x: 1.0, y: 0), CGPoint(x: -0.7, y: -2), CGPoint(x: 0.2, y: -4.5)]
        p.addLines(between: pts)
        return p
    }

    /// Outline following the piece's shape, offset by `inset` (negative = outside).
    public static func outlineNode(piece: Piece, inset: CGFloat, color: SKColor, width: CGFloat, dashed: Bool) -> SKShapeNode {
        let b = PieceTextureFactory.localBounds(piece).insetBy(dx: inset, dy: inset)
        var path: CGPath
        if case let .polygon(points) = piece.shape {
            let center = CGPoint(x: PieceTextureFactory.localBounds(piece).midX, y: PieceTextureFactory.localBounds(piece).midY)
            let m = CGMutablePath()
            let scaled = points.map { pt -> CGPoint in
                let v = CGPoint(x: pt.x - center.x, y: pt.y - center.y)
                let len = max(0.001, hypot(v.x, v.y))
                return CGPoint(x: pt.x - v.x / len * inset, y: pt.y - v.y / len * inset)
            }
            m.addLines(between: scaled)
            m.closeSubpath()
            path = m
        } else {
            path = CGPath(roundedRect: b, cornerWidth: min(4, b.width / 2), cornerHeight: min(4, b.height / 2), transform: nil)
        }
        if dashed { path = path.copy(dashingWithPhase: 0, lengths: [4, 3]) }
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = width
        node.fillColor = .clear
        return node
    }

    /// Hint/blame ring: a circle for compact pieces, a rounded frame for long ones.
    public static func ring(piece: Piece, color: SKColor, dashed: Bool) -> SKShapeNode {
        let b = PieceTextureFactory.localBounds(piece)
        let long = max(b.width, b.height) / max(1, min(b.width, b.height)) > 2.2
        var path: CGPath
        if long {
            path = CGPath(roundedRect: b.insetBy(dx: -10, dy: -10), cornerWidth: 12, cornerHeight: 12, transform: nil)
        } else {
            let r = max(b.width, b.height) / 2 + 16
            path = CGPath(ellipseIn: CGRect(x: b.midX - r, y: b.midY - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        if dashed { path = path.copy(dashingWithPhase: 0, lengths: [6, 4]) }
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = 2
        node.fillColor = .clear
        return node
    }

    /// Dashed outline for removed pieces and replay origins.
    public static func ghost(piece: Piece, palette: ScenePalette, alpha: CGFloat) -> SKNode {
        let node = outlineNode(piece: piece, inset: 0.75, color: palette.text3, width: 1.5, dashed: true)
        node.alpha = alpha
        node.position = piece.position.cgPoint
        node.zRotation = CGFloat(piece.rotation)
        return node
    }
}
