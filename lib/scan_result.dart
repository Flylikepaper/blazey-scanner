/// Normalized schema that all scanned codes get merged into.
///
/// Identity (SKU-level) comes from the UPC; batch-level data (COA, lot,
/// potency, traceability) comes from the QR / Retail ID when available.
library;

/// What a single machine code most likely *is*, ordered by usefulness for
/// cannabis product identification (higher index = more valuable).
enum CodeClass {
  unknown, // couldn't classify
  dispensaryInternal, // POS/inventory sticker — low value outside that store
  marketing, // brand website / social link
  stateTraceability, // regulatory/package identifier (non-URL lot/tag ID)
  retailSku, // UPC-A / EAN — product identity
  manufacturerCoa, // brand page with batch selector
  coaUrl, // direct link to a lab report
  metrcRetailId, // serialized regulated retail item — best case
}

extension CodeClassInfo on CodeClass {
  String get label => switch (this) {
        CodeClass.metrcRetailId => 'Metrc Retail ID',
        CodeClass.coaUrl => 'Lab COA link',
        CodeClass.manufacturerCoa => 'Manufacturer COA page',
        CodeClass.retailSku => 'Retail SKU (UPC/EAN)',
        CodeClass.stateTraceability => 'Traceability / lot ID',
        CodeClass.marketing => 'Marketing link',
        CodeClass.dispensaryInternal => 'Dispensary internal code',
        CodeClass.unknown => 'Unclassified',
      };

  String get usefulness => switch (this) {
        CodeClass.metrcRetailId || CodeClass.coaUrl => 'Excellent',
        CodeClass.manufacturerCoa ||
        CodeClass.retailSku ||
        CodeClass.stateTraceability =>
          'Good',
        CodeClass.marketing => 'Low–medium',
        CodeClass.dispensaryInternal => 'Low',
        CodeClass.unknown => '—',
      };
}

/// One decoded machine code plus its classification.
class ClassifiedCode {
  const ClassifiedCode({
    required this.rawValue,
    required this.symbology, // e.g. 'qrCode', 'upcA'
    required this.codeClass,
    this.url,
    this.notes,
  });

  final String rawValue;
  final String symbology;
  final CodeClass codeClass;

  /// Parsed URL if the payload is (or contains) one.
  final Uri? url;

  /// Human-readable classifier reasoning ("matched Metrc domain", etc.).
  final String? notes;

  bool get isQr => symbology == 'qrCode';
}

/// Batch/lot-level information extracted from QR-side sources.
class BatchInfo {
  const BatchInfo({
    this.lotId,
    this.coaUrl,
    this.retailIdUrl,
    this.source,
  });

  final String? lotId;
  final Uri? coaUrl;
  final Uri? retailIdUrl;
  final CodeClass? source; // which class of code this came from

  bool get isEmpty => lotId == null && coaUrl == null && retailIdUrl == null;
}

/// The merged result of one scanning session.
class NormalizedScanResult {
  const NormalizedScanResult({
    required this.codes,
    this.sku,
    this.productName,
    this.brand,
    this.category,
    this.size,
    this.origin,
    this.description,
    this.batch = const BatchInfo(),
  });

  /// All codes captured, sorted best-first.
  final List<ClassifiedCode> codes;

  // ---- SKU level (from UPC lookup) ----
  final String? sku;
  final String? productName;
  final String? brand;
  final String? category;
  final String? size;
  final String? origin;
  final String? description;

  // ---- Batch level (from QR side) ----
  final BatchInfo batch;

  ClassifiedCode? get bestCode => codes.isEmpty ? null : codes.first;

  bool get hasProductIdentity => productName != null;
}
