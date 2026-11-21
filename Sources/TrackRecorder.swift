import Foundation
import CoreLocation
import MapKit

final class TrackRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var distance: Double = 0
    @Published var pointsCount = 0

    private let manager = CLLocationManager()
    private var coords: [CLLocationCoordinate2D] = []
    private var lastLocation: CLLocation?
    
    var onSave: ((String, [CLLocationCoordinate2D], Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // تسجيل كل 10 أمتار
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        coords = []
        distance = 0
        pointsCount = 0
        lastLocation = nil
        isRecording = true
        Haptics.success()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRecording = false
        if coords.count > 1 {
            let name = "تسجيل \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
            onSave?(name, coords, distance)
        }
        coords = []
        distance = 0
        pointsCount = 0
        lastLocation = nil
        Haptics.success()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording, let loc = locations.last, loc.horizontalAccuracy < 20 else { return }
        
        if let last = lastLocation {
            distance += loc.distance(from: last)
        }
        
        lastLocation = loc
        coords.append(loc.coordinate)
        
        DispatchQueue.main.async {
            self.distance = self.distance
            self.pointsCount = self.coords.count
        }
    }
}
