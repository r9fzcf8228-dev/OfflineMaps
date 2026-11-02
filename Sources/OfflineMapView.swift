import SwiftUI
import MapKit
import CoreLocation

struct PathInfo {
    var count: Int = 0
    var total: Double = 0
    var lastLeg: Double = 0
    var bearing: Double = 0
    var seconds: Double = 0
    var busy: Bool = false
}

final class MapController: ObservableObject {
    weak var coordinator: OfflineMapView.Coordinator?
    var needsFit = true

    func undoPath() { coordinator?.undoPath() }
    func clearPath() { coordinator?.clearPath() }
    func pathCoords() -> [CLLocationCoordinate2D] { return coordinator?.pathCoords ?? [] }
    func goTo(_ c: CLLocationCoordinate2D) { coordinator?.goTo(c) }
    func recenterNow() { coordinator?.recenter() }

    func userLocation() -> CLLocation? {
        return coordinator?.map?.userLocation.location
    }

    func visibleBounds() -> GeoBounds? {
        guard let m = coordinator?.map else { return nil }
        let r = m.region
        if r.span.latitudeDelta <= 0 || r.span.longitudeDelta <= 0 { return nil }
        return GeoBounds(minLat: r.center.latitude - r.span.latitudeDelta / 2,
                         maxLat: r.center.latitude + r.span.latitudeDelta / 2,
                         minLon: r.center.longitude - r.span.longitudeDelta / 2,
                         maxLon: r.center.longitude + r.span.longitudeDelta / 2)
    }
}

final class PointAnnotation: MKPointAnnotation {
    var pid = UUID()
    var colorName = ""
    var symbol = ""
    var note = ""
    var pinned = false
}

final class PathVertex: MKPointAnnotation {}

final class TargetAnnotation: MKPointAnnotation {}

final class NavTargetAnnotation: MKPointAnnotation {}

struct OfflineMapView: UIViewRepresentable {
    let overlay: MKTileOverlay?
    let points: [MapPoint]
    let shapes: [MapShape]
    let revision: Int
    let showPoints: Bool
    let showAreas: Bool
    let showLines: Bool
    let showTracks: Bool
    let clusterPoints: Bool
    let mapType: MKMapType
    let editMode: Bool
    let pathMode: Bool
    let followRoads: Bool
    let navRoute: [CLLocationCoordinate2D]
    let navRevision: Int
    let navProgress: Int
    let navTarget: CLLocationCoordinate2D?
    let navRoad: Bool
    let navActive: Bool
    let navFollow: Bool
    let navNear: Bool
    let controller: MapController
    let onCenter: (CLLocationCoordinate2D) -> Void
    let onEditPoint: (UUID) -> Void
    let onMovePoint: (UUID, CLLocationCoordinate2D) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void
    let onPath: (PathInfo) -> Void
    let onPathMessage: (String) -> Void
    let onFollowChange: (Bool) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.delegate = context.coordinator
        context.coordinator.map = map
        context.coordinator.lm.requestWhenInUseAuthorization()
        context.coordinator.startHeading()

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.7
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        map.addGestureRecognizer(press)

        let dbl = UITapGestureRecognizer(target: nil, action: nil)
        dbl.numberOfTapsRequired = 2
        dbl.delegate = context.coordinator
        map.addGestureRecognizer(dbl)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tap.require(toFail: dbl)
        map.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.userGesture(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.userGesture(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)

        let btn = MKUserTrackingButton(mapView: map)
        btn.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            btn.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -170)
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.map = map
        c.onCenter = onCenter
        c.onEditPoint = onEditPoint
        c.onMovePoint = onMovePoint
        c.onLongPress = onLongPress
        c.onPath = onPath
        c.onPathMessage = onPathMessage
        c.onFollowChange = onFollowChange
        c.pathMode = pathMode
        c.followRoads = followRoads
        c.editMode = editMode
        c.clusterPoints = clusterPoints
        c.navActive = navActive
        c.following = navFollow
        c.near = navNear
        controller.coordinator = c
        map.mapType = mapType

