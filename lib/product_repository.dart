import 'dart:convert';

import 'package:http/http.dart' as http;

/// Simple product model.
class Product {
  const Product({
    required this.name,
    this.brand,
    this.category,
    this.size,
    this.origin,
    this.description,
  });

  final String name;
  final String? brand;
  final String? category;
  final String? size;
  final String? origin;
  final String? description;
}

/// Looks up product info for a barcode.
///
/// Strategy:
/// 1. Check the local database first (instant, works offline).
/// 2. Optionally fall back to Open Food Facts, a free public UPC API.
///    Niche/regulated products (like the example jar) usually won't be in
///    public databases, which is why the local map exists.
class ProductRepository {
  ProductRepository._();
  static final ProductRepository instance = ProductRepository._();

  /// Set to false if you want purely offline/local lookups.
  static const bool useOnlineFallback = true;

  /// Local database keyed by the decoded barcode string.
  /// The entry below matches the UPC-A code on the example jar (850050317029).
  static const Map<String, Product> _localDb = {
    '850050317029': Product(
      name: 'Mac Nilla',
      brand: 'Nanticoke',
      category: 'Flower',
      size: '3.5 g',
      origin: 'New York State',
      description:
          'Whole flower, 3.5 g jar. Adult-use product (21+), licensed in '
          'New York State. Best if used within 90 days of opening; store '
          'away from light, sealed in the container.',
    ),
    // Add more products here:
    // '012345678905': Product(name: '...', brand: '...'),
  };

  Future<Product?> lookup(String barcode) async {
    // 1. Local database.
    final local = _localDb[barcode];
    if (local != null) return local;

    // 2. Online fallback (Open Food Facts — free, no API key required).
    if (useOnlineFallback) {
      try {
        final uri = Uri.parse(
            'https://world.openfoodfacts.org/api/v2/product/$barcode.json');
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          if (json['status'] == 1) {
            final p = json['product'] as Map<String, dynamic>;
            final name = (p['product_name'] as String?)?.trim();
            if (name != null && name.isNotEmpty) {
              return Product(
                name: name,
                brand: (p['brands'] as String?)?.trim(),
                category: (p['categories'] as String?)?.split(',').first.trim(),
                size: (p['quantity'] as String?)?.trim(),
                origin: (p['countries'] as String?)?.trim(),
              );
            }
          }
        }
      } catch (_) {
        // Network failure — fall through to "not found".
      }
    }

    return null; // Unknown product; UI shows the raw barcode instead.
  }
}
