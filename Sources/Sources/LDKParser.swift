import Foundation
import CoreLocation

struct LDKPoint: Identifiable {
    let id = UUID()
    let name: String
    let color: String
    let coordinate: CLLocationCoordinate2D
}

enum LDKParser {
    static func parse(url: URL) -> [LDKPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data: data)
    }

    static func parse(data: Data) -> [LDKPoint] {
        let b = [UInt8](data)
        let end = b.count
        var result: [LDKPoint] = []
        var seen = Set<String>()

        func u32(_ p: Int) -> Int? {
            guard p >= 0, p + 4 <= end else { return nil }
            return (Int(b[p]) << 24) | (Int(b[p + 1]) << 16) | (Int(b[p + 2]) << 8) | Int(b[p + 3])
        }
        func i32(_ p: Int) -> Int32? {
            guard let v = u32(p) else { return nil }
            return Int32(bitPattern: UInt32(v))
        }
        func str(_ p: Int, _ n: Int) -> String? {
            guard n >= 0, p >= 0, p + n <= end else { return nil }
            return String(decoding: b[p..<(p + n)], as: UTF8.self)
        }

        var i = 0
        while i + 13 < end {
            guard b[i] == 0x65, b[i + 1] == 0x50, b[i + 2] == 0x50,
                  b[i + 3] == 0x0A, b[i + 4] == 0x01 else { i += 1; continue }

            var p = i + 5
            guard let hi = u32(p), hi == 0, let n = u32(p + 4), n <= 50 else { i += 1; continue }
            p += 8

            var name = ""
            var color = ""
            var ok = true
            for _ in 0..<n {
                guard let kl = u32(p), let k = str(p + 4, kl),
                      let vl = u32(p + 4 + kl), let v = str(p + 8 + kl, vl) else { ok = false; break }
                p += 8 + kl + vl
                if k == "name" { name = v } else if k == "color" { color = v }
            }
            guard ok, let ln = u32(p + 8), ln >= 8,
                  let lonRaw = i32(p + 12), let latRaw = i32(p + 16) else { i += 1; continue }

            let lon = Double(lonRaw) / 1e7
            let lat = Double(latRaw) / 1e7
            if abs(lon) <= 180, abs(lat) <= 90 {
                let key = "\(name)|\(lon)|\(lat)"
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(LDKPoint(name: name, color: color,
                                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                }
            }
            i = p
        }
        return result
    }
}