        if c.lastOverlay !== overlay {
            let tiles = map.overlays.filter { $0 is MKTileOverlay }
            map.removeOverlays(tiles)
            if let o = overlay { map.insertOverlay(o, at: 0, level: .aboveLabels) }
            c.lastOverlay = overlay
        }

        let key = "\(revision)|\(showPoints)|\(showAreas)|\(showLines)|\(showTracks)|\(editMode)|\(clusterPoints)"
        if c.lastKey != key {
            map.removeOverlays(c.shapeOverlays)
            let old = map.annotations.filter { $0 is PointAnnotation }
            map.removeAnnotations(old)
            c.shapeOverlays = []
            c.styles = [:]

            var polygons: [MKOverlay] = []
            var lines: [MKOverlay] = []
            for s in shapes {
                var cs = s.coords
                let fb: UIColor = (s.kind == "route") ? UIColor.systemBlue : UIColor.systemRed
                let col = LDKStyle.color(s.color, fallback: fb)
                if s.kind == "area" {
                    if showAreas && cs.count >= 3 {
                        let poly = MKPolygon(coordinates: &cs, count: cs.count)
                        poly.title = s.name
                        c.styles[ObjectIdentifier(poly)] = Coordinator.Style(color: col, dashed: false, width: 2)
                        polygons.append(poly)
                    }
                } else {
                    var wanted = showTracks
                    if s.kind == "line" { wanted = showLines }
                    if wanted && cs.count >= 2 {
                        let line = MKPolyline(coordinates: &cs, count: cs.count)
                        line.title = s.name
                        let w: CGFloat = (s.kind == "route") ? 4 : 3
                        c.styles[ObjectIdentifier(line)] = Coordinator.Style(color: col, dashed: s.dashed, width: w)
                        lines.append(line)
                    }
                }
            }
            map.addOverlays(polygons, level: .aboveLabels)
            map.addOverlays(lines, level: .aboveLabels)
            c.shapeOverlays = polygons + lines

            if showPoints {
                var anns: [PointAnnotation] = []
                for p in points {
                    let a = PointAnnotation()
                    a.pid = p.id
                    a.coordinate = p.coordinate
                    a.title = p.name
                    a.colorName = p.color
                    a.symbol = p.symbol
                    a.note = p.note
                    a.pinned = p.pinned
                    anns.append(a)
                }
                map.addAnnotations(anns)
            }
            c.lastKey = key
        }

        // الملاحة: علامة الهدف
        var tkey = ""
        if navActive, let t = navTarget {
            tkey = "\(t.latitude),\(t.longitude)"
        }
        if c.navTargetKey != tkey {
            if let p = c.navPin {
                map.removeAnnotation(p)
                c.navPin = nil
            }
            if navActive, let t = navTarget {
                let pin = NavTargetAnnotation()
                pin.coordinate = t
                pin.title = "الهدف"
                c.navPin = pin
                map.addAnnotation(pin)
            }
            c.navTargetKey = tkey
        }

        // الملاحة: بدء/إنهاء كاميرا التتبع
        if c.lastNavActive != navActive {
            c.lastNavActive = navActive
            if navActive {
                c.beginFollow(map)
            } else {
                c.endFollow(map)
            }
        }

        // الملاحة: خط الطريق (الجزء المتبقي فقط)
        if c.lastNavRevision != navRevision || c.lastNavProgress != navProgress {
            if let l = c.navLine {
                map.removeOverlay(l)
                c.navLine = nil
            }
            if let l = c.navCasing {
                map.removeOverlay(l)
                c.navCasing = nil
            }
            if navActive {
                var cs = navRoute
                if navRoad && navProgress > 0 && navProgress < cs.count - 1 {
                    cs = Array(cs[navProgress...])
                }
                if cs.count >= 2 {
                    var cs2 = cs
                    c.navRoad = navRoad
                    if navRoad {
                        let casing = MKPolyline(coordinates: &cs2, count: cs2.count)
                        c.navCasing = casing
                        map.addOverlay(casing, level: .aboveLabels)
                    }
                    let l = MKPolyline(coordinates: &cs, count: cs.count)
                    c.navLine = l
                    map.addOverlay(l, level: .aboveLabels)
                }
            }
            c.lastNavRevision = navRevision
            c.lastNavProgress = navProgress
        }

