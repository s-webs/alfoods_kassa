class OrderUser {
  final int id;
  final String name;
  final String? email;

  const OrderUser({
    required this.id,
    required this.name,
    this.email,
  });

  factory OrderUser.fromJson(Map<String, dynamic> json) {
    return OrderUser(
      id: _parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}

class OrderDeliveryAddress {
  final int? id;
  final String? address;
  final String? city;
  final String? phone;

  const OrderDeliveryAddress({
    this.id,
    this.address,
    this.city,
    this.phone,
  });

  factory OrderDeliveryAddress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OrderDeliveryAddress();
    return OrderDeliveryAddress(
      id: json['id'] != null ? _parseInt(json['id']) : null,
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      phone: json['phone']?.toString(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}

class OrderItem {
  final int id;
  final int productId;
  final String? productName;
  final int quantity;
  final double price;

  const OrderItem({
    required this.id,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.price,
  });

  double get subtotal => price * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return OrderItem(
      id: _parseInt(json['id']),
      productId: _parseInt(json['product_id']),
      productName: product?['name']?.toString(),
      quantity: _parseInt(json['quantity']),
      price: _parseDouble(json['price']),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class Order {
  static const String statusNew = 'new';
  static const String statusInProgress = 'in_progress';
  static const String statusIssued = 'issued';
  static const String statusCancelled = 'cancelled';

  final int id;
  final int userId;
  final String status;
  final double total;
  final DateTime createdAt;
  final String? comment;
  final DateTime? requestedDeliveryDate;
  final OrderUser? user;
  final OrderDeliveryAddress? deliveryAddress;
  final List<OrderItem> items;
  final int? itemsCount;

  const Order({
    required this.id,
    required this.userId,
    required this.status,
    required this.total,
    required this.createdAt,
    this.comment,
    this.requestedDeliveryDate,
    this.user,
    this.deliveryAddress,
    this.items = const [],
    this.itemsCount,
  });

  String get statusLabel {
    switch (status) {
      case statusNew:
        return 'Новый';
      case statusInProgress:
        return 'Заказ собирается';
      case statusIssued:
        return 'Выдан';
      case statusCancelled:
        return 'Отменён';
      default:
        return status;
    }
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>?;
    final deliveryJson = json['delivery_address'] as Map<String, dynamic>?;
    final itemsList = json['items'] as List<dynamic>?;
    return Order(
      id: _parseInt(json['id']),
      userId: _parseInt(json['user_id']),
      status: json['status']?.toString() ?? statusNew,
      total: _parseDouble(json['total']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      comment: json['comment']?.toString(),
      requestedDeliveryDate: json['requested_delivery_date'] != null
          ? DateTime.tryParse(json['requested_delivery_date'].toString())
          : null,
      user: userJson != null ? OrderUser.fromJson(userJson) : null,
      deliveryAddress:
          deliveryJson != null ? OrderDeliveryAddress.fromJson(deliveryJson) : null,
      items: itemsList != null
          ? itemsList
              .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      itemsCount: json['items_count'] != null ? _parseInt(json['items_count']) : null,
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class PaginatedOrders {
  const PaginatedOrders({
    required this.data,
    required this.total,
    required this.perPage,
    required this.currentPage,
  });

  final List<Order> data;
  final int total;
  final int perPage;
  final int currentPage;

  bool get hasMore => (currentPage * perPage) < total;
  int get nextPage => currentPage + 1;
}
