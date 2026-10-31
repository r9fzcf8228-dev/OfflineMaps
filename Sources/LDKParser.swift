import Foundation
import CoreLocation
import UIKit

struct LDKPoint: Identifiable {
    let id = UUID()
    let name: String
    let color: String
    let comment: String
    let coordinate: CLLocationCoordinate2D
}

struct LDKShape: Identifiable {
    enum Kind { case line, area, track }
    let id = UUID()
    let kind: Kind
    let name: String
    let color: String
    let dashed: Bool
    let coords: [CLLocationCoordinate2D]
}

struct LDKData {
    let id = UUID()
    var points: [LDKPoint] = []
    var shapes: [LDKShape] = []
    var isEmpty: Bool { points.isEmpty && shapes.isEmpty }
}

enum LDKStyle {
    static func color(_ name: String, fallback: UIColor = .systemRed) -> UIColor {
        let n = name.lowercased()
        if n.hasPrefix("#") {
            var hex = String(n.dropFirst())
            if hex.count == 6 { hex = "ff" + hex }
            if hex.count == 8, let v = UInt32(hex, radix: 16) {
                let a = CGFloat((v >> 24) & 0xff) / 255
                let r = CGFloat((v >> 16) & 0xff) / 255
                let g = CGFloat((v >> 8) & 0xff) / 255
                let b = CGFloat(v & 0xff) / 255
                return UIColor(red: r, green: g, blue: b, alpha: max(a, 0.5))
            }
            return fallback
        }
        switch n {
        case "red": return .systemRed
        case "blue": return .systemBlue
        case "lightblue": return UIColor(red: 0.45, green: 0.78, blue: 0.98, alpha: 1)
        case "green": return .systemGreen
        case "lightgreen": return UIColor(red: 0.55, green: 0.92, blue: 0.55, alpha: 1)
        case "yellow": return .systemYellow
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        case "magenta": return .magenta
        case "cyan": return .cyan
        case "black": return .black
        case "gray", "grey": return .gray
        case "white": return .white
        default: return fallback
        }
    }

    static func colorFromIcon(_ icon: String) -> String {
        let s = icon.lowercased()
        for n in ["blue", "red", "green", "yellow", "orange", "purple", "magenta", "cyan", "black", "gray", "white"] {
            if s.contains(n) { return n }
        }
        return ""
    }
}

enum Coords {
    static let bands = Array("CDEFGHJKLMNPQRSTUVWX")
    static let colSets = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"]
    static let rowLetters = Array("ABCDEFGHJKLMNPQRSTUV")

    static func utm(_ c: CLLocationCoordinate2D) -> (zone: Int, band: Character, easting: Double, northing: Double)? {
        let lat = c.latitude
        let lon = c.longitude
        guard lat >= -80, lat < 84, lon >= -180, lon <= 180 else { return nil }
        var zone = Int(floor((lon + 180) / 6)) + 1
        if zone > 60 { zone = 60 }
        let lon0 = Double((zone - 1) * 6 - 180 + 3) * Double.pi / 180
        let phi = lat * Double.pi / 180
        let lam = lon * Double.pi / 180 - lon0
        let f = 1.0 / 298.257223563
        let a = 6378137.0
        let k0 = 0.9996
        let n = f / (2 - f)
        let e = sqrt(f * (2 - f))
        let aa = a / (1 + n) * (1 + n * n / 4 + pow(n, 4) / 64)
        let al1 = n / 2 - 2 * n * n / 3 + 5 * pow(n, 3) / 16
        let al2 = 13 * n * n / 48 - 3 * pow(n, 3) / 5
        let al3 = 61 * pow(n, 3) / 240
        let al = [al1, al2, al3]
        let t = tan(phi)
        let sig = sinh(e * atanh(e * t / sqrt(1 + t * t)))
        let tp = t * sqrt(1 + sig * sig) - sig * sqrt(1 + t * t)
        let xi = atan2(tp, cos(lam))
        let eta = asinh(sin(lam) / sqrt(tp * tp + cos(lam) * cos(lam)))
        var xs = xi
        var es = eta
        for j in 1...3 {
            let jj = Double(j)
            xs += al[j - 1] * sin(2 * jj * xi) * cosh(2 * jj * eta)
            es += al[j - 1] * cos(2 * jj * xi) * sinh(2 * jj * eta)
        }
        let easting = 500000 + k0 * aa * es
        var northing = k0 * aa * xs
        if lat < 0 { northing += 10000000 }
        let bi = min(Int(floor((lat + 80) / 8)), 19)
        return (zone, bands[bi], easting, northing)
    }

