import '../models/product.dart';

bool productHasScannableBarcode(Product p) {
  if (p.barcode != null && p.barcode!.trim().isNotEmpty) {
    return true;
  }
  return p.extraBarcodes.any((b) => b.trim().isNotEmpty);
}

bool productMatchesQuery(Product p, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return true;
  }

  if (p.id.toString().contains(q)) {
    return true;
  }
  if (p.name.toLowerCase().contains(q)) {
    return true;
  }
  if ((p.newName ?? '').toLowerCase().contains(q)) {
    return true;
  }
  if ((p.barcode ?? '').toLowerCase().contains(q)) {
    return true;
  }
  for (final extra in p.extraBarcodes) {
    if (extra.toLowerCase().contains(q)) {
      return true;
    }
  }

  return false;
}

String productDisplayBarcode(Product p) {
  final primary = p.barcode?.trim();
  if (primary != null && primary.isNotEmpty) {
    return primary;
  }
  for (final extra in p.extraBarcodes) {
    final trimmed = extra.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '—';
}
