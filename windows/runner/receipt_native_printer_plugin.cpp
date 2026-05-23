#include "receipt_native_printer_plugin.h"

#include <windows.h>
#include <winspool.h>

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "winspool.lib")
#pragma comment(lib, "gdi32.lib")

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr int kReceiptWidthPx = 576;  // 80 mm @ 203 dpi
constexpr int kMarginX = 10;
constexpr int kLineHeight = 27;
constexpr int kTitleLineHeight = 34;
constexpr int kFontSizeBody = 27;
constexpr int kFontSizeTitle = 34;
constexpr int kNameColChars = 18;

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, str.data(),
                                       static_cast<int>(str.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()),
                      out.data(), size);
  return out;
}

/// Строки из .cpp (UTF-8) и из Dart — единый путь в wchar_t для DrawTextW.
std::wstring U8(const char* utf8) {
  return utf8 != nullptr ? Utf8ToWide(std::string(utf8)) : std::wstring();
}

std::wstring GetString(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return L"";
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return Utf8ToWide(*s);
  }
  return L"";
}

double GetDouble(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0.0;
  if (const auto* d = std::get_if<double>(&it->second)) return *d;
  if (const auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) return static_cast<double>(*i64);
  return 0.0;
}

int64_t GetInt64(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0;
  if (const auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) return *i64;
  if (const auto* d = std::get_if<double>(&it->second)) return static_cast<int64_t>(*d);
  return 0;
}

std::vector<std::wstring> WrapText(const std::wstring& text, size_t max_width) {
  if (text.empty()) return {L""};
  if (text.size() <= max_width) return {text};

  std::vector<std::wstring> lines;
  std::wstring remaining = text;
  while (!remaining.empty()) {
    if (remaining.size() <= max_width) {
      lines.push_back(remaining);
      break;
    }
    size_t split_at = max_width;
    const std::wstring chunk = remaining.substr(0, max_width);
    const size_t last_space = chunk.find_last_of(L' ');
    if (last_space != std::wstring::npos && last_space > max_width / 2) {
      split_at = last_space + 1;
    }
    std::wstring line = remaining.substr(0, split_at);
    while (!line.empty() && line.back() == L' ') line.pop_back();
    lines.push_back(line);
    remaining = remaining.substr(split_at);
    while (!remaining.empty() && remaining.front() == L' ') remaining.erase(0, 1);
  }
  return lines;
}

std::wstring FormatSum(double value) {
  const int64_t rounded = static_cast<int64_t>(std::llround(value));
  std::wstring s = std::to_wstring(rounded);
  std::wstring out;
  int count = 0;
  for (auto it = s.rbegin(); it != s.rend(); ++it) {
    if (count > 0 && count % 3 == 0) out.push_back(L' ');
    out.push_back(*it);
    ++count;
  }
  std::reverse(out.begin(), out.end());
  return out;
}

std::wstring FormatQty(double qty) {
  const double rounded = std::round(qty);
  if (std::fabs(qty - rounded) < 1e-9) {
    return std::to_wstring(static_cast<int64_t>(rounded));
  }
  std::wostringstream oss;
  oss.setf(std::ios::fixed);
  oss.precision(2);
  oss << qty;
  std::wstring s = oss.str();
  while (!s.empty() && s.back() == L'0') s.pop_back();
  if (!s.empty() && s.back() == L'.') s.pop_back();
  return s;
}

struct ReceiptItem {
  std::wstring name;
  std::wstring qty;
  std::wstring price;
  std::wstring sum;
};

struct ReceiptDocument {
  int sale_id = 0;
  std::wstring cashier;
  std::wstring date_time;
  std::wstring total_qty;
  std::wstring total_sum;
  std::vector<ReceiptItem> items;
};

struct DrawRow {
  enum class Kind { TextCenter, TextLeft, TableHeader, ItemRow, Separator, Spacer };

  Kind kind = Kind::TextLeft;
  std::wstring col_no;
  std::wstring col_name;
  std::wstring col_qty;
  std::wstring col_price;
  std::wstring col_sum;
  std::wstring text;
  bool bold = false;
  int line_height = kLineHeight;
};

class ReceiptLayoutBuilder {
 public:
  void AddCenter(const std::wstring& text, bool bold, int line_height) {
    DrawRow row;
    row.kind = DrawRow::Kind::TextCenter;
    row.text = text;
    row.bold = bold;
    row.line_height = line_height;
    rows_.push_back(row);
  }

