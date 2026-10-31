import UIKit

enum Affiliation: String, CaseIterable {
    case friendly = "F"
    case hostile = "H"
    case neutral = "N"
    case unknown = "U"

    var title: String {
        switch self {
        case .friendly: return "صديق"
        case .hostile: return "معادي"
        case .neutral: return "محايد"
        case .unknown: return "مجهول"
        }
    }
}

enum UnitType: String, CaseIterable {
    case infantry, armor, mech, artillery, mortar, recon, engineer, medical
    case signal, airdefense, hq, supply, op, checkpoint, roadblock, other

    var title: String {
        switch self {
        case .infantry: return "مشاة"
        case .armor: return "دروع"
        case .mech: return "مشاة آلية"
        case .artillery: return "مدفعية"
        case .mortar: return "هاون"
        case .recon: return "استطلاع"
        case .engineer: return "هندسة"
        case .medical: return "طبي"
        case .signal: return "اتصالات"
        case .airdefense: return "دفاع جوي"
        case .hq: return "مقر"
        case .supply: return "تجهيز"
        case .op: return "نقطة مراقبة"
        case .checkpoint: return "سيطرة"
        case .roadblock: return "مانع طريق"
        case .other: return "أخرى"
        }
    }
}

enum UnitSize: String, CaseIterable {
    case unsized = "-"
    case squad = "sq"
    case section = "sc"
    case platoon = "pl"
    case company = "co"
    case battalion = "bn"
    case brigade = "bg"
    case division = "dv"

    var title: String {
        switch self {
        case .unsized: return "بدون"
        case .squad: return "جماعة (•)"
        case .section: return "مفرزة (••)"
        case .platoon: return "فصيل (•••)"
        case .company: return "سرية ( | )"
        case .battalion: return "كتيبة / فوج ( || )"
        case .brigade: return "لواء ( X )"
        case .division: return "فرقة ( XX )"
        }
    }
}

enum MilSymbol {
    static var cache: [String: UIImage] = [:]

    static func key(_ a: Affiliation, _ t: UnitType, _ s: UnitSize) -> String {
        return "std|\(a.rawValue)|\(t.rawValue)|\(s.rawValue)"
    }

    static func parse(_ key: String) -> (Affiliation, UnitType, UnitSize)? {
        let p = key.split(separator: "|").map { String($0) }
        guard p.count == 4, p[0] == "std",
              let a = Affiliation(rawValue: p[1]),
              let t = UnitType(rawValue: p[2]),
              let s = UnitSize(rawValue: p[3]) else { return nil }
        return (a, t, s)
    }

    static func image(for key: String) -> UIImage? {
        if key.isEmpty { return nil }
        if let c = cache[key] { return c }
        var img: UIImage?
        if key.hasPrefix("img|") {
            img = loadCustom(String(key.dropFirst(4)))
        } else if let parsed = parse(key) {
            img = draw(parsed.0, parsed.1, parsed.2)
        }
        if let i = img { cache[key] = i }
        return img
    }

    // MARK: - الرموز المخصصة (صور من كراسة الرموز)

    static var folder: URL {
        return MapStore.shared.dir.appendingPathComponent("Symbols", isDirectory: true)
    }

    static func customNames() -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let ok = ["png", "jpg", "jpeg"]
        return all.filter { ok.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .sorted()
    }

