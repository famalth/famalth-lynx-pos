import 'dart:convert';
import 'package:http/http.dart' as http;

/// Helper utility for reverse geocoding coordinates into human-readable locations
class GeoHelper {
  static final Map<String, String> _cache = {};

  /// Checks if key is in cache
  static bool hasCached(String key) => _cache.containsKey(key);

  /// Reverse geocodes (lat, lng) into human-readable location e.g. "Dehradun, Uttarakhand"
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    // 1. Try BigDataCloud reverse geocode client API (fast, CORS-friendly, generous)
    try {
      final uri = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final locality = (data['locality'] ?? '').toString().trim();
        final city = (data['city'] ?? '').toString().trim();
        final state = (data['principalSubdivision'] ?? '').toString().trim();
        final country = (data['countryName'] ?? '').toString().trim();

        final Set<String> parts = {};
        if (locality.isNotEmpty) parts.add(locality);
        if (city.isNotEmpty && city != locality) parts.add(city);
        if (state.isNotEmpty) parts.add(state);
        if (parts.isEmpty && country.isNotEmpty) parts.add(country);

        if (parts.isNotEmpty) {
          final addr = parts.join(', ');
          _cache[key] = addr;
          return addr;
        }
      }
    } catch (_) {}

    // 2. Fallback to OpenStreetMap Nominatim
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng');
      final res = await http.get(uri, headers: {
        'User-Agent': 'FamalthLynx/1.0 (pos@famalth.com)'
      }).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final displayName = data['display_name']?.toString();
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.split(',').map((s) => s.trim()).take(3).toList();
          final addr = parts.join(', ');
          _cache[key] = addr;
          return addr;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Parses text like "GPS Location (30.2982, 78.0489)" or "(30.2982, 78.0489)" to extract lat/lng
  static ({double lat, double lng})? parseCoordinates(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)').firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null) {
        return (lat: lat, lng: lng);
      }
    }
    return null;
  }

  /// Formats raw address or coordinates into a clean human-readable string
  static String formatLocation(String? address, double? lat, double? lng) {
    if (address != null && address.isNotEmpty && !address.startsWith('GPS Location (')) {
      if (lat != null && lng != null && !address.contains('(')) {
        return '$address (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
      }
      return address;
    }
    if (lat != null && lng != null) {
      final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
      if (_cache.containsKey(key)) {
        return '${_cache[key]} (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
      }
      return '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    }
    if (address != null && address.isNotEmpty) {
      return address;
    }
    return 'Location not available';
  }
}
