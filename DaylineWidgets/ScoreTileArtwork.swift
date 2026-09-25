import UIKit
import SwiftUI
import WidgetKit

/// A live score drawn as one image so iOS accented Home Screen modes can keep
/// the user's chosen blue ring and white tile instead of flattening the layers.
@MainActor enum ScoreTileArtwork {
    static func image(score: Int, label: String) -> UIImage {
        let side: CGFloat = 160
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = false
            return format
        }())
        return renderer.image { output in
            let context = output.cgContext
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 22).fill()

            let title = NSAttributedString(string: "Day score", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.black
            ])
            let titleSize = title.size()
            title.draw(at: CGPoint(x: (side - titleSize.width) / 2, y: 8))

            let center = CGPoint(x: 80, y: 81)
            let radius: CGFloat = 37
            let width: CGFloat = 34
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setStrokeColor(UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1).cgColor)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.strokePath()
            let fraction = CGFloat(min(max(score, 0), 100)) / 100
            let start = -CGFloat.pi / 2
            let end = start + 2 * .pi * fraction
            // Draw a single arc to avoid seams and moire from adjacent strokes.
            // The ice cap starts the arc, which then becomes continuous Dayline blue.
            context.setStrokeColor(UIColor(red: 0.0, green: 0.38, blue: 0.90, alpha: 1).cgColor)
            context.setLineCap(.round)
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.strokePath()
            // Ice-to-blue overlay is clipped to the arc silhouette, preventing
            // the pale cap from swelling into an oval over the blue stroke.
            context.saveGState()
            let icePath = UIBezierPath(arcCenter: center, radius: radius,
                                     startAngle: start, endAngle: end, clockwise: true)
            icePath.lineWidth = width
            icePath.lineCapStyle = .round
            context.addPath(icePath.cgPath)
            context.replacePathWithStrokedPath()
            context.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(red: 0.61, green: 0.85, blue: 1, alpha: 1).cgColor,
                                               UIColor(red: 0.0, green: 0.38, blue: 0.9, alpha: 1).cgColor] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: center.x, y: center.y - radius - width / 2),
                                       end: CGPoint(x: center.x + radius, y: center.y + radius / 2),
                                       options: [])
            context.restoreGState()
            if score > 0 {
                let point = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
                let number = NSAttributedString(string: "\(score)", attributes: [
                    .font: UIFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: UIColor.white
                ])
                let size = number.size()
                number.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
            }
            let footer = NSAttributedString(string: label, attributes: [
                .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor(white: 0.48, alpha: 1)
            ])
            let footerSize = footer.size()
            footer.draw(at: CGPoint(x: (side - footerSize.width) / 2, y: 142))
        }
    }
}
