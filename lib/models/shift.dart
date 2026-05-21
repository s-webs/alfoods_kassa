class Shift {
  final int id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final Map<String, dynamic>? webkassaZReport;
  final DateTime? webkassaZReportAt;
  final bool hasZReport;

  const Shift({
    required this.id,
    required this.openedAt,
    this.closedAt,
    this.webkassaZReport,
    this.webkassaZReportAt,
    this.hasZReport = false,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? zReport;
    final rawZ = json['webkassa_z_report'];
    if (rawZ is Map<String, dynamic>) {
      zReport = rawZ;
    } else if (rawZ is Map) {
      zReport = Map<String, dynamic>.from(rawZ);
    }

    return Shift(
      id: json['id'] as int,
      openedAt: DateTime.parse(json['opened_at'] as String),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      webkassaZReport: zReport,
      webkassaZReportAt: json['webkassa_z_report_at'] != null
          ? DateTime.parse(json['webkassa_z_report_at'] as String)
          : null,
      hasZReport: json['has_z_report'] == true || zReport != null,
    );
  }

  bool get isOpen => closedAt == null;
}

class ShiftCloseResult {
  const ShiftCloseResult({
    required this.shift,
    this.zReport,
    this.zReportSkipped = false,
    this.webkassaShiftAlreadyClosed = false,
    this.message,
  });

  final Shift shift;
  final Map<String, dynamic>? zReport;
  final bool zReportSkipped;
  final bool webkassaShiftAlreadyClosed;
  final String? message;

  factory ShiftCloseResult.fromJson(Map<String, dynamic> json) {
    final shiftJson = json['shift'] as Map<String, dynamic>? ?? json;
    Map<String, dynamic>? zReport;
    final rawZ = json['z_report'];
    if (rawZ is Map<String, dynamic>) {
      zReport = rawZ;
    } else if (rawZ is Map) {
      zReport = Map<String, dynamic>.from(rawZ);
    }

    return ShiftCloseResult(
      shift: Shift.fromJson(shiftJson),
      zReport: zReport,
      zReportSkipped: json['z_report_skipped'] == true,
      webkassaShiftAlreadyClosed: json['webkassa_shift_already_closed'] == true,
      message: json['message']?.toString(),
    );
  }
}
