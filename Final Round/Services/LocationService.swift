import Foundation
import CoreLocation
import MapKit
import Combine

/// Service for location auto-completion using Apple's native CLGeocoder and MKLocalSearchCompleter
@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    // MARK: - Location Info
    
    struct LocationInfo: Identifiable, Equatable {
        let id = UUID()
        let city: String
        let country: String
        let countryCode: String
        let currency: String
        let displayName: String
        
        var fullLocation: String {
            if city.isEmpty {
                return country
            }
            return "\(city), \(country)"
        }
        
        static func == (lhs: LocationInfo, rhs: LocationInfo) -> Bool {
            lhs.displayName == rhs.displayName
        }
    }
    
    // MARK: - Published Properties
    
    @Published var suggestions: [LocationInfo] = []
    @Published var isSearching = false
    @Published var searchError: String?
    
    // MARK: - Private Properties
    
    private let geocoder = CLGeocoder()
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var completionContinuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .address
    }
    
    // MARK: - Public Methods
    
    /// Search for locations based on user input
    func searchLocations(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }
        
        // Cancel any existing search
        searchTask?.cancel()
        
        isSearching = true
        searchError = nil
        
        searchTask = Task {
            do {
                // Use MKLocalSearchCompleter for suggestions
                let completions = await getSearchCompletions(for: trimmed)
                
                guard !Task.isCancelled else { return }
                
                // Convert completions to LocationInfo
                var results: [LocationInfo] = []
                
                // Process top 5 completions
                for completion in completions.prefix(5) {
                    if Task.isCancelled { break }
                    
                    if let locationInfo = await geocodeCompletion(completion) {
                        // Avoid duplicates
                        if !results.contains(where: { $0.displayName == locationInfo.displayName }) {
                            results.append(locationInfo)
                        }
                    }
                }
                
                guard !Task.isCancelled else { return }
                
                // If no results from completer, try direct geocoding
                if results.isEmpty {
                    if let directResult = await geocodeAddress(trimmed) {
                        results.append(directResult)
                    }
                }
                
                await MainActor.run {
                    self.suggestions = results
                    self.isSearching = false
                }
                
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchError = "Failed to search locations"
                    self.isSearching = false
                }
            }
        }
    }
    
    /// Infer location info from a text input using CLGeocoder
    func inferLocation(from input: String) async -> LocationInfo? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        return await geocodeAddress(trimmed)
    }
    
    /// Clear current suggestions
    func clearSuggestions() {
        searchTask?.cancel()
        suggestions = []
        isSearching = false
    }
    
    // MARK: - Private Methods
    
    /// Get search completions using MKLocalSearchCompleter
    private func getSearchCompletions(for query: String) async -> [MKLocalSearchCompletion] {
        return await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
            self.searchCompleter.queryFragment = query
            
            // Timeout after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let cont = self.completionContinuation {
                    self.completionContinuation = nil
                    cont.resume(returning: self.searchCompleter.results)
                }
            }
        }
    }
    
    /// Geocode a search completion to get full location info
    private func geocodeCompletion(_ completion: MKLocalSearchCompletion) async -> LocationInfo? {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first,
                  let placemark = mapItem.placemark as? CLPlacemark else {
                return nil
            }
            
            return createLocationInfo(from: placemark)
        } catch {
            return nil
        }
    }
    
    /// Geocode an address string directly
    private func geocodeAddress(_ address: String) async -> LocationInfo? {
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let placemark = placemarks.first else { return nil }
            return createLocationInfo(from: placemark)
        } catch {
            SecureLogger.debug("Geocoding failed for: \(address) - \(error.localizedDescription)", category: .database)
            return nil
        }
    }
    
    /// Create LocationInfo from a CLPlacemark
    private func createLocationInfo(from placemark: CLPlacemark) -> LocationInfo? {
        let city = placemark.locality ?? placemark.administrativeArea ?? ""
        let country = placemark.country ?? ""
        let countryCode = placemark.isoCountryCode ?? ""
        
        guard !country.isEmpty else { return nil }
        
        let currency = currencyForCountryCode(countryCode)
        let displayName = city.isEmpty ? country : "\(city), \(country)"
        
        return LocationInfo(
            city: city,
            country: country,
            countryCode: countryCode,
            currency: currency,
            displayName: displayName
        )
    }
    
    /// Get currency info for a country code using Locale
    private func currencyForCountryCode(_ countryCode: String) -> String {
        // Use Locale with the "en_XX" pattern to reliably get currency for any country
        let locale = Locale(identifier: "en_\(countryCode.uppercased())")
        
        if let currencyCode = locale.currency?.identifier {
            return currencyCode
        }
        
        // Fallback to USD if Locale fails (extremely rare)
        return "USD"
    }
    
    /// Get full currency details for a country (code, symbol, name)
    func getCurrencyDetails(for countryCode: String) -> (code: String?, symbol: String?, name: String?) {
        let locale = Locale(identifier: "en_\(countryCode.uppercased())")
        
        let currencyCode = locale.currency?.identifier
        let currencySymbol = locale.currencySymbol
        let currencyName = locale.localizedString(forCurrencyCode: currencyCode ?? "")
        
        return (currencyCode, currencySymbol, currencyName)
    }
    
    /// Get currency symbol for any currency code using Locale
    func getSymbol(for currencyCode: String) -> String {
        // Find a locale that uses this currency to get its symbol
        let locales = Locale.availableIdentifiers
        
        for identifier in locales {
            let locale = Locale(identifier: identifier)
            if locale.currency?.identifier == currencyCode {
                return locale.currencySymbol ?? currencyCode
            }
        }
        
        // Fallback: return the currency code itself as the symbol
        return currencyCode
    }
    
    /// Get currency name for any currency code
    func getName(for currencyCode: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forCurrencyCode: currencyCode) ?? currencyCode
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            if let continuation = self.completionContinuation {
                self.completionContinuation = nil
                continuation.resume(returning: completer.results)
            }
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            if let continuation = self.completionContinuation {
                self.completionContinuation = nil
                continuation.resume(returning: [])
            }
            self.searchError = error.localizedDescription
        }
    }
}