    static func pad5(_ v: Int) -> String {
        let s = String(v)
        return String(repeating: "0", count: max(0, 5 - s.count)) + s
    }

    static func utmString(_ c: CLLocationCoordinate2D) -> String {
        guard let u = utm(c) else { return "-" }
        return "\(u.zone)\(u.band) \(Int(u.easting.rounded())) \(Int(u.northing.rounded()))"
    }

    static func mgrsString(_ c: CLLocationCoordinate2D) -> String {
        guard let u = utm(c) else { return "-" }
        let cols = Array(colSets[(u.zone - 1) % 3])
        let ci = Int(u.easting / 100000) - 1
        guard ci >= 0, ci < cols.count else { return "-" }
        let off = (u.zone % 2 == 0) ? 5 : 0
        let ri = (Int(u.northing / 100000) + off) % 20
        let e = Int(u.easting) % 100000
        let n = Int(u.northing) % 100000
        return "\(u.zone)\(u.band) \(cols[ci])\(rowLetters[ri]) \(pad5(e)) \(pad5(n))"
    }

    static func ddString(_ c: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }

    static func summary(_ c: CLLocationCoordinate2D) -> String {
        return "UTM  \(utmString(c))\nMGRS \(mgrsString(c))\n\(ddString(c))"
    }
}

enum LDKParser {
    static func parse(url: URL) -> LDKData {
        guard let d = try? Data(contentsOf: url) else { return LDKData() }
        return parse(data: d)
    }

