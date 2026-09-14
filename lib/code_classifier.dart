import 'package:mobile_scanner/mobile_scanner.dart';

import 'product_repository.dart';
import 'scan_result.dart';

/// Classifies raw decoded payloads into [CodeClass]es and merges a whole
/// scanning session into one [NormalizedScanResult].
///
/// The heuristics below encode the state-by-state reality: QR *technology*
/// is standardized, cannabis QR *semantics* are not — so classification is
/// best-effort pattern matching, ordered by confidence, never assumption.
class CodeClassifier {
  CodeClassifier._();

  // -- Domain heuristics ----------------------------------------------------

  /// Hosts strongly associated with Metrc Retail ID.
  /// Metrc's serialized consumer QR system; exact hostnames may evolve, so we
  /// match any metrc.com subdomain plus known Retail ID hosts.
  static final _metrcHosts = RegExp(
    r'(^|\.)metrc\.com$|(^|\.)retailid\.com$',
    caseSensitive: false,
  );

  /// Cannabis testing labs that host COAs directly (extend as you encounter
  /// more — this list skews toward labs active in the NY market).
  static final _labHosts = RegExp(
    r'kaycha|greenanalyticsllc|green-analytics|keystonelabs|steephill|'
    r'confidentcannabis|cannalysis|sclabs|mcrlabs|prolificalabs|'
    r'phytatest|certus|acslab',
    caseSensitive: false,
  );

  /// URL path fragments that suggest a certificate of analysis / lab result.
  static final _coaPath = RegExp(
    r'coa|certificate|lab-?results?|test-?results?|analysis|batch',
    caseSensitive: false,
  );

  /// Non-URL payloads that look like a Metrc package tag
  /// (24-char alphanumeric, e.g. 1A4060300003F2B000001234).
  static final _metrcTag = RegExp(r'^1A[0-9A-F]{22}$', caseSensitive: false);

  /// Generic lot/batch identifier patterns (letters+digits with separators).
  static final _lotLike = RegExp(r'^[A-Z0-9][A-Z0-9\-_/\.]{5,31}$');

  /// UPC-A/EAN payloads: 8, 12, or 13 digits.
  static final _retailDigits = RegExp(r'^\d{8}$|^\d{12,13}$');

  /// Short numeric strings typical of POS/inventory stickers.
  static final _posLike = RegExp(r'^\d{4,7}$|^[A-Z]{1,3}\d{3,8}$');

  // -- Classification -------------------------------------------------------

  static ClassifiedCode classify(Barcode barcode) {
    final raw = (barcode.rawValue ?? '').trim();
    final symbology = barcode.format.name;
    final uri = _tryParseUrl(raw);

    // 1D retail symbologies are SKUs regardless of payload quirks.
    const retailFormats = {
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    };
    if (retailFormats.contains(barcode.format) ||
        (!_isQr(barcode) && _retailDigits.hasMatch(raw))) {
      return ClassifiedCode(
        rawValue: raw,
        symbology: symbology,
        codeClass: CodeClass.retailSku,
        notes: 'Retail symbology → SKU identity',
      );
    }

    // URL payloads (mostly QR).
    if (uri != null) {
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();

      if (_metrcHosts.hasMatch(host)) {
        return ClassifiedCode(
          rawValue: raw,
          symbology: symbology,
          codeClass: CodeClass.metrcRetailId,
          url: uri,
          notes: 'Metrc domain → serialized Retail ID',
        );
      }
      if (_labHosts.hasMatch(host)) {
        return ClassifiedCode(
          rawValue: raw,
          symbology: symbology,
          codeClass: CodeClass.coaUrl,
          url: uri,
          notes: 'Known testing-lab domain → direct COA',
        );
      }
      if (_coaPath.hasMatch(path) || _coaPath.hasMatch(uri.query)) {
        // COA-ish path on a brand domain → manufacturer COA page.
        return ClassifiedCode(
          rawValue: raw,
          symbology: symbology,
          codeClass: CodeClass.manufacturerCoa,
          url: uri,
          notes: 'COA/lab-results path on non-lab domain',
        );
      }
      return ClassifiedCode(
        rawValue: raw,
        symbology: symbology,
        codeClass: CodeClass.marketing,
        url: uri,
        notes: 'Generic URL → likely brand/marketing page',
      );
    }

    // Non-URL text payloads.
    if (_metrcTag.hasMatch(raw)) {
      return ClassifiedCode(
        rawValue: raw,
        symbology: symbology,
        codeClass: CodeClass.stateTraceability,
        notes: 'Matches Metrc package-tag format',
      );
    }
    if (_isQr(barcode) && _lotLike.hasMatch(raw) && !_posLike.hasMatch(raw)) {
      return ClassifiedCode(
        rawValue: raw,
        symbology: symbology,
        codeClass: CodeClass.stateTraceability,
        notes: 'Lot/batch-style identifier',
      );
    }
    if (_posLike.hasMatch(raw)) {
      return ClassifiedCode(
        rawValue: raw,
        symbology: symbology,
        codeClass: CodeClass.dispensaryInternal,
        notes: 'Short internal-inventory-style code',
      );
    }

    return ClassifiedCode(
      rawValue: raw,
      symbology: symbology,
      codeClass: CodeClass.unknown,
      notes: 'No pattern matched',
    );
  }

