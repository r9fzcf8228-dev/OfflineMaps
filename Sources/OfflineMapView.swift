import SwiftUI
import MapKit

struct OfflineMapView: UIViewRepresentable {
    let overlay: MKTileOverlay

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.addOverlay(overlay, level: .aboveLabels)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ v: MKMapView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if let t = o as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            return MKOverlayRenderer(overlay: o)
        }
    }
}
