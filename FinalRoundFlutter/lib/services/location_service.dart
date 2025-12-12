import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

/// Service for location auto-completion and currency inference
/// Matches iOS LocationService.swift
class LocationService extends ChangeNotifier {
  static final LocationService instance = LocationService._();
  LocationService._();

  // MARK: - State
  List<LocationInfo> _suggestions = [];
  bool _isSearching = false;
  String? _searchError;

  List<LocationInfo> get suggestions => _suggestions;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  // MARK: - Search

  /// Search for locations based on user input
  Future<void> searchLocations(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      _suggestions = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final locations = await locationFromAddress(trimmed);
      final results = <LocationInfo>[];

      for (final location in locations.take(5)) {
        try {
          final placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            final info = _createLocationInfo(placemark);
            if (info != null && !results.any((r) => r.displayName == info.displayName)) {
              results.add(info);
            }
          }
        } catch (e) {
          debugPrint('Error reverse geocoding: $e');
        }
      }

      _suggestions = results;
      _isSearching = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Location search failed: $e');
      _searchError = 'Failed to search locations';
      _suggestions = [];
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Infer location info from a text input
  Future<LocationInfo?> inferLocation(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    try {
      final locations = await locationFromAddress(trimmed);
      if (locations.isEmpty) return null;

      final placemarks = await placemarkFromCoordinates(
        locations.first.latitude,
        locations.first.longitude,
      );

      if (placemarks.isEmpty) return null;
      return _createLocationInfo(placemarks.first);
    } catch (e) {
      debugPrint('Geocoding failed for: $trimmed - $e');
      return null;
    }
  }

  /// Clear current suggestions
  void clearSuggestions() {
    _suggestions = [];
    _isSearching = false;
    notifyListeners();
  }

  // MARK: - Private Methods

  LocationInfo? _createLocationInfo(Placemark placemark) {
    final city = placemark.locality ?? placemark.administrativeArea ?? '';
    final country = placemark.country ?? '';
    final countryCode = placemark.isoCountryCode ?? '';

    if (country.isEmpty) return null;

    final currency = currencyForCountryCode(countryCode);
    final displayName = city.isEmpty ? country : '$city, $country';

    return LocationInfo(
      city: city,
      country: country,
      countryCode: countryCode,
      currency: currency,
      displayName: displayName,
    );
  }

  // MARK: - Currency Mapping

  /// Get currency code for a country code
  static String currencyForCountryCode(String countryCode) {
    return _countryCurrencyMap[countryCode.toUpperCase()] ?? 'USD';
  }

  /// Get currency symbol for a currency code
  static String getSymbol(String currencyCode) {
    return _currencySymbolMap[currencyCode] ?? currencyCode;
  }

  /// Get currency name for a currency code
  static String getName(String currencyCode) {
    return _currencyNameMap[currencyCode] ?? currencyCode;
  }

  // Comprehensive country to currency mapping
  static const Map<String, String> _countryCurrencyMap = {
    // North America
    'US': 'USD', 'CA': 'CAD', 'MX': 'MXN',
    // Europe
    'GB': 'GBP', 'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR',
    'NL': 'EUR', 'BE': 'EUR', 'AT': 'EUR', 'PT': 'EUR', 'IE': 'EUR',
    'FI': 'EUR', 'GR': 'EUR', 'LU': 'EUR', 'SK': 'EUR', 'SI': 'EUR',
    'EE': 'EUR', 'LV': 'EUR', 'LT': 'EUR', 'CY': 'EUR', 'MT': 'EUR',
    'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK', 'PL': 'PLN',
    'CZ': 'CZK', 'HU': 'HUF', 'RO': 'RON', 'BG': 'BGN', 'HR': 'EUR',
    'IS': 'ISK', 'RU': 'RUB', 'UA': 'UAH', 'TR': 'TRY',
    // Asia
    'JP': 'JPY', 'CN': 'CNY', 'KR': 'KRW', 'IN': 'INR', 'SG': 'SGD',
    'HK': 'HKD', 'TW': 'TWD', 'TH': 'THB', 'MY': 'MYR', 'ID': 'IDR',
    'PH': 'PHP', 'VN': 'VND', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR',
    'NP': 'NPR', 'AE': 'AED', 'SA': 'SAR', 'IL': 'ILS', 'QA': 'QAR',
    'KW': 'KWD', 'BH': 'BHD', 'OM': 'OMR', 'JO': 'JOD', 'LB': 'LBP',
    // Oceania
    'AU': 'AUD', 'NZ': 'NZD', 'FJ': 'FJD',
    // South America
    'BR': 'BRL', 'AR': 'ARS', 'CL': 'CLP', 'CO': 'COP', 'PE': 'PEN',
    'VE': 'VES', 'EC': 'USD', 'UY': 'UYU', 'PY': 'PYG', 'BO': 'BOB',
    // Africa
    'ZA': 'ZAR', 'EG': 'EGP', 'NG': 'NGN', 'KE': 'KES', 'GH': 'GHS',
    'MA': 'MAD', 'TN': 'TND', 'DZ': 'DZD', 'ET': 'ETB', 'TZ': 'TZS',
  };

