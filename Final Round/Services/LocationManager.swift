import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: String?
    @Published var currentCurrency: String?
    @Published var isLoading = false
    @Published var error: String?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    static let shared = LocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func fetchCurrentLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            error = "Location permission not granted"
            return
        }
        
        isLoading = true
        error = nil
        locationManager.requestLocation()
    }
    
    func inferCurrencyFromLocation(_ location: String) -> String {
        let locationLower = location.lowercased()
        
        // Common countries and their currencies
        let currencyMap: [String: String] = [
            // North America
            "united states": "USD",
            "usa": "USD",
            "us": "USD",
            "america": "USD",
            "canada": "CAD",
            "mexico": "MXN",
            
            // Europe
            "united kingdom": "GBP",
            "uk": "GBP",
            "britain": "GBP",
            "england": "GBP",
            "scotland": "GBP",
            "wales": "GBP",
            "ireland": "EUR",
            "germany": "EUR",
            "france": "EUR",
            "spain": "EUR",
            "italy": "EUR",
            "netherlands": "EUR",
            "belgium": "EUR",
            "austria": "EUR",
            "portugal": "EUR",
            "greece": "EUR",
            "switzerland": "CHF",
            "sweden": "SEK",
            "norway": "NOK",
            "denmark": "DKK",
            "poland": "PLN",
            "czech": "CZK",
            "hungary": "HUF",
            "romania": "RON",
            
            // Asia Pacific
            "india": "INR",
            "china": "CNY",
            "japan": "JPY",
            "south korea": "KRW",
            "korea": "KRW",
            "singapore": "SGD",
            "hong kong": "HKD",
            "taiwan": "TWD",
            "thailand": "THB",
            "malaysia": "MYR",
            "indonesia": "IDR",
            "philippines": "PHP",
            "vietnam": "VND",
            "pakistan": "PKR",
            "bangladesh": "BDT",
            "australia": "AUD",
            "new zealand": "NZD",
            
            // Middle East
            "uae": "AED",
            "dubai": "AED",
            "saudi arabia": "SAR",
            "israel": "ILS",
            "turkey": "TRY",
            "qatar": "QAR",
            "kuwait": "KWD",
            
            // Africa
            "south africa": "ZAR",
            "nigeria": "NGN",
            "kenya": "KES",
            "egypt": "EGP",
            
            // South America
            "brazil": "BRL",
            "argentina": "ARS",
            "chile": "CLP",
            "colombia": "COP",
            "peru": "PEN"
        ]
        
        // Check for exact matches or partial matches
        for (country, currency) in currencyMap {
            if locationLower.contains(country) {
                return currency
            }
        }
        
        // Default to USD if no match found
        return "USD"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            await reverseGeocode(location: location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
    
    private func reverseGeocode(location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                // Build location string: City, Country
                var locationComponents: [String] = []
                
                if let city = placemark.locality {
                    locationComponents.append(city)
                }
                
                if let country = placemark.country {
                    locationComponents.append(country)
                }
                
                let locationString = locationComponents.joined(separator: ", ")
                
                await MainActor.run {
                    self.currentLocation = locationString
                    self.currentCurrency = inferCurrencyFromLocation(locationString)
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to determine location"
                self.isLoading = false
            }
        }
    }
}

