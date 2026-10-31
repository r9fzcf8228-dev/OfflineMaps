import Foundation
import CoreLocation

extension Coords {

    // تحويل الأرقام العربية والفواصل العربية إلى إنجليزية
    static func normalize(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            let v = u.value
            if v >= 0x0660 && v <= 0x0669 {
                out.append(String(v - 0x0660))
            } else if v >= 0x06F0 && v <= 0x06F9 {
                out.append(String(v - 0x06F0))
            } else if v == 0x060C || v == 0x061B {
                out.append(",")
            } else if v == 0x066B {
                out.append(".")
            } else {
                out.unicodeScalars.append(u)
            }
        }
        return out.uppercased()
    }

    // UTM إلى خط عرض وطول
    static func fromUTM(zone: Int, north: Bool, easting: Double, northing: Double) -> CLLocationCoordinate2D? {
        guard zone >= 1, zone <= 60 else { return nil }
        let f = 1.0 / 298.257223563
        let a = 6378137.0
        let k0 = 0.9996
        let n = f / (2 - f)
        let aa = a / (1 + n) * (1 + n * n / 4 + pow(n, 4) / 64)
        let b1 = n / 2 - 2 * n * n / 3 + 37 * pow(n, 3) / 96
        let b2 = n * n / 48 + pow(n, 3) / 15
        let b3 = 17 * pow(n, 3) / 480
        let d1 = 2 * n - 2 * n * n / 3 - 2 * pow(n, 3)
        let d2 = 7 * n * n / 3 - 8 * pow(n, 3) / 5
        let d3 = 56 * pow(n, 3) / 15
        let bs = [b1, b2, b3]
        let ds = [d1, d2, d3]

        let nn = north ? northing : northing - 10000000
        let xi = nn / (k0 * aa)
        let eta = (easting - 500000) / (k0 * aa)
        var xp = xi
        var ep = eta
        for j in 1...3 {
            let jj = Double(j)
            xp -= bs[j - 1] * sin(2 * jj * xi) * cosh(2 * jj * eta)
            ep -= bs[j - 1] * cos(2 * jj * xi) * sinh(2 * jj * eta)
        }
        let chi = asin(sin(xp) / cosh(ep))
        var phi = chi
        for j in 1...3 {
            phi += ds[j - 1] * sin(2 * Double(j) * chi)
        }
        let lon0 = Double((zone - 1) * 6 - 180 + 3) * Double.pi / 180
        let lam = lon0 + atan2(sinh(ep), cos(xp))
        let lat = phi * 180 / Double.pi
        let lon = lam * 180 / Double.pi
        guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // قراءة MGRS مثل: 38S MD 15154 71396 أو 38SMD1515471396
    static func parseMGRS(_ t: String) -> CLLocationCoordinate2D? {
        let s = t.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        let pattern = "^(\\d{1,2})([C-HJ-NP-X])([A-HJ-NP-Z])([A-HJ-NP-V])(\\d*)$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 6 else { return nil }
        let zone = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let bandStr = ns.substring(with: m.range(at: 2))
        let colStr = ns.substring(with: m.range(at: 3))
        let rowStr = ns.substring(with: m.range(at: 4))
        let digits = ns.substring(with: m.range(at: 5))
        guard zone >= 1, zone <= 60, digits.count % 2 == 0, digits.count <= 10 else { return nil }
        guard let bandCh = bandStr.first, let colCh = colStr.first, let rowCh = rowStr.first else { return nil }

        let half = digits.count / 2
        var e = 0.0
        var n = 0.0
        if half > 0 {
            let eDigits = String(digits.prefix(half))
            let nDigits = String(digits.suffix(half))
            let scale = pow(10.0, Double(5 - half))
            e = (Double(eDigits) ?? 0) * scale
            n = (Double(nDigits) ?? 0) * scale
        }

        let colSet = Array(colSets[(zone - 1) % 3])
        guard let ci = colSet.firstIndex(of: colCh) else { return nil }
        let easting = Double(ci + 1) * 100000 + e

        guard let ri = rowLetters.firstIndex(of: rowCh) else { return nil }
        let off = (zone % 2 == 0) ? 5 : 0
        let n100 = (ri - off + 20) % 20
        var northing = Double(n100) * 100000 + n

        guard let bi = bands.firstIndex(of: bandCh) else { return nil }
        let southLat = Double(-80 + 8 * bi)
        let cm = Double((zone - 1) * 6 - 180 + 3)
        guard let ref = utm(CLLocationCoordinate2D(latitude: southLat, longitude: cm)) else { return nil }
        var guardCount = 0
        while northing < ref.northing - 1 && guardCount < 10 {
            northing += 2000000
            guardCount += 1
        }
        return fromUTM(zone: zone, north: bi >= 10, easting: easting, northing: northing)
    }

    // قراءة UTM مثل: 38S 415154 3871396
    static func parseUTM(_ t: String) -> CLLocationCoordinate2D? {
        let pattern = "^(\\d{1,2})\\s*([C-HJ-NP-X])\\s+(\\d{5,7})(?:\\.\\d+)?\\s*M?\\s*[,;]?\\s*(\\d{6,8})(?:\\.\\d+)?\\s*M?$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = t as NSString
        guard let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 5 else { return nil }
        let zone = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let bandStr = ns.substring(with: m.range(at: 2))
        let e = Double(ns.substring(with: m.range(at: 3))) ?? 0
        let n = Double(ns.substring(with: m.range(at: 4))) ?? 0
        guard let bandCh = bandStr.first, let bi = bands.firstIndex(of: bandCh) else { return nil }
        return fromUTM(zone: zone, north: bi >= 10, easting: e, northing: n)
    }

    // قراءة خط عرض وطول عشري: 34.98159, 44.07042
    static func parseDD(_ t: String) -> CLLocationCoordinate2D? {
        let cleaned = t.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
        let parts = cleaned.split(separator: " ").map { String($0) }
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else { return nil }
        if abs(a) <= 90 && abs(b) <= 180 {
            return CLLocationCoordinate2D(latitude: a, longitude: b)
        }
        return nil
    }

    // قراءة أي صيغة
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        let t = normalize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let c = parseMGRS(t) { return c }
        if let c = parseUTM(t) { return c }
        return parseDD(t)
    }

    // المسافة بالمتر
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return la.distance(from: lb)
    }

    static func length(_ cs: [CLLocationCoordinate2D]) -> Double {
        var total = 0.0
        if cs.count < 2 { return 0 }
        for i in 1..<cs.count {
            total += distance(cs[i - 1], cs[i])
        }
        return total
    }

    // الاتجاه (السمت) بالدرجات من 0 إلى 360
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * Double.pi / 180
        let p2 = b.latitude * Double.pi / 180
        let dl = (b.longitude - a.longitude) * Double.pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        var deg = atan2(y, x) * 180 / Double.pi
        if deg < 0 { deg += 360 }
        return deg
    }

    // الميل العسكري: الدائرة 6400 ميل
    static func mils(_ deg: Double) -> Int {
        return Int((deg * 6400 / 360).rounded()) % 6400
    }

    static func formatDistance(_ m: Double) -> String {
        if m >= 1000 {
            return String(format: "%.2f km", m / 1000)
        }
        return String(format: "%.0f m", m)
    }

    static func formatDuration(_ s: Double) -> String {
        let mins = Int((s / 60).rounded())
        if mins >= 60 {
            return "\(mins / 60) h \(mins % 60) min"
        }
        return "\(mins) min"
    }
}
