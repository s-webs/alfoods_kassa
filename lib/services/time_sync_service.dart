import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/storage.dart';
import '../utils/time_util.dart';

/// Synchronizes device time with public time sources and keeps
/// a cached correction offset for stable app behavior.
class TimeSyncService {
  TimeSyncService(this._storage, {Dio? dio}) : _dio = dio ?? Dio();

  final Storage _storage;
  final Dio _dio;
  Timer? _timer;

  static const Duration _syncInterval = Duration(minutes: 15);
  static const Duration _requestTimeout = Duration(seconds: 5);
  static const Duration _maxAllowedAbsOffset = Duration(hours: 24);

  Future<void> restoreCachedOffset() async {
    final ms = _storage.timeOffsetMs;
    TimeUtil.setUtcCorrectionOffset(Duration(milliseconds: ms));
  }

  void startAutoSync() {
    _timer?.cancel();
    _timer = Timer.periodic(_syncInterval, (_) {
      unawaited(syncNow());
    });
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> syncNow() async {
    final before = DateTime.now().toUtc();
    DateTime? serverUtc;

    serverUtc ??= await _fetchWorldTimeApiUtc();
    serverUtc ??= await _fetchUtcFromHttpDate('https://www.google.com');
    serverUtc ??= await _fetchUtcFromHttpDate('https://www.cloudflare.com');

    if (serverUtc == null) return false;

    final after = DateTime.now().toUtc();
    final midpoint =
        before.add(Duration(milliseconds: after.difference(before).inMilliseconds ~/ 2));
    final offset = serverUtc.difference(midpoint);

    if (offset.abs() > _maxAllowedAbsOffset) {
      return false;
    }

    TimeUtil.setUtcCorrectionOffset(offset);
    await _storage.setTimeOffsetMs(offset.inMilliseconds);
    await _storage.setTimeLastSyncMs(DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  Future<DateTime?> _fetchWorldTimeApiUtc() async {
    try {
      final response = await _dio
          .get<Map<String, dynamic>>(
            'https://worldtimeapi.org/api/timezone/Etc/UTC',
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: _requestTimeout,
              sendTimeout: _requestTimeout,
            ),
          )
          .timeout(_requestTimeout);

      final raw = response.data?['utc_datetime'];
      if (raw is! String || raw.isEmpty) return null;
      return DateTime.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _fetchUtcFromHttpDate(String url) async {
    try {
      final response = await _dio
          .get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: _requestTimeout,
              sendTimeout: _requestTimeout,
            ),
          )
          .timeout(_requestTimeout);

      final dateHeader = response.headers.value(HttpHeaders.dateHeader);
      if (dateHeader == null || dateHeader.isEmpty) return null;
      return HttpDate.parse(dateHeader).toUtc();
    } catch (_) {
      return null;
    }
  }
}
