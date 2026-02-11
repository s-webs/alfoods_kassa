class Counterparty {
  final int id;
  final String name;
  final String? iin;
  final String? kbe;
  final String? iik;
  final String? bankName;
  final String? bik;
  final String? address;
  final String? manager;
  final String? phone;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Counterparty({
    required this.id,
    required this.name,
    this.iin,
    this.kbe,
    this.iik,
    this.bankName,
    this.bik,
    this.address,
    this.manager,
    this.phone,
    this.email,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Counterparty.fromJson(Map<String, dynamic> json) {
    return Counterparty(
      id: json['id'] as int,
      name: json['name'] as String,
      iin: json['iin'] as String?,
      kbe: json['kbe'] as String?,
      iik: json['iik'] as String?,
      bankName: json['bank_name'] as String?,
      bik: json['bik'] as String?,
      address: json['address'] as String?,
      manager: json['manager'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'iin': iin,
      'kbe': kbe,
      'iik': iik,
      'bank_name': bankName,
      'bik': bik,
      'address': address,
      'manager': manager,
      'phone': phone,
      'email': email,
    };
  }
}
