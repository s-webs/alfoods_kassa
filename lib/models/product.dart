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
  final String unit;

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
    this.unit = 'pcs',
  });

  factory Product.fromJson(Map<String, dynamic> json) {
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
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      unit: json['unit'] as String? ?? 'pcs',
    );
  }

  double get effectivePrice => discountPrice ?? price;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'slug': slug,
      'category_id': categoryId,
      'unit': unit,
      'price': price,
      'barcode': barcode,
      'stock': stock,
    };
    if (discountPrice != null) {
      map['discount_price'] = discountPrice;
    }
    return map;
  }
}
