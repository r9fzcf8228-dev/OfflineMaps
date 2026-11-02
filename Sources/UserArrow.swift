import UIKit

enum UserArrow {
    private static var cached: UIImage?

    static func image() -> UIImage {
        if let c = cached { return c }

        let size = CGSize(width: 64, height: 64)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)

        let img = renderer.image { ctx in
            let g = ctx.cgContext

            g.setFillColor(UIColor(red: 0.2, green: 0.55, blue: 1.0, alpha: 0.18).cgColor)
            g.fillEllipse(in: CGRect(x: 4, y: 6, width: 56, height: 56))

            let outline = UIBezierPath()
            outline.move(to: CGPoint(x: 32, y: 4))
            outline.addLine(to: CGPoint(x: 52, y: 56))
            outline.addLine(to: CGPoint(x: 32, y: 45))
            outline.addLine(to: CGPoint(x: 12, y: 56))
            outline.close()
            g.saveGState()
            g.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                        color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor.white.setFill()
            outline.fill()
            g.restoreGState()

            let left = UIBezierPath()
            left.move(to: CGPoint(x: 32, y: 11))
            left.addLine(to: CGPoint(x: 32, y: 40))
            left.addLine(to: CGPoint(x: 18, y: 49))
            left.close()
            UIColor(red: 0.38, green: 0.72, blue: 1.0, alpha: 1).setFill()
            left.fill()

            let right = UIBezierPath()
            right.move(to: CGPoint(x: 32, y: 11))
            right.addLine(to: CGPoint(x: 46, y: 49))
            right.addLine(to: CGPoint(x: 32, y: 40))
            right.close()
            UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1).setFill()
            right.fill()
        }

        cached = img
        return img
    }
}