  static const Map<String, String> _currencySymbolMap = {
    'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CNY': '¥',
    'INR': '₹', 'AUD': 'A\$', 'CAD': 'C\$', 'SGD': 'S\$', 'HKD': 'HK\$',
    'CHF': 'CHF', 'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr',
    'KRW': '₩', 'TWD': 'NT\$', 'THB': '฿', 'MYR': 'RM', 'IDR': 'Rp',
    'PHP': '₱', 'VND': '₫', 'BRL': 'R\$', 'MXN': 'MX\$', 'ZAR': 'R',
    'AED': 'د.إ', 'SAR': '﷼', 'ILS': '₪', 'TRY': '₺', 'RUB': '₽',
    'PLN': 'zł', 'CZK': 'Kč', 'HUF': 'Ft', 'NZD': 'NZ\$', 'ARS': 'AR\$',
    'CLP': 'CL\$', 'COP': 'CO\$', 'PEN': 'S/', 'EGP': 'E£', 'NGN': '₦',
  };

  static const Map<String, String> _currencyNameMap = {
    'USD': 'US Dollar', 'EUR': 'Euro', 'GBP': 'British Pound',
    'JPY': 'Japanese Yen', 'CNY': 'Chinese Yuan', 'INR': 'Indian Rupee',
    'AUD': 'Australian Dollar', 'CAD': 'Canadian Dollar',
    'SGD': 'Singapore Dollar', 'HKD': 'Hong Kong Dollar',
    'CHF': 'Swiss Franc', 'SEK': 'Swedish Krona', 'NOK': 'Norwegian Krone',
    'DKK': 'Danish Krone', 'KRW': 'South Korean Won', 'TWD': 'Taiwan Dollar',
    'THB': 'Thai Baht', 'MYR': 'Malaysian Ringgit', 'IDR': 'Indonesian Rupiah',
    'PHP': 'Philippine Peso', 'VND': 'Vietnamese Dong', 'BRL': 'Brazilian Real',
    'MXN': 'Mexican Peso', 'ZAR': 'South African Rand', 'AED': 'UAE Dirham',
    'SAR': 'Saudi Riyal', 'ILS': 'Israeli Shekel', 'TRY': 'Turkish Lira',
    'RUB': 'Russian Ruble', 'PLN': 'Polish Zloty', 'CZK': 'Czech Koruna',
    'HUF': 'Hungarian Forint', 'NZD': 'New Zealand Dollar',
    'PKR': 'Pakistani Rupee', 'BDT': 'Bangladeshi Taka',
  };
}

// MARK: - Location Info

class LocationInfo {
  final String city;
  final String country;
  final String countryCode;
  final String currency;
  final String displayName;

  LocationInfo({
    required this.city,
    required this.country,
    required this.countryCode,
    required this.currency,
    required this.displayName,
  });

  String get fullLocation => city.isEmpty ? country : '$city, $country';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationInfo && displayName == other.displayName;

  @override
  int get hashCode => displayName.hashCode;
}
