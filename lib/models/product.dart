class Product {
  final int id;
  final int? categoryId;
  final String name;
  final String? newName;
  final String slug;
  final String? barcode;
  final double price;
  final double? discountPrice;
  final double purchasePrice;
  final double stock;
  final double stockThreshold;
  final String unit;
  final bool isActive;
  final Map<String, dynamic>? meta;
  final List<String>? images;

  const Product({
    required this.id,
    this.categoryId,
    required this.name,
    this.newName,
    this.slug = '',
    this.barcode,
    required this.price,
    this.discountPrice,
    this.purchasePrice = 0,
    this.stock = 0,
    this.stockThreshold = 0,
    this.unit = 'pcs',
    this.isActive = true,
    this.meta,
    this.images,
  });

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
    return map;
  }
}
