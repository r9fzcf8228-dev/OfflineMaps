import Foundation
import MapKit
import CoreLocation

struct RouteStep {
    let text: String
    let icon: String
    let start: CLLocationCoordinate2D
}

struct RouteResult {
    let coords: [CLLocationCoordinate2D]
    let distance: Double
    let duration: Double
    let steps: [RouteStep]
}

enum Routing {
    static let defaultServer = "https://router.project-osrm.org"
    private static var appleHolder: MKDirections?

    static var server: String {
        var s = UserDefaults.standard.string(forKey: "routeServer") ?? defaultServer
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultServer }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // يحاول أولاً خريطة الطرق المفتوحة (OSM عبر OSRM) ثم خرائط Apple. النتيجة تعود على الخيط الرئيسي.
    static func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                      completion: @escaping (RouteResult?, String) -> Void) {
        osrm(from: a, to: b) { r1, e1 in
            if let r = r1 {
                DispatchQueue.main.async { completion(r, "OSM") }
                return
            }
            apple(from: a, to: b) { r2, e2 in
                DispatchQueue.main.async {
                    if let r = r2 {
                        completion(r, "Apple")
                    } else {
                        completion(nil, e1 + " | " + e2)
                    }
                }
            }
        }
    }

    // MARK: - OSRM

    private static func osrm(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                             completion: @escaping (RouteResult?, String) -> Void) {
        let urlStr = "\(server)/route/v1/driving/\(a.longitude),\(a.latitude);\(b.longitude),\(b.latitude)?overview=full&geometries=geojson&steps=true"
        guard let url = URL(string: urlStr) else {
            completion(nil, "رابط الخادم غير صحيح")
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("OfflineMapsApp/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let e = error {
                completion(nil, e.localizedDescription)
                return
            }
            guard let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                completion(nil, "رد غير مفهوم من الخادم")
                return
            }
            guard (json["code"] as? String) == "Ok",
                  let routes = json["routes"] as? [[String: Any]],
                  let first = routes.first else {
                let msg = (json["message"] as? String) ?? (json["code"] as? String) ?? "لا يوجد طريق"
                completion(nil, msg)
                return
            }
            if let r = parse(first) {
                completion(r, "")
            } else {
                completion(nil, "تعذر قراءة المسار")
            }
        }.resume()
    }

    private static func parse(_ route: [String: Any]) -> RouteResult? {
        guard let geo = route["geometry"] as? [String: Any],
              let raw = geo["coordinates"] as? [[Double]] else { return nil }
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(raw.count)
        for p in raw where p.count >= 2 {
            coords.append(CLLocationCoordinate2D(latitude: p[1], longitude: p[0]))
        }
        if coords.count < 2 { return nil }

        var steps: [RouteStep] = []
        let legs = route["legs"] as? [[String: Any]] ?? []
        for leg in legs {
            let ss = leg["steps"] as? [[String: Any]] ?? []
            for s in ss {
                guard let man = s["maneuver"] as? [String: Any],
                      let loc = man["location"] as? [Double], loc.count >= 2 else { continue }
                let type = man["type"] as? String ?? ""
                let mod = man["modifier"] as? String ?? ""
                let name = s["name"] as? String ?? ""
                let exit = man["exit"] as? Int ?? 0
                let text = instruction(type: type, modifier: mod, name: name, exit: exit)
                steps.append(RouteStep(text: text,
                                       icon: Navigator.icon(for: text),
                                       start: CLLocationCoordinate2D(latitude: loc[1], longitude: loc[0])))
            }
        }

        let dist = route["distance"] as? Double ?? 0
        let dur = route["duration"] as? Double ?? 0
        return RouteResult(coords: coords, distance: dist, duration: dur, steps: steps)
    }

    private static func ordinal(_ n: Int) -> String {
        let names = ["", "الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن"]
        if n >= 1 && n < names.count { return names[n] }
        return "رقم \(n)"
    }

    private static func instruction(type: String, modifier: String, name: String, exit: Int) -> String {
        let road = name.isEmpty ? "" : " إلى " + name
        let onRoad = name.isEmpty ? "" : " على " + name

        switch type {
        case "depart":
            return "انطلق" + onRoad
        case "arrive":
            return "وصلت إلى وجهتك"
        case "roundabout", "rotary", "roundabout turn":
            if exit > 0 { return "ادخل الدوار وخذ المخرج " + ordinal(exit) + road }
            return "ادخل الدوار" + road
        case "exit roundabout", "exit rotary":
            return "اخرج من الدوار" + road
        case "fork":
            if modifier.contains("left") { return "عند التفرع ابقَ يساراً" + road }
            if modifier.contains("right") { return "عند التفرع ابقَ يميناً" + road }
            return "عند التفرع تابع" + road
        default:
            break
        }

        switch modifier {
        case "uturn": return "استدر للخلف"
        case "sharp left": return "انعطف بحدة يساراً" + road
        case "left": return "انعطف يساراً" + road
        case "slight left": return "انحرف قليلاً يساراً" + road
        case "sharp right": return "انعطف بحدة يميناً" + road
        case "right": return "انعطف يميناً" + road
        case "slight right": return "انحرف قليلاً يميناً" + road
        default: return "استمر مباشرة" + onRoad
        }
    }

    // MARK: - Apple (احتياطي)

    private static func apple(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                              completion: @escaping (RouteResult?, String) -> Void) {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        req.transportType = .automobile
        let d = MKDirections(request: req)
        appleHolder = d
        d.calculate { resp, error in
            guard let r = resp?.routes.first else {
                completion(nil, error?.localizedDescription ?? "لا يوجد طريق")
                return
            }
            func coordsOf(_ pl: MKPolyline) -> [CLLocationCoordinate2D] {
                var cs = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pl.pointCount)
                if pl.pointCount > 0 {
                    pl.getCoordinates(&cs, range: NSRange(location: 0, length: pl.pointCount))
                }
                return cs
            }
            let cs = coordsOf(r.polyline)
            if cs.count < 2 {
                completion(nil, "مسار فارغ")
                return
            }
            var steps: [RouteStep] = []
            for s in r.steps {
                if s.instructions.isEmpty { continue }
                if let first = coordsOf(s.polyline).first {
                    steps.append(RouteStep(text: s.instructions,
                                           icon: Navigator.icon(for: s.instructions),
                                           start: first))
                }
            }
            completion(RouteResult(coords: cs, distance: r.distance,
                                   duration: r.expectedTravelTime, steps: steps), "")
        }
    }
}
