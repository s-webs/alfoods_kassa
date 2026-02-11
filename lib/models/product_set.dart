import 'product.dart';

class ProductSetItem {
  final int productId;
  final double quantity;
  final Product? product;

  const ProductSetItem({
    required this.productId,
    required this.quantity,
    this.product,
  });

  factory ProductSetItem.fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    Product? product;
    if (productRaw is Map<String, dynamic>) {
      product = Product.fromJson(productRaw);
    }
    return ProductSetItem(
      productId: json['product_id'] as int,
      quantity: _parseDouble(json['quantity']),
      product: product,
    );
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class ProductSet {
  final int id;
  final String name;
  final String slug;
  final String? barcode;
  final double price;
  final double? discountPrice;
  final bool isActive;
  final List<ProductSetItem> items;
  final Map<String, dynamic>? meta;

  const ProductSet({
    required this.id,
    required this.name,
    this.slug = '',
    this.barcode,
    required this.price,
    this.discountPrice,
    this.isActive = true,
    this.items = const [],
    this.meta,
  });

  factory ProductSet.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>?;
    final items = itemsRaw != null
        ? itemsRaw
            .map((e) => ProductSetItem.fromJson(e as Map<String, dynamic>))
            .toList()
        : <ProductSetItem>[];

    final metaRaw = json['meta'];
    Map<String, dynamic>? meta;
    if (metaRaw is Map<String, dynamic>) {
      meta = metaRaw;
    } else if (metaRaw is Map) {
      meta = Map<String, dynamic>.from(metaRaw as Map);
    }

    return ProductSet(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      barcode: json['barcode'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPrice: json['discount_price'] != null
          ? (json['discount_price'] as num).toDouble()
          : null,
      isActive: json['is_active'] == null ? true : json['is_active'] as bool,
      items: items,
      meta: meta,
    );
  }

  double get effectivePrice =>
      (discountPrice != null && discountPrice! > 0) ? discountPrice! : price;
}
