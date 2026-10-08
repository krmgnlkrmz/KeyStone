import BalanceCore
import SwiftUI

/// The day's structure as a SwiftUI shape (no SpriteKit in the widget).
struct SilhouetteShape: Shape {
    let silhouette: Silhouette
    var keystoneOnly = false
    var excludeKeystone = false

    func path(in rect: CGRect) -> Path {
        let b = silhouette.bounds
        var box = CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height)
        if box.width < 300 { box = box.insetBy(dx: -(300 - box.width) / 2, dy: 0) }
        if box.height < 380 { box.size.height = 380 }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let ox = rect.minX + (rect.width - box.width * scale) / 2 - box.minX * scale
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: ox + v.x * scale, y: rect.maxY - (v.y - box.minY) * scale) }
        var path = Path()
        for shape in silhouette.shapes {
            let isKey = shape.kind == .keystone
            if keystoneOnly && !isKey { continue }
            if excludeKeystone && isKey { continue }
            path.addLines(shape.points.map(pt))
            path.closeSubpath()
        }
        if !keystoneOnly {
            let y = rect.maxY - (silhouette.floorY - box.minY) * scale
            path.addRect(CGRect(x: rect.minX + rect.width * 0.1, y: y, width: rect.width * 0.8, height: max(1, 1.5 * scale)))
        }
        return path
    }
}
