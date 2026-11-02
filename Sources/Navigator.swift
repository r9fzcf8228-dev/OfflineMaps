import Foundation
import MapKit
import CoreLocation
import AVFoundation
import Network

final class NetworkMonitor: ObservableObject {
    @Published var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = (path.status == .satisfied)
            DispatchQueue.main.async {
                self?.online = ok
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.monitor"))
    }
}

struct NavStep {
    let text: String
    let icon: String
    let start: CLLocationCoordinate2D
}

final class Navigator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var active = false
    @Published var arrived = false
    @Published var target: CLLocationCoordinate2D?
    @Published var targetName = ""
    @Published var distance: Double = 0
    @Published var bearing: Double = 0
    @Published var heading: Double = 0
    @Published var remaining: Double = 0
    @Published var eta: Double = 0
    @Published var speed: Double = 0
    @Published var instruction = ""
    @Published var maneuver = "arrow.up"
    @Published var nextInstruction = ""
    @Published var nextManeuver = "arrow.up"
    @Published var stepDistance: Double = 0
    @Published var progressIndex = 0
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var routeRevision = 0
    @Published var roadMode = false
    @Published var voice = true
    @Published var status = ""
    @Published var hasFix = false

    private let manager = CLLocationManager()
    private let synth = AVSpeechSynthesizer()
    private var directions: MKDirections?
    private var steps: [NavStep] = []
    private var stepIndex = 0
    private var spokeIndex = -1
    private var spokeStage = 0
    private var cum: [Double] = []
    private var routeTotal = 0.0
    private var expected = 0.0
    private var needsRoute = false
    private var online = true
    private var offRoute = 0
    private var lastReroute = Date.distantPast
    private var lastLoc: CLLocation?
    private var lastDirect: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    // MARK: - التحكم

    func start(to c: CLLocationCoordinate2D, name: String, online: Bool) {
        self.online = online
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.headingFilter = 3
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        target = c
        targetName = name
        arrived = false
        active = true
        roadMode = false
        steps = []
        routeCoords = []
        cum = []
        instruction = ""
        nextInstruction = ""
        maneuver = "arrow.up"
        nextManeuver = "arrow.up"
        stepIndex = 0
        spokeIndex = -1
        spokeStage = 0
        progressIndex = 0
        offRoute = 0
        needsRoute = true
        hasFix = false
        lastDirect = nil
        status = "جاري تحديد موقعك..."
        routeRevision += 1
        if let loc = manager.location, loc.horizontalAccuracy >= 0 {
            firstFix(loc)
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        synth.stopSpeaking(at: .immediate)
        directions?.cancel()
        active = false
        arrived = false
        roadMode = false
        steps = []
        routeCoords = []
        target = nil
        instruction = ""
        nextInstruction = ""
        progressIndex = 0
        speed = 0
        routeRevision += 1
    }

    // MARK: - المسار

    private func firstFix(_ loc: CLLocation) {
        hasFix = true
        lastLoc = loc
        update(loc)
        if needsRoute {
            needsRoute = false
            if online {
                requestRoute(from: loc.coordinate)
            } else {
                directMode(from: loc)
            }
        }
    }

    private func directMode(from loc: CLLocation) {
        guard let t = target else { return }
        roadMode = false
        status = "ملاحة مباشرة بالاتجاه والمسافة"
        routeCoords = [loc.coordinate, t]
        routeRevision += 1
    }

    private func requestRoute(from: CLLocationCoordinate2D) {
        guard let t = target else { return }
        status = "جاري حساب الطريق..."
        Routing.route(from: from, to: t) { [weak self] result, info in
            guard let self = self, self.active else { return }
            if let r = result {
                self.apply(r, provider: info)
            } else if let loc = self.lastLoc {
                self.directMode(from: loc)
                self.status = "تعذر حساب الطريق: \(info)"
            }
        }
    }

    private func apply(_ r: RouteResult, provider: String) {
        if r.coords.count < 2 { return }
        routeCoords = r.coords
        var c: [Double] = [0]
        var acc = 0.0
        for i in 1..<r.coords.count {
            acc += Coords.distance(r.coords[i - 1], r.coords[i])
            c.append(acc)
        }
        cum = c
        routeTotal = acc
        expected = r.duration

        var list: [NavStep] = []
        for st in r.steps {
            list.append(NavStep(text: st.text, icon: st.icon, start: st.start))
        }
        steps = list
        stepIndex = 0
        spokeIndex = -1
        spokeStage = 0
        progressIndex = 0
        offRoute = 0
        roadMode = true
        status = "ملاحة على الطرق (\(provider))"
        instruction = steps.first?.text ?? ""
        maneuver = steps.first?.icon ?? "arrow.up"
        nextInstruction = ""
        routeRevision += 1
        if let loc = lastLoc { update(loc) }
    }

    // MARK: - أيقونة المنعطف

    static func icon(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("u-turn") || t.contains("uturn") || t.contains("استدار") || t.contains("للخلف") {
            return "arrow.uturn.left"
        }
        if t.contains("roundabout") || t.contains("دوار") {
            return "arrow.triangle.2.circlepath"
        }
        if t.contains("arrive") || t.contains("destination") || t.contains("وجهتك") || t.contains("الوجهة") {
            return "flag.checkered"
        }
        if t.contains("left") || t.contains("يسار") {
            return "arrow.turn.up.left"
        }
        if t.contains("right") || t.contains("يمين") {
            return "arrow.turn.up.right"
        }
        return "arrow.up"
    }

    // MARK: - التحديث

    private func update(_ loc: CLLocation) {
        guard let t = target else { return }
        let here = loc.coordinate
        distance = Coords.distance(here, t)
        bearing = Coords.bearing(from: here, to: t)
        speed = max(0, loc.speed)

        if distance < 30 && !arrived {
            arrived = true
            instruction = "وصلت إلى الهدف"
            speak("وصلت إلى الهدف")
            Haptics.success()
        }

        if roadMode && routeCoords.count > 1 && cum.count == routeCoords.count {
            trackRoute(loc)
        } else {
            remaining = distance
            let v = loc.speed
            eta = v > 1 ? distance / v : 0
            if !roadMode {
                var needUpdate = true
                if let ld = lastDirect, Coords.distance(ld.coordinate, here) < 10 {
                    needUpdate = false
                }
                if needUpdate {
                    lastDirect = loc
                    routeCoords = [here, t]
                    routeRevision += 1
                }
            }
        }
    }

    private func trackRoute(_ loc: CLLocation) {
        let here = loc.coordinate
        let n = routeCoords.count

        // البحث عن أقرب نقطة على المسار ضمن نافذة حول التقدم الحالي
        var lo = max(0, min(progressIndex, n - 1) - 5)
        var hi = min(n, progressIndex + 250)
        var best = min(progressIndex, n - 1)
        var bd = Double.greatestFiniteMagnitude
        for pass in 0..<2 {
            if lo < hi {
                for i in lo..<hi {
                    let d = Coords.distance(here, routeCoords[i])
                    if d < bd {
                        bd = d
                        best = i
                    }
                }
            }
            if bd < 120 || pass == 1 { break }
            lo = 0
            hi = n
        }
        progressIndex = best

        remaining = max(0, routeTotal - cum[best]) + bd
        eta = routeTotal > 0 ? expected * remaining / routeTotal : 0

        if bd > 80 { offRoute += 1 } else { offRoute = 0 }
        if offRoute >= 3 && online && Date().timeIntervalSince(lastReroute) > 20 {
            lastReroute = Date()
            offRoute = 0
            speak("جاري إعادة حساب المسار")
            requestRoute(from: here)
            return
        }

        if stepIndex < steps.count && !arrived {
            let s = steps[stepIndex]
            let d = Coords.distance(here, s.start)
            stepDistance = d
            instruction = s.text
            maneuver = s.icon
            if stepIndex + 1 < steps.count {
                nextInstruction = steps[stepIndex + 1].text
                nextManeuver = steps[stepIndex + 1].icon
            } else {
                nextInstruction = ""
            }

            var stage = 0
            if d < 150 { stage = 2 } else if d < 700 { stage = 1 }
            if spokeIndex != stepIndex {
                spokeIndex = stepIndex
                spokeStage = 0
            }
            if stage > spokeStage {
                spokeStage = stage
                speak(lead(d, s.text) + s.text)
            }

            if d < 28 && stepIndex < steps.count - 1 {
                stepIndex += 1
            }
        }
    }

    // MARK: - الصوت

    private func isArabic(_ s: String) -> Bool {
        for sc in s.unicodeScalars {
            if sc.value >= 0x0600 && sc.value <= 0x06FF { return true }
        }
        return false
    }

    private func lead(_ d: Double, _ text: String) -> String {
        if d < 60 { return "" }
        let arabic = isArabic(text)
        if d >= 1000 {
            let km = String(format: "%.1f", d / 1000)
            return arabic ? "بعد \(km) كيلومتر، " : "In \(km) kilometers, "
        }
        let m = max(50, Int((d / 50).rounded()) * 50)
        return arabic ? "بعد \(m) متر، " : "In \(m) meters, "
    }

    private func speak(_ text: String) {
        if !voice || text.isEmpty { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: isArabic(text) ? "ar-SA" : "en-US")
        u.rate = 0.48
        synth.speak(u)
    }

    // MARK: - المندوب

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        if needsRoute {
            firstFix(loc)
        } else {
            hasFix = true
            lastLoc = loc
            update(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = h
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "تعذر تحديد الموقع. تأكد من تفعيل خدمات الموقع"
    }
}