        if controller.needsFit && (!points.isEmpty || !shapes.isEmpty) {
            c.fit(map, points, shapes)
            controller.needsFit = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate, CLLocationManagerDelegate {
        struct Style {
            let color: UIColor
            let dashed: Bool
            let width: CGFloat
        }

        weak var map: MKMapView?
        let lm = CLLocationManager()
        var onCenter: (CLLocationCoordinate2D) -> Void = { _ in }
        var onEditPoint: (UUID) -> Void = { _ in }
        var onMovePoint: (UUID, CLLocationCoordinate2D) -> Void = { _, _ in }
        var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
        var onPath: (PathInfo) -> Void = { _ in }
        var onPathMessage: (String) -> Void = { _ in }
        var onFollowChange: (Bool) -> Void = { _ in }

        var lastOverlay: MKTileOverlay?
        var lastKey = ""
        var shapeOverlays: [MKOverlay] = []
        var styles: [ObjectIdentifier: Style] = [:]
        var pathMode = false
        var followRoads = false
        var editMode = false
        var clusterPoints = true

        var taps: [CLLocationCoordinate2D] = []
        var legs: [[CLLocationCoordinate2D]] = []
        var legTimes: [Double] = []
        var pathLine: MKPolyline?
        var pathMarkers: [PathVertex] = []
        var busy = false
        var directions: MKDirections?
        var target: TargetAnnotation?

        var navLine: MKPolyline?
        var navCasing: MKPolyline?
        var navPin: NavTargetAnnotation?
        var navRoad = false
        var navTargetKey = ""
        var navActive = false
        var following = true
        var near = false
        var lastNavActive = false
        var lastNavRevision = -1
        var lastNavProgress = -1

        var deviceHeading: Double = 0
        var camHeading: Double = 0
        var lastLocation: CLLocation?

        override init() {
            super.init()
            lm.delegate = self
        }

        var pathCoords: [CLLocationCoordinate2D] {
            var all: [CLLocationCoordinate2D] = []
            for l in legs { all.append(contentsOf: l) }
            return all
        }

        // MARK: البوصلة والسهم

        func startHeading() {
            if CLLocationManager.headingAvailable() {
                lm.headingFilter = 2
                lm.startUpdatingHeading()
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            deviceHeading = h
            updateArrow()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            startHeading()
        }

        func arrowAngle(_ map: MKMapView) -> Double {
            var h = deviceHeading
            if let loc = lastLocation, loc.speed > 1.5, loc.course >= 0 {
                h = loc.course
            }
            return (h - map.camera.heading) * Double.pi / 180
        }

        func updateArrow() {
            guard let map = map, let v = map.view(for: map.userLocation) else { return }
            v.transform = CGAffineTransform(rotationAngle: CGFloat(arrowAngle(map)))
        }

        // MARK: كاميرا التتبع (على طريقة Waze)

        static func offset(_ c: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
            let r = 6371000.0
            let br = bearing * Double.pi / 180
            let lat1 = c.latitude * Double.pi / 180
            let lon1 = c.longitude * Double.pi / 180
            let dr = meters / r
            let lat2 = asin(sin(lat1) * cos(dr) + cos(lat1) * sin(dr) * cos(br))
            let lon2 = lon1 + atan2(sin(br) * sin(dr) * cos(lat1), cos(dr) - sin(lat1) * sin(lat2))
            return CLLocationCoordinate2D(latitude: lat2 * 180 / Double.pi,
                                          longitude: lon2 * 180 / Double.pi)
        }

        func followCamera(_ map: MKMapView, _ loc: CLLocation) {
            let speed = max(0, loc.speed)
            var dist = 380 + speed * 22
            if dist > 1500 { dist = 1500 }
            if near && dist > 300 { dist = 300 }

            var targetHeading = loc.course
            if speed < 1.5 || loc.course < 0 {
                targetHeading = deviceHeading
            }
            let delta = ((targetHeading - camHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
            camHeading = (camHeading + delta * 0.5 + 360).truncatingRemainder(dividingBy: 360)

            let ahead = Coordinator.offset(loc.coordinate, meters: dist * 0.3, bearing: camHeading)
            let cam = MKMapCamera(lookingAtCenter: ahead, fromDistance: dist, pitch: 55, heading: camHeading)
            map.setCamera(cam, animated: true)
        }

        func beginFollow(_ map: MKMapView) {
            map.setUserTrackingMode(.none, animated: false)
            camHeading = map.camera.heading
            if let loc = map.userLocation.location {
                followCamera(map, loc)
            }
        }

        func endFollow(_ map: MKMapView) {
            let cam = MKMapCamera(lookingAtCenter: map.centerCoordinate,
                                  fromDistance: map.camera.centerCoordinateDistance,
                                  pitch: 0, heading: 0)
            map.setCamera(cam, animated: true)
        }

        func recenter() {
            guard let map = map, let loc = map.userLocation.location else { return }
            following = true
            followCamera(map, loc)
        }

        @objc func userGesture(_ g: UIGestureRecognizer) {
            if g.state == .began && navActive && following {
                following = false
                onFollowChange(false)
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let loc = userLocation.location else { return }
            lastLocation = loc
            updateArrow()
            if navActive && following {
                followCamera(mapView, loc)
            }
        }

        // MARK: ضبط الإطار

        func fit(_ map: MKMapView, _ points: [MapPoint], _ shapes: [MapShape]) {
            var all: [CLLocationCoordinate2D] = points.map { $0.coordinate }
            for s in shapes { all.append(contentsOf: s.coords) }
            if all.isEmpty { return }
            let lats = all.map { $0.latitude }.sorted()
            let lons = all.map { $0.longitude }.sorted()
            let mlat = lats[lats.count / 2]
            let mlon = lons[lons.count / 2]
            let near = all.filter { abs($0.latitude - mlat) < 3 && abs($0.longitude - mlon) < 3 }
            if near.isEmpty { return }
            var rect = MKMapRect.null
            for c in near {
                let mp = MKMapPoint(c)
                rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0.1, height: 0.1))
            }
            map.setVisibleMapRect(rect,
                                  edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 200, right: 40),
                                  animated: false)
        }

        func goTo(_ c: CLLocationCoordinate2D) {
            guard let map = map else { return }
            if let t = target { map.removeAnnotation(t) }
            let t = TargetAnnotation()
            t.coordinate = c
            t.title = "العلامة"
            target = t
            map.addAnnotation(t)
            map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000),
                          animated: true)
            map.selectAnnotation(t, animated: true)
        }

        // MARK: الإيماءات

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }

