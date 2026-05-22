import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import 'nkt_request_actions_panel.dart';
import 'nkt_variants_ui.dart';

bool _isImageCode(String code) {
  final lower = code.toLowerCase();
  return lower.contains('image') ||
      lower.contains('photo') ||
      lower.contains('picture');
}

class _FormFieldSpec {
  const _FormFieldSpec({
    required this.schema,
    this.parentCode,
    this.index,
    this.isCompoundContainer = false,
  });

  final NktRequestAttribute schema;
  final String? parentCode;
  final int? index;
  final bool isCompoundContainer;
}

String _fieldKey(String code, String? parentCode, int? index) {
  return '$code|${parentCode ?? ''}|${index ?? 0}';
}

List<_FormFieldSpec> _expandSchema(
  List<NktRequestAttribute> items, {
  String? parentCode,
  int? index,
}) {
  final out = <_FormFieldSpec>[];
  for (final item in items) {
    if (_isImageCode(item.code)) continue;

    if (item.isCompound && item.nested.isNotEmpty) {
      final blockIndex = index ?? 1;
      out.add(_FormFieldSpec(
        schema: item,
        parentCode: parentCode,
        index: blockIndex,
        isCompoundContainer: true,
      ));
      out.addAll(
        _expandSchema(item.nested, parentCode: item.code, index: blockIndex),
      );
    } else if (!item.isCompound) {
      out.add(_FormFieldSpec(
        schema: item,
        parentCode: parentCode,
        index: index,
      ));
    }
  }
  return out;
}

/// Full-page NKT product request form (all portal attributes).
class NktProductRequestForm extends StatefulWidget {
  const NktProductRequestForm({
    super.key,
    required this.api,
    required this.product,
    required this.onProductUpdated,
  });

  final ApiService api;
  final Product product;
  final ValueChanged<Product> onProductUpdated;

  @override
  State<NktProductRequestForm> createState() => _NktProductRequestFormState();
}

