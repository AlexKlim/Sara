import CoreLocation

/// Where the home is, for the weather: the address and its coordinates.
struct HomeLocation: Codable, Equatable {
    var country = "", city = "", street = "", house = ""
    var latitude = 0.0, longitude = 0.0

    var address: String {
        [[street, house].filter { !$0.isEmpty }.joined(separator: " "), city, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func located() async throws -> HomeLocation {
        guard let coordinate = try await CLGeocoder().geocodeAddressString(address).first?.location?.coordinate else {
            throw SaraError("No such address")
        }
        var located = self
        located.latitude = coordinate.latitude
        located.longitude = coordinate.longitude
        return located
    }

    static func at(_ location: CLLocation) async -> HomeLocation {
        let place = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return HomeLocation(country: place?.country ?? "", city: place?.locality ?? "", street: place?.thoroughfare ?? "",
                            house: place?.subThoroughfare ?? "",
                            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

extension HomeLocation {
    var stored: String { (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "" }

    init?(stored: String) {
        guard let location = try? JSONDecoder().decode(HomeLocation.self, from: Data(stored.utf8)) else { return nil }
        self = location
    }
}