  void AddLeft(const std::wstring& text, bool bold = true) {
    DrawRow row;
    row.kind = DrawRow::Kind::TextLeft;
    row.text = text;
    row.bold = bold;
    rows_.push_back(row);
  }

  void AddSeparator() {
    DrawRow row;
    row.kind = DrawRow::Kind::Separator;
    rows_.push_back(row);
  }

  void AddSpacer(int line_height) {
    DrawRow row;
    row.kind = DrawRow::Kind::Spacer;
    row.line_height = line_height;
    rows_.push_back(row);
  }

  void AddTableHeader() {
    DrawRow row;
    row.kind = DrawRow::Kind::TableHeader;
    row.col_no = U8("\u2116");  // № as UTF-8 in source (/utf-8)
    row.col_name = U8("Наименование");
    row.col_qty = U8("К-во");
    row.col_price = U8("Цена");
    row.col_sum = U8("Сумма");
    row.bold = true;
    rows_.push_back(row);
  }

  void AddItemRow(const std::wstring& no, const std::wstring& name,
                  const std::wstring& qty, const std::wstring& price,
                  const std::wstring& sum) {
    DrawRow row;
    row.kind = DrawRow::Kind::ItemRow;
    row.col_no = no;
    row.col_name = name;
    row.col_qty = qty;
    row.col_price = price;
    row.col_sum = sum;
    row.bold = true;
    rows_.push_back(row);
  }

  int TotalHeight() const {
    int h = kMarginX;
    for (const auto& row : rows_) {
      h += row.line_height;
    }
    h += kMarginX;
    return h;
  }

  const std::vector<DrawRow>& rows() const { return rows_; }

 private:
  std::vector<DrawRow> rows_;
};

ReceiptLayoutBuilder BuildLayout(const ReceiptDocument& doc) {
  ReceiptLayoutBuilder layout;
  layout.AddCenter(U8("Almaty Foods"), true, kTitleLineHeight);
  layout.AddCenter(U8("Кассир: ") + doc.cashier, true, kLineHeight);
  layout.AddCenter(U8("Товарный чек \u2116 ") + std::to_wstring(doc.sale_id), true,
                   kLineHeight);
  layout.AddSeparator();
  layout.AddTableHeader();
  layout.AddSeparator();

  int index = 1;
  for (const auto& item : doc.items) {
    const auto name_lines = WrapText(item.name, kNameColChars);
    for (size_t i = 0; i < name_lines.size(); ++i) {
      const bool first = i == 0;
      layout.AddItemRow(
          first ? std::to_wstring(index) : L"",
          name_lines[i],
          first ? item.qty : L"",
          first ? item.price : L"",
          first ? item.sum : L"");
    }
    ++index;
  }

  layout.AddSeparator();
  layout.AddLeft(U8("Общее количество товаров: ") + doc.total_qty, true);
  layout.AddLeft(U8("Итоговая сумма: ") + doc.total_sum, true);
  layout.AddSpacer(10);
  layout.AddCenter(doc.date_time, true, kLineHeight);
  layout.AddSpacer(8);
  layout.AddCenter(U8("Спасибо за покупку!"), true, kLineHeight);
  return layout;
}

void DrawTextInRect(HDC hdc, const std::wstring& text, const RECT& rect, UINT format,
                    HFONT font) {
  HFONT old_font = reinterpret_cast<HFONT>(SelectObject(hdc, font));
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, RGB(0, 0, 0));
  DrawTextW(hdc, text.c_str(), static_cast<int>(text.size()), const_cast<RECT*>(&rect),
            format);
  SelectObject(hdc, old_font);
}

HFONT CreateReceiptFont(int height, bool bold) {
  return CreateFontW(
      -height, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL, FALSE, FALSE, FALSE,
      RUSSIAN_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH | FF_DONTCARE, L"Arial");
}

