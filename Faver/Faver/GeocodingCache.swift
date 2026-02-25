import CoreLocation

/// Session-scoped geocoding cache — avoids redundant network calls for locations
/// already seen during this app launch. Keyed by lat/lon rounded to 2 decimal places
/// (~1 km resolution), so nearby photos share a single lookup result.
actor GeocodingCache {
    static let shared = GeocodingCache()
    private init() {}

    private var cache: [String: String] = [:]

    func lookup(_ location: CLLocation?) async -> String? {
        guard let location else { return nil }
        let key = cacheKey(for: location)
        if let cached = cache[key] { return cached }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks?.first else { return nil }
        let name = p.locality ?? p.subLocality ?? p.administrativeArea
        if let name { cache[key] = name }
        return name
    }

    private func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}