  static bool _isQr(Barcode b) =>
      b.format == BarcodeFormat.qrCode || b.format == BarcodeFormat.dataMatrix;

  static Uri? _tryParseUrl(String raw) {
    var s = raw;
    if (!s.contains('://') &&
        RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}(/|$)', caseSensitive: false)
            .hasMatch(s)) {
      s = 'https://$s'; // bare-domain QR payloads
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.host.contains('.') ? uri : null;
  }

  // -- Normalization --------------------------------------------------------

  /// Merge all codes from one session into the app's product schema.
  static Future<NormalizedScanResult> normalize(
      Iterable<Barcode> barcodes) async {
    // Classify + dedupe by payload, keep best classification per payload.
    final byPayload = <String, ClassifiedCode>{};
    for (final b in barcodes) {
      final c = classify(b);
      if (c.rawValue.isEmpty) continue;
      final existing = byPayload[c.rawValue];
      if (existing == null ||
          c.codeClass.index > existing.codeClass.index) {
        byPayload[c.rawValue] = c;
      }
    }
    final codes = byPayload.values.toList()
      ..sort((a, b) => b.codeClass.index.compareTo(a.codeClass.index));

    // SKU identity from the best retail code.
    String? sku;
    Product? product;
    for (final c in codes.where((c) => c.codeClass == CodeClass.retailSku)) {
      sku = c.rawValue;
      product = await ProductRepository.instance.lookup(c.rawValue);
      if (product != null) break;
    }

    // Batch info from the best QR-side source.
    Uri? retailIdUrl;
    Uri? coaUrl;
    String? lotId;
    CodeClass? source;
    for (final c in codes) {
      switch (c.codeClass) {
        case CodeClass.metrcRetailId:
          retailIdUrl ??= c.url;
          source ??= c.codeClass;
        case CodeClass.coaUrl || CodeClass.manufacturerCoa:
          coaUrl ??= c.url;
          source ??= c.codeClass;
        case CodeClass.stateTraceability:
          lotId ??= c.rawValue;
          source ??= c.codeClass;
        default:
          break;
      }
    }

    return NormalizedScanResult(
      codes: codes,
      sku: sku,
      productName: product?.name,
      brand: product?.brand,
      category: product?.category,
      size: product?.size,
      origin: product?.origin,
      description: product?.description,
      batch: BatchInfo(
        lotId: lotId,
        coaUrl: coaUrl,
        retailIdUrl: retailIdUrl,
        source: source,
      ),
    );
  }
}
