import 'shift.dart';

class PaginatedShifts {
  const PaginatedShifts({
    required this.data,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
  });

  final List<Shift> data;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  factory PaginatedShifts.fromResponse(dynamic raw) {
    if (raw is List<dynamic>) {
      final list = raw
          .map((e) => Shift.fromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedShifts(
        data: list,
        total: list.length,
        perPage: list.length,
        currentPage: 1,
        lastPage: 1,
      );
    }

    final map = raw as Map<String, dynamic>;
    final items = (map['data'] as List<dynamic>)
        .map((e) => Shift.fromJson(e as Map<String, dynamic>))
        .toList();

    return PaginatedShifts(
      data: items,
      total: _parseInt(map['total']),
      perPage: _parseInt(map['per_page']),
      currentPage: _parseInt(map['current_page'], fallback: 1),
      lastPage: _parseInt(map['last_page'], fallback: 1),
    );
  }

  static int _parseInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }
}
