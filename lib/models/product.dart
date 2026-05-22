class Product {
  final int id;
  final int? categoryId;
  final String name;
  final String? newName;
  final String slug;
  final String? barcode;
  final List<String> extraBarcodes;
  final double price;
  final double? discountPrice;
  final double purchasePrice;
  final double stock;
  final double stockThreshold;
  final String unit;
  final bool isActive;
  final Map<String, dynamic>? meta;
  final List<String>? images;

  // НКТ (Национальный каталог товаров Казахстана)
  final String? nktNtin;
  final int? nktProductId;
  final String? nktGtin;
  final String? nktNameRu;
  final String? nktNameKk;
  final bool? nktIsMarkedeac;
  final bool? nktIsSocial;
  final String? nktMeasureCode;
  final String? nktMeasureName;
  final bool? nktIsDeactivated;
  final String? nktDeactivationReason;
  final String? nktDuplicateOfNtin;
  final DateTime? nktModifiedAt;
  final DateTime? nktCheckedAt;
  final bool? nktNotFound;
  final int? nktRequestId;
  final String? nktRequestStatus;
  final String? nktRequestStatusLabel;
  final DateTime? nktRequestUpdatedAt;

  const Product({
    required this.id,
    this.categoryId,
    required this.name,
    this.newName,
    this.slug = '',
    this.barcode,
    this.extraBarcodes = const [],
    required this.price,
    this.discountPrice,
    this.purchasePrice = 0,
    this.stock = 0,
    this.stockThreshold = 0,
    this.unit = 'pcs',
    this.isActive = true,
    this.meta,
    this.images,
    this.nktNtin,
    this.nktProductId,
    this.nktGtin,
    this.nktNameRu,
    this.nktNameKk,
    this.nktIsMarkedeac,
    this.nktIsSocial,
    this.nktMeasureCode,
    this.nktMeasureName,
    this.nktIsDeactivated,
    this.nktDeactivationReason,
    this.nktDuplicateOfNtin,
    this.nktModifiedAt,
    this.nktCheckedAt,
    this.nktNotFound,
    this.nktRequestId,
    this.nktRequestStatus,
    this.nktRequestStatusLabel,
    this.nktRequestUpdatedAt,
  });

  bool get isLinkedToNkt => nktNtin != null && nktNtin!.isNotEmpty;
  bool get isNktNotFound => nktNotFound == true && !isLinkedToNkt;
  bool get hasNktRequest => nktRequestId != null && nktRequestId! > 0;

  String get nktRequestStatusDisplay =>
      (nktRequestStatusLabel != null && nktRequestStatusLabel!.isNotEmpty)
          ? nktRequestStatusLabel!
          : (nktRequestStatus ?? '—');

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _parseStringList(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool? _parseBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final metaRaw = json['meta'];
    Map<String, dynamic>? meta;
    if (metaRaw is Map<String, dynamic>) {
      meta = metaRaw;
    } else if (metaRaw is Map) {
      meta = Map<String, dynamic>.from(metaRaw as Map);
    }
    final imagesRaw = json['images'] as List<dynamic>?;
    final images = imagesRaw != null
        ? imagesRaw.map((e) => e.toString()).toList()
        : null;
    return Product(
      id: json['id'] as int,
      categoryId: json['category_id'] as int?,
      name: json['name'] as String,
      newName: json['new_name'] as String?,
      slug: json['slug'] as String? ?? '',
      barcode: json['barcode'] as String?,
      extraBarcodes: _parseStringList(json['extra_barcodes']),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPrice: json['discount_price'] != null
          ? (json['discount_price'] as num).toDouble()
          : null,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      stock: _parseDouble(json['stock']),
      stockThreshold: _parseDouble(json['stock_threshold']),
      unit: json['unit'] as String? ?? 'pcs',
      isActive: json['is_active'] == null ? true : json['is_active'] as bool,
      meta: meta,
      images: images,
      nktNtin: json['nkt_ntin'] as String?,
      nktProductId: json['nkt_product_id'] as int?,
      nktGtin: json['nkt_gtin'] as String?,
      nktNameRu: json['nkt_name_ru'] as String?,
      nktNameKk: json['nkt_name_kk'] as String?,
      nktIsMarkedeac: _parseBool(json['nkt_is_markedeac']),
      nktIsSocial: _parseBool(json['nkt_is_social']),
      nktMeasureCode: json['nkt_measure_code'] as String?,
      nktMeasureName: json['nkt_measure_name'] as String?,
      nktIsDeactivated: _parseBool(json['nkt_is_deactivated']),
      nktDeactivationReason: json['nkt_deactivation_reason'] as String?,
      nktDuplicateOfNtin: json['nkt_duplicate_of_ntin'] as String?,
      nktModifiedAt: _parseDate(json['nkt_modified_at']),
      nktCheckedAt: _parseDate(json['nkt_checked_at']),
      nktNotFound: _parseBool(json['nkt_not_found']),
      nktRequestId: json['nkt_request_id'] as int?,
      nktRequestStatus: json['nkt_request_status'] as String?,
      nktRequestStatusLabel: json['nkt_request_status_label'] as String?,
      nktRequestUpdatedAt: _parseDate(json['nkt_request_updated_at']),
    );
  }

  /// Если discount_price задан и > 0 — используется скидочная цена, иначе — обычная.
  double get effectivePrice =>
      (discountPrice != null && discountPrice! > 0) ? discountPrice! : price;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'slug': slug,
      'category_id': categoryId,
      'unit': unit,
      'price': price,
      'barcode': barcode,
      'stock': stock,
      'stock_threshold': stockThreshold,
    };
    if (discountPrice != null) {
      map['discount_price'] = discountPrice;
    }
    map['is_active'] = isActive;
    if (meta != null) {
      map['meta'] = meta;
    }
    if (images != null) {
      map['images'] = images;
    }
    if (extraBarcodes.isNotEmpty) {
      map['extra_barcodes'] = extraBarcodes;
    }
    return map;
  }
}