class _NktProductRequestFormState extends State<NktProductRequestForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _oktruController;
  bool _autoPublication = false;
  bool _submitToModeration = false;
  bool _loading = true;
  String? _loadError;
  List<_FormFieldSpec> _fields = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  Product? _product;

  bool get _isEdit => _product?.hasNktRequest == true;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _oktruController = TextEditingController();
    _load();
  }

  @override
  void didUpdateWidget(NktProductRequestForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.product.nktRequestId != widget.product.nktRequestId ||
        oldWidget.product.nktRequestStatus != widget.product.nktRequestStatus) {
      _product = widget.product;
    }
  }

  @override
  void dispose() {
    _oktruController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.api.nktGetRequestAttributes(),
        widget.api.nktGetRequestFormData(widget.product.id),
      ]);
      final schema = results[0] as List<NktRequestAttribute>;
      final formData = results[1] as NktRequestFormData;

      final prefillMap = <String, String>{};
      for (final a in formData.attributes) {
        prefillMap[_fieldKey(a.code, a.parentCode, a.index)] = a.value;
      }

      _oktruController.text = formData.oktru;
      _autoPublication = formData.autoPublication;

      final fields = _expandSchema(schema);
      for (final f in fields) {
        if (f.isCompoundContainer) continue;
        final key = _fieldKey(f.schema.code, f.parentCode, f.index);
        final prefillVal = prefillMap[key] ?? '';
        if (f.schema.dataType == 'boolean') {
          _boolValues[key] =
              prefillVal.toLowerCase() == 'true' || prefillVal == '1';
        } else {
          _controllers[key] = TextEditingController(text: prefillVal);
        }
      }

      if (!mounted) return;
      setState(() {
        _fields = fields;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is DioException
            ? nktExtractDioError(e, fallback: 'Не удалось загрузить форму')
            : 'Не удалось загрузить форму';
        _loading = false;
      });
    }
  }

  List<NktRequestAttributeValue> _collectAttributes() {
    final values = <NktRequestAttributeValue>[];
    for (final f in _fields) {
      final code = f.schema.code;
      if (f.isCompoundContainer) {
        values.add(NktRequestAttributeValue(
          code: code,
          value: '',
          parentCode: f.parentCode,
          index: f.index ?? 1,
        ));
        continue;
      }
      final key = _fieldKey(code, f.parentCode, f.index);
      if (f.schema.dataType == 'boolean') {
        values.add(NktRequestAttributeValue(
          code: code,
          value: (_boolValues[key] ?? false) ? 'true' : 'false',
          parentCode: f.parentCode,
          index: f.index,
        ));
      } else {
        values.add(NktRequestAttributeValue(
          code: code,
          value: _controllers[key]?.text.trim() ?? '',
          parentCode: f.parentCode,
          index: f.index,
        ));
      }
    }
    return values;
  }

  NktRequestPayload _buildPayload() {
    return NktRequestPayload(
      oktru: _oktruController.text.trim(),
      autoPublication: _autoPublication,
      attributes: _collectAttributes(),
    );
  }

  void _onProductUpdated(Product updated) {
    setState(() => _product = updated);
    widget.onProductUpdated(updated);
  }

  Future<void> _submit({required bool toModeration}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final payload = _buildPayload();
      Product updated;
      if (!_isEdit) {
        updated = await widget.api.nktCreateProductRequest(
          widget.product.id,
          payload,
          submitToModeration: toModeration || _submitToModeration,
        );
      } else {
        updated = await widget.api.nktUpdateProductRequest(
          widget.product.id,
          payload,
        );
        if (toModeration || _submitToModeration) {
          updated = await widget.api.nktSubmitRequestModeration(updated.id);
        }
      }
      if (!mounted) return;
      _onProductUpdated(updated);
      showToast(
        context,
        _isEdit
            ? 'Заявка обновлена'
            : 'Заявка №${updated.nktRequestId} создана',
      );
      await _reloadAfterSave(updated);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        e is DioException
            ? nktExtractDioError(e, fallback: 'Ошибка сохранения заявки')
            : 'Ошибка сохранения заявки',
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _reloadAfterSave(Product updated) async {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _boolValues.clear();
    _product = updated;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _product ?? widget.product;

    if (_loading && _fields.isEmpty) {
      if (_loadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (p.hasNktRequest) ...[
                  NktRequestActionsPanel(
                    api: widget.api,
                    product: p,
                    onProductUpdated: _onProductUpdated,
                    lifecycleOnly: true,
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isEdit
                              ? 'Редактирование заявки №${p.nktRequestId}'
                              : 'Новая заявка в НКТ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.name,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _oktruController,
                          decoration: const InputDecoration(
                            labelText: 'ОКТРУ *',
                            hintText: '1015-0001-0029-100001212',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Укажите ОКТРУ'
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Автопубликация'),
                          value: _autoPublication,
                          onChanged: (v) =>
                              setState(() => _autoPublication = v),
                        ),
                        if (!_isEdit)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Сразу отправить на модерацию'),
                            value: _submitToModeration,
                            onChanged: (v) =>
                                setState(() => _submitToModeration = v),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._buildAttributeSections(),
              ],
            ),
          ),
        ),
        Material(
          elevation: 4,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (_isEdit) ...[
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () => _submit(toModeration: false),
                      child: const Text('Сохранить'),
                    ),
                    FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _submit(toModeration: true),
                      child: const Text('Сохранить и на модерацию'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: _loading
                          ? null
                          : () =>
                              _submit(toModeration: _submitToModeration),
                      child: const Text('Создать заявку'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAttributeSections() {
    final widgets = <Widget>[];
    String? currentCompound;

    for (final f in _fields) {
      if (f.isCompoundContainer) {
        currentCompound = f.schema.nameRu.isNotEmpty
            ? f.schema.nameRu
            : f.schema.code;
        widgets.add(
          _SectionHeader(title: currentCompound),
        );
        continue;
      }

      if (f.parentCode == null && currentCompound != null) {
        currentCompound = null;
      }

      widgets.add(_buildField(f, indent: f.parentCode != null));
    }

    if (widgets.isEmpty) {
      return [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Атрибуты заявки не загружены'),
          ),
        ),
      ];
    }
    return widgets;
  }

  Widget _buildField(_FormFieldSpec f, {bool indent = false}) {
    final schema = f.schema;
    final label = schema.nameRu.isNotEmpty ? schema.nameRu : schema.code;
    final requiredMark = schema.isRequired ? ' *' : '';
    final key = _fieldKey(schema.code, f.parentCode, f.index);

    Widget field;
    if (f.isCompoundContainer) {
      return const SizedBox.shrink();
    }

    if (schema.dataType == 'boolean') {
      field = SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('$label$requiredMark'),
        subtitle: _fieldSubtitle(schema),
        value: _boolValues[key] ?? false,
        onChanged: (v) => setState(() => _boolValues[key] = v),
      );
    } else {
      _controllers.putIfAbsent(key, () => TextEditingController());
      field = TextFormField(
        controller: _controllers[key],
        decoration: InputDecoration(
          labelText: '$label$requiredMark',
          hintText: schema.dictionaryCode != null
              ? 'Код справочника: ${schema.dictionaryCode}'
              : null,
          helperText: schema.descriptionRu,
          helperMaxLines: 3,
        ),
        maxLines: schema.dataType == 'text' ? 4 : 1,
        keyboardType: schema.dataType == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: schema.isRequired
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null
            : null,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 24 : 16, 8, 16, 8),
        child: field,
      ),
    );
  }

  Widget? _fieldSubtitle(NktRequestAttribute schema) {
    final parts = <String>[];
    if (schema.dictionaryCode != null) {
      parts.add('Справочник: ${schema.dictionaryCode}');
    }
    parts.add('Код: ${schema.code}');
    if (schema.dataType == 'multiDictionary') {
      parts.add('Несколько значений через @');
    }
    return Text(parts.join(' · '), style: const TextStyle(fontSize: 11));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.surface,
            ),
      ),
    );
  }
}
