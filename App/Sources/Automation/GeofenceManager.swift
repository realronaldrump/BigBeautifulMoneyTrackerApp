import CoreLocation
import Foundation

@MainActor
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func syncMonitoring(workplace: WorkplaceLocation, isEnabled: Bool) {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }

        guard isEnabled, let latitude = workplace.latitude, let longitude = workplace.longitude else {
            return
        }

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: min(max(workplace.radiusMeters, 50), 1_000),
            identifier: "workplace"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
    }
}
