import SwiftUI
import MapKit
import CoreLocation

final class LDKAnnotation: MKPointAnnotation {
    var colorName = ""
    var note = ""
}

final class DroppedAnnotation: MKPointAnnotation {}

struct OfflineMapView: UIViewRepresentable {
    let overlay: MKTileOverlay?
    let data: LDKData
    let showPoints: Bool
    let showAreas: Bool
    let showLines: Bool
    let showTracks: Bool
    let mapType: MKMapType
    let onCenter: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.delegate = context.coordinator
        context.coordinator.lm.requestWhenInUseAuthorization()

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.6
        map.addGestureRecognizer(press)

        let btn = MKUserTrackingButton(mapView: map)
        btn.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            btn.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -110)
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onCenter = onCenter
        map.mapType = mapType

        if c.lastOverlay !== overlay {
            let tiles = map.overlays.filter { $0 is MKTileOverlay }
            map.removeOverlays(tiles)
            if let o = overlay { map.insertOverlay(o, at: 0, level: .aboveLabels) }
            c.lastOverlay = overlay
        }

        let key = "\(data.id)|\(showPoints)|\(showAreas)|\(showLines)|\(showTracks)"
        if c.lastKey != key {
            let isNewData = c.lastDataID != data.id
            map.removeOverlays(c.shapeOverlays)
            let old = map.annotations.filter { $0 is LDKAnnotation }
            map.removeAnnotations(old)
            c.shapeOverlays = []
            c.styles = [:]

            var polygons: [MKOverlay] = []
            var lines: [MKOverlay] = []
            for s in data.shapes {
                var cs = s.coords
                let col = LDKStyle.color(s.color)
                if s.kind == .area {
                    if showAreas && cs.count >= 3 {
                        let p = MKPolygon(coordinates: &cs, count: cs.count)
                        p.title = s.name
                        c.styles[ObjectIdentifier(p)] = Coordinator.Style(color: col, dashed: false)
                        polygons.append(p)
                    }
                } else {
                    let wanted = (s.kind == .line) ? showLines : showTracks
                    if wanted && cs.count >= 2 {
                        let l = MKPolyline(coordinates: &cs, count: cs.count)
                        l.title = s.name
                        c.styles[ObjectIdentifier(l)] = Coordinator.Style(color: col, dashed: s.dashed)
                        lines.append(l)
                    }
                }
            }
            map.addOverlays(polygons, level: .aboveLabels)
            map.addOverlays(lines, level: .aboveLabels)
            c.shapeOverlays = polygons + lines

            if showPoints {
                var anns: [LDKAnnotation] = []
                for p in data.points {
                    let a = LDKAnnotation()
                    a.coordinate = p.coordinate
                    a.title = p.name
                    a.colorName = p.color
                    a.note = p.comment
                    anns.append(a)
                }
                map.addAnnotations(anns)
            }

            c.lastKey = key
            c.lastDataID = data.id
            if isNewData && !data.isEmpty { c.fit(map, data) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        struct Style {
            let color: UIColor
            let dashed: Bool
        }

        let lm = CLLocationManager()
        var onCenter: (CLLocationCoordinate2D) -> Void = { _ in }
        var lastOverlay: MKTileOverlay?
        var lastKey = ""
        var lastDataID: UUID?
        var shapeOverlays: [MKOverlay] = []
        var styles: [ObjectIdentifier: Style] = [:]
        var dropped: DroppedAnnotation?

        func fit(_ map: MKMapView, _ data: LDKData) {
            var all: [CLLocationCoordinate2D] = data.points.map { $0.coordinate }
            for s in data.shapes { all.append(contentsOf: s.coords) }
            guard !all.isEmpty else { return }
            let lats = all.map { $0.latitude }.sorted()
            let lons = all.map { $0.longitude }.sorted()
            let mlat = lats[lats.count / 2]
            let mlon = lons[lons.count / 2]
            let near = all.filter { abs($0.latitude - mlat) < 3 && abs($0.longitude - mlon) < 3 }
            guard !near.isEmpty else { return }
            var rect = MKMapRect.null
            for c in near {
                let mp = MKMapPoint(c)
                rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0.1, height: 0.1))
            }
            map.setVisibleMapRect(rect,
                                  edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 80, right: 40),
                                  animated: false)
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let pt = g.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)
            if let old = dropped { map.removeAnnotation(old) }
            let a = DroppedAnnotation()
            a.coordinate = coord
            a.title = "نقطة محددة"
            dropped = a
            map.addAnnotation(a)
            map.selectAnnotation(a, animated: true)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let c = mapView.centerCoordinate
            DispatchQueue.main.async { [weak self] in
                self?.onCenter(c)
            }
        }

        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if let t = o as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
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
                r.lineWidth = 3
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

        func copyButton() -> UIButton {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            b.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            return b
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let a = annotation as? LDKAnnotation {
                let id = "ldk"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: a, reuseIdentifier: id)
                v.annotation = a
                v.canShowCallout = true
                v.markerTintColor = LDKStyle.color(a.colorName)
                v.clusteringIdentifier = "ldk"
                var text = Coords.summary(a.coordinate)
                if !a.note.isEmpty { text = a.note + "\n" + text }
                v.detailCalloutAccessoryView = calloutLabel(text)
                v.rightCalloutAccessoryView = copyButton()
                return v
            }
            if let d = annotation as? DroppedAnnotation {
                let id = "dropped"
                let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: d, reuseIdentifier: id)
                v.annotation = d
                v.canShowCallout = true
                v.markerTintColor = .systemPurple
                v.displayPriority = .required
                v.detailCalloutAccessoryView = calloutLabel(Coords.summary(d.coordinate))
                v.rightCalloutAccessoryView = copyButton()
                return v
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let a = view.annotation else { return }
            UIPasteboard.general.string = Coords.summary(a.coordinate)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
