import '../services/api_webkassa_exception.dart';

/// Текст ошибки WebKassa для отображения кассиру (сообщение + код).
String formatWebkassaError(ApiWebkassaException e) {
  final code = e.webkassaCode;
  final base = e.message;
  if (code == null) {
    return base;
  }
  return '$base (код WebKassa: $code)';
}

/// Краткая подсказка по коду ошибки.
String? webkassaErrorHint(int? code) {
  return switch (code) {
    2 || 3 => 'Обновите токен: Настройки → Интеграции → WebKassa → «Обновить токен».',
    10 => 'Активируйте лицензию кассы в личном кабинете WebKassa.',
    13 => 'Выполните продажу или откройте смену на кассе.',
    11 => 'Смена превышает 24 часа. Закройте смену на кассе (Z-отчёт).',
    12 => 'Смена в WebKassa уже закрыта. Обновите список смен.',
    1014 => 'Закройте смену: сформируйте Z-отчёт на кассе.',
    18 => 'Выключите автономный (offline) режим на ККМ в ЛК WebKassa.',
    14 => 'Чек уже был передан. Проверьте ExternalCheckNumber в деталях продажи.',
    5 || 6 => 'Проверьте привязку кассы WebKassa к кассиру в админке.',
    _ => null,
  };
}