        func nearestAnnotation(_ map: MKMapView, _ pt: CGPoint, within: CGFloat) -> MKAnnotation? {
            var best: MKAnnotation?
            var bd = within
            for a in map.annotations {
                if a is MKUserLocation { continue }
                if a is MKClusterAnnotation { continue }
                let p = map.convert(a.coordinate, toPointTo: map)
                let d = hypot(p.x - pt.x, p.y - pt.y)
                if d < bd {
                    bd = d
                    best = a
                }
            }
            return best
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            if pathMode || editMode || navActive { return }
            let pt = g.location(in: map)
            if nearestAnnotation(map, pt, within: 32) != nil { return }
            let coord = map.convert(pt, toCoordinateFrom: map)
            onLongPress(coord)
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard pathMode, !busy, g.state == .ended, let map = map else { return }
            let pt = g.location(in: map)
            var c = map.convert(pt, toCoordinateFrom: map)
            if let a = nearestAnnotation(map, pt, within: 28), !(a is PathVertex) {
                c = a.coordinate
            }
            addTap(c)
        }

        // MARK: المسار والقياس

        func addTap(_ c: CLLocationCoordinate2D) {
            guard let last = taps.last else {
                taps.append(c)
                refreshPath()
                return
            }
            if followRoads {
                busy = true
                publish()
                let req = MKDirections.Request()
                req.source = MKMapItem(placemark: MKPlacemark(coordinate: last))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: c))
                req.transportType = .automobile
                let d = MKDirections(request: req)
                directions = d
                d.calculate { [weak self] resp, err in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.busy = false
                        if let r = resp?.routes.first {
                            let pl = r.polyline
                            var cs = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(),
                                                              count: pl.pointCount)
                            pl.getCoordinates(&cs, range: NSRange(location: 0, length: pl.pointCount))
                            self.taps.append(c)
                            self.legs.append(cs)
                            self.legTimes.append(r.expectedTravelTime)
                        } else {
                            self.taps.append(c)
                            self.legs.append([last, c])
                            self.legTimes.append(0)
                            self.onPathMessage("تعذر حساب الطريق (يلزم اتصال بالإنترنت). رُسم خط مستقيم.")
                        }
                        self.refreshPath()
                    }
                }
            } else {
                taps.append(c)
                legs.append([last, c])
                legTimes.append(0)
                refreshPath()
            }
        }

        func undoPath() {
            if taps.isEmpty { return }
            taps.removeLast()
            if !legs.isEmpty {
                legs.removeLast()
                legTimes.removeLast()
            }
            refreshPath()
        }

        func clearPath() {
            taps = []
            legs = []
            legTimes = []
            refreshPath()
        }

        func refreshPath() {
            guard let map = map else { return }
            if let l = pathLine { map.removeOverlay(l) }
            map.removeAnnotations(pathMarkers)
            pathMarkers = []
            pathLine = nil

            var all = pathCoords
            if all.count >= 2 {
                let l = MKPolyline(coordinates: &all, count: all.count)
                pathLine = l
                map.addOverlay(l, level: .aboveLabels)
            }
            for (i, c) in taps.enumerated() {
                let v = PathVertex()
                v.coordinate = c
                v.title = "\(i + 1)"
                pathMarkers.append(v)
            }
            map.addAnnotations(pathMarkers)
            publish()
        }

        func publish() {
            var total = 0.0
            for l in legs { total += Coords.length(l) }
            var last = 0.0
            var brg = 0.0
            if taps.count >= 2 {
                let a = taps[taps.count - 2]
                let b = taps[taps.count - 1]
                brg = Coords.bearing(from: a, to: b)
                if let ll = legs.last {
                    last = Coords.length(ll)
                } else {
                    last = Coords.distance(a, b)
                }
            }
            var secs = 0.0
            for t in legTimes { secs += t }
            onPath(PathInfo(count: taps.count, total: total, lastLeg: last,
                            bearing: brg, seconds: secs, busy: busy))
        }

        // MARK: المندوب

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let c = mapView.centerCoordinate
            updateArrow()
            DispatchQueue.main.async { [weak self] in
                self?.onCenter(c)
            }
        }

        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if let t = o as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }

            if let l = o as? MKPolyline, l === navCasing {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = UIColor(red: 0.04, green: 0.18, blue: 0.45, alpha: 1)
                r.lineWidth = 11
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }

            if let l = o as? MKPolyline, l === navLine {
                let r = MKPolylineRenderer(polyline: l)
                r.lineCap = .round
                r.lineJoin = .round
                if navRoad {
                    r.strokeColor = UIColor(red: 0.30, green: 0.68, blue: 1.0, alpha: 1)
                    r.lineWidth = 7
                } else {
                    r.strokeColor = UIColor.systemCyan
                    r.lineWidth = 5
                    r.lineDashPattern = [10, 8]
                }
                return r
            }

            if let l = o as? MKPolyline, l === pathLine {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = UIColor.systemOrange
                r.lineWidth = 5
                return r
            }

            let st = styles[ObjectIdentifier(o)]
            if let p = o as? MKPolygon {
                let r = MKPolygonRenderer(polygon: p)
                let col = st?.color ?? UIColor.systemRed
                r.fillColor = col.withAlphaComponent(0.3)
                r.strokeColor = col
                r.lineWidth = 2
                return r
            }
            if let l = o as? MKPolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = st?.color ?? UIColor.systemBlue
                r.lineWidth = st?.width ?? 3
                if st?.dashed == true { r.lineDashPattern = [8, 6] }
                return r
            }
            return MKOverlayRenderer(overlay: o)
        }

        func calloutLabel(_ text: String) -> UILabel {
            let l = UILabel()
            l.numberOfLines = 0
            l.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            l.text = text
            return l
        }

        func iconButton(_ name: String) -> UIButton {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: name), for: .normal)
            b.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            return b
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // سهم موقعي بدل النقطة الدائرية
            if annotation is MKUserLocation {
                let id = "me"
                let v = m.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.image = UserArrow.image()
                v.centerOffset = CGPoint.zero
                v.canShowCallout = false
                v.zPriority = .max
                v.transform = CGAffineTransform(rotationAngle: CGFloat(arrowAngle(m)))
                return v
            }

            if let a = annotation as? PointAnnotation {
                var text = Coords.summary(a.coordinate)
                if !a.note.isEmpty { text = a.note + "\n" + text }
                let canCluster = clusterPoints && !editMode && !a.pinned
                let cluster: String? = canCluster ? "pts" : nil
                let prio: MKFeatureDisplayPriority = a.pinned ? .required : .defaultHigh

                if let img = MilSymbol.image(for: a.symbol) {
                    let id = "sym"
                    let v = m.dequeueReusableAnnotationView(withIdentifier: id)
                        ?? MKAnnotationView(annotation: a, reuseIdentifier: id)
                    v.annotation = a
                    v.image = img
                    v.centerOffset = CGPoint.zero
                    v.canShowCallout = true
                    v.isDraggable = editMode
                    v.clusteringIdentifier = cluster
                    v.displayPriority = prio
                    v.detailCalloutAccessoryView = calloutLabel(text)
                    v.rightCalloutAccessoryView = iconButton("pencil")
                    v.leftCalloutAccessoryView = iconButton("doc.on.doc")
                    return v
                }

                let id = "pin"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: a, reuseIdentifier: id)
                v.annotation = a
                v.canShowCallout = true
                v.markerTintColor = LDKStyle.color(a.colorName)
                v.isDraggable = editMode
                v.clusteringIdentifier = cluster
                v.displayPriority = prio
                v.detailCalloutAccessoryView = calloutLabel(text)
                v.rightCalloutAccessoryView = iconButton("pencil")
                v.leftCalloutAccessoryView = iconButton("doc.on.doc")
                return v
            }

            if let t = annotation as? TargetAnnotation {
                let id = "target"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: t, reuseIdentifier: id)
                v.annotation = t
                v.canShowCallout = true
                v.markerTintColor = UIColor.systemPurple
                v.displayPriority = .required
                v.detailCalloutAccessoryView = calloutLabel(Coords.summary(t.coordinate))
                v.rightCalloutAccessoryView = iconButton("doc.on.doc")
                return v
            }

            if let nt = annotation as? NavTargetAnnotation {
                let id = "navtarget"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: nt, reuseIdentifier: id)
                v.annotation = nt
                v.canShowCallout = true
                v.markerTintColor = UIColor.systemGreen
                v.glyphImage = UIImage(systemName: "flag.fill")
                v.displayPriority = .required
                v.clusteringIdentifier = nil
                v.detailCalloutAccessoryView = calloutLabel(Coords.summary(nt.coordinate))
                return v
            }

            if let pv = annotation as? PathVertex {
                let id = "vertex"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: pv, reuseIdentifier: id)
                v.annotation = pv
                v.canShowCallout = false
                v.markerTintColor = UIColor.systemOrange
                v.glyphText = pv.title
                v.displayPriority = .required
                v.clusteringIdentifier = nil
                return v
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let ann = view.annotation else { return }
            if let a = ann as? PointAnnotation, control === view.rightCalloutAccessoryView {
                onEditPoint(a.pid)
                return
            }
            UIPasteboard.general.string = Coords.summary(ann.coordinate)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            if newState == .ending {
                view.dragState = .none
                if let a = view.annotation as? PointAnnotation {
                    onMovePoint(a.pid, a.coordinate)
                }
            }
        }
    }
}
