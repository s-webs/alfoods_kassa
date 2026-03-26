import 'dart:math';

/// Fixed timezone helpers for `UTC+5`.
///
/// Dart's `DateTime` does not support arbitrary fixed offsets as a real timezone,
/// so we convert to "wall clock" time for formatting and (optionally) build
/// ISO strings with `+05:00` offset.
class TimeUtil {
  static const Duration utcPlus5Offset = Duration(hours: 5);
  static Duration _utcCorrectionOffset = Duration.zero;

  /// Applies correction between device UTC and synchronized UTC.
  static void setUtcCorrectionOffset(Duration offset) {
    _utcCorrectionOffset = offset;
  }

  static Duration get utcCorrectionOffset => _utcCorrectionOffset;

  /// Synchronized UTC "now" (device UTC + correction).
  static DateTime syncedUtcNow() {
    return DateTime.now().toUtc().add(_utcCorrectionOffset);
  }

  /// Current moment expressed as "UTC+5 wall clock" (conversion for display).
  static DateTime nowUtcPlus5Wall() {
    final utcNow = syncedUtcNow();
    return utcNow.add(utcPlus5Offset);
  }

  /// Convert any DateTime to "UTC+5 wall clock" for formatting.
  static DateTime toUtcPlus5Wall(DateTime dt) {
    return dt.toUtc().add(utcPlus5Offset);
  }

  /// Build ISO8601 string for `UTC+5` from a given UTC instant.
  ///
  /// Example: `2026-03-26T17:04:05+05:00`
  static String isoUtcPlus5FromUtc(DateTime utcInstant) {
    final wall = utcInstant.add(utcPlus5Offset);
    // Force milliseconds to be stable even if the input had fractional seconds.
    final ms = wall.millisecond;
    final sec = wall.second;
    final carryMs = max(0, ms);

    final y = wall.year.toString().padLeft(4, '0');
    final m = wall.month.toString().padLeft(2, '0');
    final d = wall.day.toString().padLeft(2, '0');
    final hh = wall.hour.toString().padLeft(2, '0');
    final mm = wall.minute.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');

    // Keep milliseconds only if non-zero to avoid noise.
    if (carryMs == 0) {
      return '$y-$m-$d' 'T$hh:$mm:$ss+05:00';
    }
    final mmm = carryMs.toString().padLeft(3, '0');
    return '$y-$m-$d' 'T$hh:$mm:$ss.$mmm+05:00';
  }
}

