import 'webkassa_print_line.dart';

class FiscalReceipt {
  const FiscalReceipt({
    this.externalCheckNumber,
    this.checkNumber,
    this.checkOrderNumber,
    this.shiftNumber,
    this.ticketUrl,
    this.ticketPrintUrl,
    this.offlineMode = false,
    this.fiscalStatus,
    this.printLines = const [],
  });

  final String? externalCheckNumber;
  final String? checkNumber;
  final int? checkOrderNumber;
  final int? shiftNumber;
  final String? ticketUrl;
  final String? ticketPrintUrl;
  final bool offlineMode;
  final String? fiscalStatus;
  final List<WebkassaPrintLine> printLines;

  factory FiscalReceipt.fromJson(Map<String, dynamic> json) {
    final rawLines = json['print_lines'];
    final lines = rawLines is List
        ? rawLines
            .whereType<Map>()
            .map((e) => WebkassaPrintLine.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList()
        : <WebkassaPrintLine>[];

    return FiscalReceipt(
      externalCheckNumber: json['external_check_number']?.toString(),
      checkNumber: json['check_number']?.toString() ??
          json['webkassa_check_number']?.toString(),
      checkOrderNumber: _parseIntOrNull(json['check_order_number']),
      shiftNumber: _parseIntOrNull(json['shift_number']),
      ticketUrl: json['ticket_url']?.toString(),
      ticketPrintUrl: json['ticket_print_url']?.toString(),
      offlineMode: json['offline_mode'] == true,
      fiscalStatus: json['fiscal_status']?.toString(),
      printLines: lines,
    );
  }

  static int? _parseIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
