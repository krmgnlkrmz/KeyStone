import BalanceCore
import SwiftUI

/// Flat drawing of a structure (map cells, menu background, daily card). No SpriteKit.
struct SilhouetteView: View {
    let silhouette: Silhouette
    var color: Color = Palette.text2
    var keyColor: Color = Palette.accent
    /// Draw at least this design-space box so small structures keep a consistent scale.
    var minBox = CGSize(width: 300, height: 380)
    var showFloor = true
    var outlined = false

    var body: some View {
        Canvas { ctx, size in
            let b = silhouette.bounds
            var box = CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height)
            if box.width < minBox.width { box = box.insetBy(dx: -(minBox.width - box.width) / 2, dy: 0) }
            if box.height < minBox.height { box.size.height = minBox.height }
            let scale = min(size.width / box.width, size.height / box.height)
            let ox = (size.width - box.width * scale) / 2 - box.minX * scale
            // Floor sits on the bottom edge.
            func pt(_ v: Vec2) -> CGPoint {
                CGPoint(x: ox + v.x * scale, y: size.height - (v.y - box.minY) * scale)
            }
            for shape in silhouette.shapes {
                var path = Path()
                path.addLines(shape.points.map(pt))
                path.closeSubpath()
                let c = shape.kind == .keystone ? keyColor : color
                if outlined { ctx.stroke(path, with: .color(c), lineWidth: 1) } else { ctx.fill(path, with: .color(c)) }
            }
            if showFloor {
                let y = size.height - (silhouette.floorY - box.minY) * scale
                var floor = Path()
                floor.move(to: CGPoint(x: size.width * 0.1, y: y))
                floor.addLine(to: CGPoint(x: size.width * 0.9, y: y))
                ctx.stroke(floor, with: .color(color.opacity(0.6)), lineWidth: max(1, 2 * scale))
            }
        }
        .accessibilityHidden(true)
    }
}
