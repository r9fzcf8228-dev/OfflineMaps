import SwiftUI
import MapKit

final class LDKAnnotation: MKPointAnnotation {
    var colorName = ""
}

struct OfflineMapView: UIViewRepresentable {
    let overlay: MKTileOverlay?
    let points: [LDKPoint]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator

        if c.lastOverlay !== overlay {
            map.removeOverlays(map.overlays)
            if let o = overlay { map.addOverlay(o, level: .aboveLabels) }
            c.lastOverlay = overlay
        }

        let ids = points.map { $0.id }
        if c.lastIDs != ids {
            let old = map.annotations.filter { $0 is LDKAnnotation }
            map.removeAnnotations(old)
            let anns: [LDKAnnotation] = points.map { p in
                let a = LDKAnnotation()
                a.coordinate = p.coordinate
                a.title = p.name
                a.colorName = p.color
                return a
            }
            map.addAnnotations(anns)
            if !anns.isEmpty { map.showAnnotations(anns, animated: true) }
            c.lastIDs = ids
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastOverlay: MKTileOverlay?
        var lastIDs: [UUID] = []

        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if let t = o as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            return MKOverlayRenderer(overlay: o)
        }

        func mapView(_ m: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? LDKAnnotation else { return nil }
            let id = "ldk"
            let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: a, reuseIdentifier: id)
            v.annotation = a
            v.canShowCallout = true
            v.markerTintColor = Coordinator.color(a.colorName)
            v.clusteringIdentifier = "ldk"
            return v
        }

        static func color(_ name: String) -> UIColor {
            switch name.lowercased() {
            case "red": return .systemRed
            case "blue", "lightblue": return .systemBlue
            case "green", "lightgreen": return .systemGreen
            case "yellow": return .systemYellow
            case "orange": return .systemOrange
            case "purple": return .systemPurple
            case "magenta": return .magenta
            case "cyan": return .cyan
            case "black": return .black
            case "gray": return .gray
            default: return .systemRed
            }
        }
    }
}