    static func parse(data: Data) -> LDKData {
        let b = [UInt8](data)
        let end = b.count
        var out = LDKData()
        var seen = Set<String>()

        func u32(_ p: Int) -> Int? {
            guard p >= 0, p + 4 <= end else { return nil }
            return (Int(b[p]) << 24) | (Int(b[p + 1]) << 16) | (Int(b[p + 2]) << 8) | Int(b[p + 3])
        }
        func i32(_ p: Int) -> Int32? {
            guard let v = u32(p) else { return nil }
            return Int32(bitPattern: UInt32(v))
        }
        func i64(_ p: Int) -> Int64? {
            guard p >= 0, p + 8 <= end else { return nil }
            var v: UInt64 = 0
            for k in 0..<8 { v = (v << 8) | UInt64(b[p + k]) }
            return Int64(bitPattern: v)
        }
        func str(_ p: Int, _ n: Int) -> String? {
            guard n >= 0, p >= 0, p + n <= end else { return nil }
            return String(decoding: b[p..<(p + n)], as: UTF8.self)
        }
        func readStrings(_ start: Int) -> ([String: String], Int)? {
            guard let n = u32(start), n <= 50 else { return nil }
            var p = start + 4
            var a: [String: String] = [:]
            for _ in 0..<n {
                guard let kl = u32(p), let k = str(p + 4, kl),
                      let vl = u32(p + 4 + kl), let v = str(p + 8 + kl, vl) else { return nil }
                p += 8 + kl + vl
                a[k] = v
            }
            return (a, p)
        }

        var i = 0
        while i + 40 < end {
            let t = b[i]
            guard t >= 0x65, t <= 0x69, b[i + 1] == 0x50, b[i + 2] == 0x50,
                  b[i + 3] >= 0x0A, b[i + 3] <= 0x0E, b[i + 4] == 0x01 else { i += 1; continue }

            var p = i + 9

            if t == 0x66 { i += 5; continue }

            if t == 0x65 {
                guard let r = readStrings(p) else { i += 1; continue }
                let q = r.1
                guard let ln = u32(q + 8), ln >= 8,
                      let lonRaw = i32(q + 12), let latRaw = i32(q + 16) else { i += 1; continue }
                let lon = Double(lonRaw) / 1e7
                let lat = Double(latRaw) / 1e7
                if abs(lon) <= 180, abs(lat) <= 90 {
                    let a = r.0
                    let name = a["name"] ?? ""
                    var color = a["color"] ?? ""
                    if color.isEmpty { color = LDKStyle.colorFromIcon(a["icon"] ?? "") }
                    if color.isEmpty { color = "red" }
                    let key = "e|\(name)|\(lon)|\(lat)|\(color)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        out.points.append(LDKPoint(name: name, color: color,
                                                   comment: a["comment"] ?? "",
                                                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                    }
                }
                i = q
                continue
            }

            // g = خط، h = مسار، i = منطقة
            guard let nint = u32(p), nint <= 20 else { i += 1; continue }
            p += 4
            var ints: [String: Int64] = [:]
            var ok = true
            for _ in 0..<nint {
                guard let kl = u32(p), kl < 64, let k = str(p + 4, kl),
                      let v = i64(p + 4 + kl + 4) else { ok = false; break }
                ints[k] = v
                p += 4 + kl + 4 + 8
            }
            guard ok else { i += 1; continue }
            p += 8
            guard let r = readStrings(p) else { i += 1; continue }
            let attrs = r.0
            p = r.1
            guard let lon0 = ints["lon"], let lat0 = ints["lat"] else { i += 1; continue }

            let lonKey = Int32(truncatingIfNeeded: lon0)
            let latKey = Int32(truncatingIfNeeded: lat0)
            var q = -1
            var s = p
            let limit = min(p + 80, end - 12)
            while s < limit {
                if b[s] == 0, b[s + 1] == 0, b[s + 2] == 0, b[s + 3] == 8,
                   i32(s + 4) == lonKey, i32(s + 8) == latKey {
                    q = s
                    break
                }
                s += 1
            }
            guard q >= 0 else { i += 1; continue }

            var coords: [CLLocationCoordinate2D] = []
            while q + 12 <= end {
                if b[q] == 0, b[q + 1] == 0, b[q + 2] == 0, b[q + 3] == 8,
                   let lo = i32(q + 4), let la = i32(q + 8) {
                    let lon = Double(lo) / 1e7
                    let lat = Double(la) / 1e7
                    if abs(lon) <= 180, abs(lat) <= 90 {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    q += 12
                } else if q + 16 <= end {
                    var zeros = true
                    for k in 0..<8 where b[q + k] != 0 { zeros = false }
                    let marker = b[q + 8] == 0xff && b[q + 9] == 0xff && b[q + 10] == 0xff && b[q + 11] == 0xff
                    let len8 = b[q + 12] == 0 && b[q + 13] == 0 && b[q + 14] == 0 && b[q + 15] == 8
                    if zeros && marker && len8 { q += 12 } else { break }
                } else {
                    break
                }
            }

            let kind: LDKShape.Kind = (t == 0x67) ? .line : ((t == 0x68) ? .track : .area)
            let minPts = (kind == .area) ? 3 : 2
            if coords.count >= minPts, let f = coords.first {
                let name = attrs["name"] ?? ""
                var color = attrs["color"] ?? ""
                if color.isEmpty {
                    color = (kind == .area) ? "yellow" : ((kind == .line) ? "black" : "red")
                }
                let key = "\(t)|\(name)|\(f.latitude)|\(f.longitude)|\(coords.count)|\(color)"
                if !seen.contains(key) {
                    seen.insert(key)
                    out.shapes.append(LDKShape(kind: kind, name: name, color: color,
                                               dashed: attrs["dashes"] != nil, coords: coords))
                }
            }
            i = q
        }
        return out
    }
}
