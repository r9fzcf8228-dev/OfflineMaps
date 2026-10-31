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
    @Published var instruction = ""
    @Published var stepDistance: Double = 0
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
    private var announced = -1
    private var cum: [Double] = []
    private var routeTotal = 0.0
    private var expected = 0.0
    private var needsRoute = false
    private var online = true
    private var offRoute = 0
    private var lastReroute = Date.distantPast
    private var lastLoc: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    // MARK: - التحكم

    func start(to c: CLLocationCoordinate2D, name: String, online: Bool) {
        self.online = online
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
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
        stepIndex = 0
        announced = -1
        offRoute = 0
        needsRoute = true
        hasFix = false
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
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: t))
        req.transportType = .automobile
        let d = MKDirections(request: req)
        directions = d
        d.calculate { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self, self.active else { return }
                if let r = resp?.routes.first {
                    self.applyRoute(r)
                } else if let loc = self.lastLoc {
                    self.directMode(from: loc)
                    self.status = "تعذر حساب الطريق، ملاحة مباشرة"
                }
            }
        }
    }

    private func coords(of pl: MKPolyline) -> [CLLocationCoordinate2D] {
        var cs = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pl.pointCount)
        if pl.pointCount > 0 {
            pl.getCoordinates(&cs, range: NSRange(location: 0, length: pl.pointCount))
        }
        return cs
    }

    private func applyRoute(_ r: MKRoute) {
        let cs = coords(of: r.polyline)
        if cs.count < 2 { return }
        routeCoords = cs
        var c: [Double] = [0]
        var acc = 0.0
        for i in 1..<cs.count {
            acc += Coords.distance(cs[i - 1], cs[i])
            c.append(acc)
        }
        cum = c
        routeTotal = acc
        expected = r.expectedTravelTime

        var list: [NavStep] = []
        for s in r.steps {
            if s.instructions.isEmpty { continue }
            let sc = coords(of: s.polyline)
            if let first = sc.first {
                list.append(NavStep(text: s.instructions, start: first))
            }
        }
        steps = list
        stepIndex = 0
        announced = -1
        offRoute = 0
        roadMode = true
        status = "ملاحة على الطرق"
        instruction = steps.first?.text ?? ""
        routeRevision += 1
        if let loc = lastLoc { update(loc) }
    }

    // MARK: - التحديث

    private func update(_ loc: CLLocation) {
        guard let t = target else { return }
        let here = loc.coordinate
        distance = Coords.distance(here, t)
        bearing = Coords.bearing(from: here, to: t)

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
                routeCoords = [here, t]
                routeRevision += 1
            }
        }
    }

    private func trackRoute(_ loc: CLLocation) {
        let here = loc.coordinate
        var best = 0
        var bd = Double.greatestFiniteMagnitude
        for i in 0..<routeCoords.count {
            let d = Coords.distance(here, routeCoords[i])
            if d < bd {
                bd = d
                best = i
            }
        }
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
            if d < 120 && announced < stepIndex {
                announced = stepIndex
                speak(s.text)
            }
            if d < 28 && stepIndex < steps.count - 1 {
                stepIndex += 1
            }
        }
    }

    private func speak(_ text: String) {
        if !voice || text.isEmpty { return }
        let u = AVSpeechUtterance(string: text)
        var arabic = false
        for sc in text.unicodeScalars {
            if sc.value >= 0x0600 && sc.value <= 0x06FF {
                arabic = true
                break
            }
        }
        u.voice = AVSpeechSynthesisVoice(language: arabic ? "ar-SA" : "en-US")
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
