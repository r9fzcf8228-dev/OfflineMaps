import SwiftUI
import MapKit
import CoreLocation

class NavigationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var trackCoordinates: [CLLocationCoordinate2D] = []
    @Published var totalDistance: Double = 0.0 // بالأمتار
    @Published var isRecording = false
    
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            trackCoordinates.removeAll()
            totalDistance = 0.0
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
        
        if isRecording {
            if let last = lastLocation {
                totalDistance += location.distance(from: last)
            }
            trackCoordinates.append(location.coordinate)
            lastLocation = location
        }
    }
}

struct Navigator: View {
    @StateObject private var navManager = NavigationManager()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                
                if navManager.isRecording && navManager.trackCoordinates.count > 1 {
                    MapPolyline(coordinates: navManager.trackCoordinates)
                        .stroke(Theme.primary, lineWidth: 5)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea()
            
            // شريط التحكم السفلي
            NavHUD(
                isRecording: navManager.isRecording,
                distance: navManager.totalDistance,
                toggleAction: { navManager.toggleRecording() }
            )
        }
        .navigationTitle("تتبع المسار")
        .navigationBarTitleDisplayMode(.inline)
    }
}
