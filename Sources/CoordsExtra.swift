import Foundation
import CoreLocation

extension Coords {

    // MARK: - المساحة والمحيط

    /// مساحة مضلع جغرافي بالمتر المربع (صيغة Spherical Excess)
    static func polygonArea(_ coords: [CLLocationCoordinate2D]) -> Double {
        if coords.count < 3 { return 0 }
        let R = 6378137.0
        var total = 0.0
        let n = coords.count
        for i in 0..<n {
            let j = (i + 1) % n
            let lat1 = coords[i].latitude * Double.pi / 180
            let lat2 = coords[j].latitude * Double.pi / 180
            let lon1 = coords[i].longitude * Double.pi / 180
            let lon2 = coords[j].longitude * Double.pi / 180
            total += (lon2 - lon1) * (2 + sin(lat1) + sin(lat2))
        }
        return abs(total * R * R / 2)
    }

    /// محيط مضلع جغرافي بالمتر
    static func polygonPerimeter(_ coords: [CLLocationCoordinate2D]) -> Double {
        if coords.count < 2 { return 0 }
        var total = 0.0
        for i in 0..<coords.count {
            let j = (i + 1) % coords.count
            total += distance(coords[i], coords[j])
        }
        return total
    }

    // MARK: - الاتجاه العكسي

    /// الاتجاه العكسي (Back Azimuth)
    static func backBearing(_ deg: Double) -> Double {
        var b = deg + 180
        if b >= 360 { b -= 360 }
        return b
    }

    // MARK: - تنسيق

    static func formatArea(_ m2: Double) -> String {
        if m2 >= 1_000_000 {
            return String(format: "%.2f km²", m2 / 1_000_000)
        } else if m2 >= 10_000 {
            return String(format: "%.2f هكتار", m2 / 10_000)
        }
        return String(format: "%.0f م²", m2)
    }

    static func formatPerimeter(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.2f km", m / 1000) }
        return String(format: "%.0f م", m)
    }

    static func formatAltitude(_ m: Double) -> String {
        if m.isNaN || m < -1000 { return "—" }
        return String(format: "%.0f م", m)
    }

    static func formatAccuracy(_ m: Double) -> String {
        if m <= 0 || m > 1000 { return "—" }
        return String(format: "±%.0f م", m)
    }
}