HBITMAP RenderReceiptBitmap(const ReceiptLayoutBuilder& layout, int* out_height) {
  const int height = layout.TotalHeight();
  *out_height = height;

  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  HBITMAP bitmap =
      CreateCompatibleBitmap(screen_dc, kReceiptWidthPx, height);
  HGDIOBJ old_bitmap = SelectObject(mem_dc, bitmap);

  RECT fill = {0, 0, kReceiptWidthPx, height};
  HBRUSH white = reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
  FillRect(mem_dc, &fill, white);

  HFONT font_normal = CreateReceiptFont(kFontSizeBody, false);
  HFONT font_bold = CreateReceiptFont(kFontSizeBody, true);
  HFONT font_title = CreateReceiptFont(kFontSizeTitle, true);

  const int col_no_left = kMarginX;
  const int col_name_left = 38;
  const int col_qty_left = 312;
  const int col_price_left = 372;
  const int col_sum_left = 434;
  const int right = kReceiptWidthPx - kMarginX;

  int y = kMarginX;
  for (const auto& row : layout.rows()) {
    const int row_h = row.line_height;
    HFONT font = row.bold ? font_bold : font_normal;
    if (row.kind == DrawRow::Kind::TextCenter && row.line_height >= kTitleLineHeight) {
      font = font_title;
    }

    switch (row.kind) {
      case DrawRow::Kind::TextCenter: {
        RECT rect = {kMarginX, y, right, y + row_h};
        DrawTextInRect(mem_dc, row.text, rect,
                       DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        break;
      }
      case DrawRow::Kind::TextLeft: {
        RECT rect = {kMarginX, y, right, y + row_h};
        DrawTextInRect(mem_dc, row.text, rect,
                       DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        break;
      }
      case DrawRow::Kind::Separator: {
        HPEN pen = CreatePen(PS_SOLID, 1, RGB(0, 0, 0));
        HPEN old_pen = reinterpret_cast<HPEN>(SelectObject(mem_dc, pen));
        MoveToEx(mem_dc, kMarginX, y + row_h / 2, nullptr);
        LineTo(mem_dc, right, y + row_h / 2);
        SelectObject(mem_dc, old_pen);
        DeleteObject(pen);
        break;
      }
      case DrawRow::Kind::Spacer:
        break;
      case DrawRow::Kind::TableHeader:
      case DrawRow::Kind::ItemRow: {
        RECT r_no = {col_no_left, y, col_name_left - 2, y + row_h};
        RECT r_name = {col_name_left, y, col_qty_left - 4, y + row_h};
        RECT r_qty = {col_qty_left, y, col_price_left - 4, y + row_h};
        RECT r_price = {col_price_left, y, col_sum_left - 4, y + row_h};
        RECT r_sum = {col_sum_left, y, right, y + row_h};
        DrawTextInRect(mem_dc, row.col_no, r_no,
                       DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        DrawTextInRect(mem_dc, row.col_name, r_name,
                       DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        DrawTextInRect(mem_dc, row.col_qty, r_qty,
                       DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        DrawTextInRect(mem_dc, row.col_price, r_price,
                       DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        DrawTextInRect(mem_dc, row.col_sum, r_sum,
                       DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
                       font);
        break;
      }
    }
    y += row_h;
  }

  DeleteObject(font_normal);
  DeleteObject(font_bold);
  DeleteObject(font_title);

  SelectObject(mem_dc, old_bitmap);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  return bitmap;
}

bool PrintBitmap(HBITMAP bitmap, int width, int height,
                 const std::wstring& printer_name) {
  HDC printer_dc = nullptr;
  if (printer_name.empty()) {
    printer_dc = CreateDCW(L"WINSPOOL", nullptr, nullptr, nullptr);
  } else {
    printer_dc = CreateDCW(L"WINSPOOL", printer_name.c_str(), nullptr, nullptr);
  }
  if (!printer_dc) return false;

  DOCINFOW doc_info = {};
  doc_info.cbSize = sizeof(doc_info);
  doc_info.lpszDocName = L"Alfoods Receipt";

  if (StartDocW(printer_dc, &doc_info) <= 0) {
    DeleteDC(printer_dc);
    return false;
  }

  const int page_width = GetDeviceCaps(printer_dc, HORZRES);
  const int page_height = GetDeviceCaps(printer_dc, VERTRES);
  const int dest_width = page_width > 0 ? page_width : width;

  // Сколько строк исходного bitmap помещается на одну «страницу» драйвера.
  // Иначе StretchBlt на одну страницу обрезает низ (итоги, дата) при длинном чеке.
  int strip_src_h_max = height;
  if (page_height > 0 && dest_width > 0) {
    strip_src_h_max = static_cast<int>(
        (static_cast<long long>(page_height) * width) / dest_width);
    if (strip_src_h_max < 1) strip_src_h_max = 1;
  }

  HDC mem_dc = CreateCompatibleDC(printer_dc);
  if (!mem_dc) {
    AbortDoc(printer_dc);
    DeleteDC(printer_dc);
    return false;
  }
  HGDIOBJ old_bitmap = SelectObject(mem_dc, bitmap);
  SetStretchBltMode(printer_dc, HALFTONE);

  bool ok = true;
  int y_src = 0;
  while (y_src < height) {
    if (StartPage(printer_dc) <= 0) {
      ok = false;
      break;
    }

    const int strip_src_h = std::min(height - y_src, strip_src_h_max);
    const int strip_dest_h = static_cast<int>(
        (static_cast<long long>(strip_src_h) * dest_width) / width);
    if (strip_src_h <= 0 || strip_dest_h <= 0) {
      EndPage(printer_dc);
      ok = false;
      break;
    }

    if (!StretchBlt(printer_dc, 0, 0, dest_width, strip_dest_h, mem_dc, 0, y_src,
                    width, strip_src_h, SRCCOPY)) {
      EndPage(printer_dc);
      ok = false;
      break;
    }

    EndPage(printer_dc);
    y_src += strip_src_h;
  }

  SelectObject(mem_dc, old_bitmap);
  DeleteDC(mem_dc);

  if (ok && y_src < height) {
    ok = false;
  }

  if (ok) {
    EndDoc(printer_dc);
  } else {
    AbortDoc(printer_dc);
  }
  DeleteDC(printer_dc);
  return ok;
}

bool ParseAndPrintReceipt(const EncodableMap& args) {
  ReceiptDocument doc;
  doc.sale_id = static_cast<int>(GetInt64(args, "saleId"));
  doc.cashier = GetString(args, "cashierName");
  doc.date_time = GetString(args, "dateTime");
  doc.total_qty = FormatQty(GetDouble(args, "totalQty"));
  doc.total_sum = FormatSum(GetDouble(args, "total"));

  const auto items_it = args.find(EncodableValue("items"));
  if (items_it != args.end()) {
    if (const auto* items = std::get_if<EncodableList>(&items_it->second)) {
      for (const auto& entry : *items) {
        const auto* item_map = std::get_if<EncodableMap>(&entry);
        if (!item_map) continue;
        ReceiptItem item;
        item.name = GetString(*item_map, "name");
        const std::wstring unit = GetString(*item_map, "unit");
        const double qty = GetDouble(*item_map, "quantity");
        item.qty = (unit == U8("pcs"))
                       ? std::to_wstring(static_cast<int64_t>(std::llround(qty)))
                       : FormatQty(qty);
        item.price = FormatSum(GetDouble(*item_map, "price"));
        item.sum = FormatSum(GetDouble(*item_map, "total"));
        doc.items.push_back(item);
      }
    }
  }

  const std::wstring printer_name = GetString(args, "printerName");
  const ReceiptLayoutBuilder layout = BuildLayout(doc);
  int height = 0;
  HBITMAP bitmap = RenderReceiptBitmap(layout, &height);
  if (!bitmap) return false;

  const bool ok = PrintBitmap(bitmap, kReceiptWidthPx, height, printer_name);
  DeleteObject(bitmap);
  return ok;
}

}  // namespace

extern "C" __declspec(dllexport) void ReceiptNativePrinterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  ReceiptNativePrinterPlugin::RegisterWithRegistrar(windows_registrar);
}

void ReceiptNativePrinterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "receipt_native_printer",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ReceiptNativePrinterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ReceiptNativePrinterPlugin::ReceiptNativePrinterPlugin() = default;
ReceiptNativePrinterPlugin::~ReceiptNativePrinterPlugin() = default;

void ReceiptNativePrinterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("printReceipt") == 0) {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("InvalidArguments", "Arguments must be a map");
      return;
    }
    const bool success = ParseAndPrintReceipt(*arguments);
    if (!success) {
      result->Error("PrintFailed", "Native receipt print failed");
      return;
    }
    result->Success(EncodableValue(true));
    return;
  }
  result->NotImplemented();
}