    static func saveCustom(from url: URL) -> String? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            cache.removeValue(forKey: "img|" + url.lastPathComponent)
            return url.lastPathComponent
        } catch {
            return nil
        }
    }

    static func loadCustom(_ name: String) -> UIImage? {
        let path = folder.appendingPathComponent(name).path
        guard let src = UIImage(contentsOfFile: path) else { return nil }
        let maxSide: CGFloat = 48
        let ratio = min(maxSide / src.size.width, maxSide / src.size.height, 1)
        let size = CGSize(width: src.size.width * ratio, height: src.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            src.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - رسم الرموز القياسية

    static func draw(_ aff: Affiliation, _ type: UnitType, _ size: UnitSize) -> UIImage {
        let W: CGFloat = 44
        let H: CGFloat = 58
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt)
        return renderer.image { _ in
            let cx: CGFloat = W / 2
            let cy: CGFloat = H / 2
            var fillColor = UIColor.white
            var strokeColor = UIColor.black
            var framePath = UIBezierPath()
            var box = CGRect.zero

            switch aff {
            case .friendly:
                fillColor = UIColor(red: 0.50, green: 0.80, blue: 1.0, alpha: 1)
                strokeColor = UIColor(red: 0, green: 0.2, blue: 0.5, alpha: 1)
                box = CGRect(x: cx - 18, y: cy - 13, width: 36, height: 26)
                framePath = UIBezierPath(rect: box)
            case .hostile:
                fillColor = UIColor(red: 1.0, green: 0.50, blue: 0.50, alpha: 1)
                strokeColor = UIColor(red: 0.6, green: 0, blue: 0, alpha: 1)
                framePath.move(to: CGPoint(x: cx, y: cy - 17))
                framePath.addLine(to: CGPoint(x: cx + 17, y: cy))
                framePath.addLine(to: CGPoint(x: cx, y: cy + 17))
                framePath.addLine(to: CGPoint(x: cx - 17, y: cy))
                framePath.close()
                box = CGRect(x: cx - 9, y: cy - 7, width: 18, height: 14)
            case .neutral:
                fillColor = UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1)
                strokeColor = UIColor(red: 0, green: 0.4, blue: 0, alpha: 1)
                box = CGRect(x: cx - 14, y: cy - 14, width: 28, height: 28)
                framePath = UIBezierPath(rect: box)
            case .unknown:
                fillColor = UIColor(red: 1.0, green: 1.0, blue: 0.5, alpha: 1)
                strokeColor = UIColor(red: 0.5, green: 0.45, blue: 0, alpha: 1)
                box = CGRect(x: cx - 14, y: cy - 14, width: 28, height: 28)
                framePath = UIBezierPath(roundedRect: box, cornerRadius: 11)
            }

            fillColor.setFill()
            framePath.fill()
            strokeColor.setStroke()
            framePath.lineWidth = 2
            framePath.stroke()

            drawIcon(type, in: box)
            drawSize(size, cx: cx, y: 3)
        }
    }

    static func drawText(_ s: String, in b: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.black,
            .paragraphStyle: style
        ]
        let h: CGFloat = 12
        let r = CGRect(x: b.minX - 6, y: b.midY - h / 2, width: b.width + 12, height: h)
        (s as NSString).draw(in: r, withAttributes: attrs)
    }

    static func drawIcon(_ type: UnitType, in b: CGRect) {
        UIColor.black.setStroke()
        UIColor.black.setFill()
        let p = UIBezierPath()
        p.lineWidth = 1.8

        switch type {
        case .infantry:
            p.move(to: CGPoint(x: b.minX, y: b.minY))
            p.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
            p.move(to: CGPoint(x: b.maxX, y: b.minY))
            p.addLine(to: CGPoint(x: b.minX, y: b.maxY))
            p.stroke()
        case .armor:
            let o = UIBezierPath(ovalIn: b.insetBy(dx: 2, dy: 3))
            o.lineWidth = 1.8
            o.stroke()
        case .mech:
            p.move(to: CGPoint(x: b.minX, y: b.minY))
            p.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
            p.move(to: CGPoint(x: b.maxX, y: b.minY))
            p.addLine(to: CGPoint(x: b.minX, y: b.maxY))
            p.stroke()
            let o = UIBezierPath(ovalIn: b.insetBy(dx: 2, dy: 3))
            o.lineWidth = 1.8
            o.stroke()
        case .artillery:
            UIBezierPath(ovalIn: CGRect(x: b.midX - 4, y: b.midY - 4, width: 8, height: 8)).fill()
        case .mortar:
            UIBezierPath(ovalIn: CGRect(x: b.midX - 4, y: b.midY - 1, width: 8, height: 8)).fill()
            p.move(to: CGPoint(x: b.midX, y: b.midY + 1))
            p.addLine(to: CGPoint(x: b.midX, y: b.minY))
            p.stroke()
        case .recon:
            p.move(to: CGPoint(x: b.minX, y: b.maxY))
            p.addLine(to: CGPoint(x: b.maxX, y: b.minY))
            p.stroke()
        case .engineer:
            p.move(to: CGPoint(x: b.minX + 2, y: b.maxY))
            p.addLine(to: CGPoint(x: b.minX + 2, y: b.minY + 2))
            p.addLine(to: CGPoint(x: b.maxX - 2, y: b.minY + 2))
            p.addLine(to: CGPoint(x: b.maxX - 2, y: b.maxY))
            p.stroke()
        case .medical:
            p.lineWidth = 3
            p.move(to: CGPoint(x: b.midX, y: b.minY))
            p.addLine(to: CGPoint(x: b.midX, y: b.maxY))
            p.move(to: CGPoint(x: b.minX + 2, y: b.midY))
            p.addLine(to: CGPoint(x: b.maxX - 2, y: b.midY))
            p.stroke()
        case .signal:
            p.move(to: CGPoint(x: b.minX + 2, y: b.maxY))
            p.addLine(to: CGPoint(x: b.midX - 1, y: b.midY + 1))
            p.addLine(to: CGPoint(x: b.midX + 1, y: b.midY - 1))
            p.addLine(to: CGPoint(x: b.maxX - 2, y: b.minY))
            p.stroke()
        case .airdefense:
            p.addArc(withCenter: CGPoint(x: b.midX, y: b.maxY - 2), radius: 9,
                     startAngle: CGFloat.pi, endAngle: 0, clockwise: true)
            p.stroke()
        case .hq:
            drawText("HQ", in: b)
        case .supply:
            drawText("SUP", in: b)
        case .op:
            drawText("OP", in: b)
        case .checkpoint:
            drawText("CP", in: b)
        case .roadblock:
            p.lineWidth = 3
            p.move(to: CGPoint(x: b.minX, y: b.midY))
            p.addLine(to: CGPoint(x: b.maxX, y: b.midY))
            p.stroke()
        case .other:
            drawText("?", in: b)
        }
    }

    static func drawSize(_ s: UnitSize, cx: CGFloat, y: CGFloat) {
        UIColor.black.setFill()
        UIColor.black.setStroke()

        func dots(_ n: Int) {
            let r: CGFloat = 2
            let gap: CGFloat = 6
            let total = CGFloat(n - 1) * gap
            for i in 0..<n {
                let x = cx - total / 2 + CGFloat(i) * gap
                UIBezierPath(ovalIn: CGRect(x: x - r, y: y + 2, width: 2 * r, height: 2 * r)).fill()
            }
        }

        func bars(_ n: Int) {
            let gap: CGFloat = 4
            let total = CGFloat(n - 1) * gap
            for i in 0..<n {
                let x = cx - total / 2 + CGFloat(i) * gap
                let b = UIBezierPath()
                b.lineWidth = 2
                b.move(to: CGPoint(x: x, y: y))
                b.addLine(to: CGPoint(x: x, y: y + 8))
                b.stroke()
            }
        }

        func cross(_ x: CGFloat) {
            let b = UIBezierPath()
            b.lineWidth = 1.8
            b.move(to: CGPoint(x: x - 4, y: y))
            b.addLine(to: CGPoint(x: x + 4, y: y + 8))
            b.move(to: CGPoint(x: x + 4, y: y))
            b.addLine(to: CGPoint(x: x - 4, y: y + 8))
            b.stroke()
        }

        switch s {
        case .unsized: break
        case .squad: dots(1)
        case .section: dots(2)
        case .platoon: dots(3)
        case .company: bars(1)
        case .battalion: bars(2)
        case .brigade: cross(cx)
        case .division:
            cross(cx - 5)
            cross(cx + 5)
        }
    }
}
