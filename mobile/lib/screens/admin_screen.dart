import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Администрация: норми на зоните, стандарти (коефициенти на филтрите) и роли на потребителите.
/// Достъпна е само за администратор; сървърът проверява правата и при всяка заявка.
/// Показва се като раздел в основния екран - заглавието и менюто са на HomeShell.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.map_outlined), text: tr('Зони и норми')),
              Tab(icon: const Icon(Icons.rule_rounded), text: tr('Стандарти')),
              Tab(icon: const Icon(Icons.group_outlined), text: tr('Потребители')),
            ],
          ),
          const Expanded(child: TabBarView(children: [_ZonesTab(), _StandardsTab(), _UsersTab()])),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

/// Списък в бяла заоблена карта с тънка рамка; редовете са разделени с линии.
/// Незадължителното [title] е удебелено заглавие над картата.
class _ListCard extends StatelessWidget {
  const _ListCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Text(title!, style: sectionLabelStyle(context)),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  child,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Ред в група: заглавие (със значка), сиви редове под него и стрелка или действие вдясно.
class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, this.lines = const [], this.badge, this.trailing, this.onTap, this.onLongPress});

  final String title;
  final List<String> lines;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, trailing == null ? 12 : 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [Text(title, style: theme.textTheme.bodyLarge), ?badge],
                    ),
                    for (final l in lines.where((l) => l.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(l, style: monoStyle(13, color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Зони ----------------

class _ZonesTab extends StatelessWidget {
  const _ZonesTab();

  Future<void> _edit(BuildContext context, Zone? zone) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ZoneDialog(zone: zone));
    if (saved == true && context.mounted) await context.read<UserData>().reloadZonesAndStandards();
  }

  Future<void> _delete(BuildContext context, Zone zone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Изтриване на зона')),
        content: Text(tr('Да се изтрие ли зоната „{name}“? Вече записаните измервания пазят своите норми.',
            {'name': zone.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Изтрий'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<ApiClient>().delete('/api/admin/zones/${zone.id}');
      if (context.mounted) await context.read<UserData>().reloadZonesAndStandards();
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = context.watch<UserData>().zones;
    final theme = Theme.of(context);
    String norms(Zone z) {
      final parts = [
        if (z.day != null) '${tr('Ден')} ${_fmt(z.day)}',
        if (z.evening != null) '${tr('Вечер')} ${_fmt(z.evening)}',
        if (z.night != null) '${tr('Нощ')} ${_fmt(z.night)}',
      ];
      return parts.isEmpty ? '' : '${parts.join(' · ')} dB(A)';
    }

    Widget group(String title, String category) {
      final items = zones.where((z) => z.category == category).toList();
      return _ListCard(
        title: title,
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Няма въведени зони.'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            ),
          for (final z in items)
            _ListRow(
              title: z.code.isEmpty ? z.name : '${z.code}. ${z.name}',
              lines: [norms(z)],
              onTap: () => _edit(context, z),
              onLongPress: () => _delete(context, z),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('Изтрий'),
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary),
                    onPressed: () => _delete(context, z),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                ],
              ),
            ),
        ],
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                group(tr('Открити територии (Прил. 2, табл. 2)'), 'outdoor'),
                const SizedBox(height: 24),
                group(tr('Помещения'), 'indoor'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: Text(tr('Зона')),
      ),
    );
  }
}

class _ZoneDialog extends StatefulWidget {
  const _ZoneDialog({this.zone});

  final Zone? zone;

  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  late final _code = TextEditingController(text: widget.zone?.code);
  late final _name = TextEditingController(text: widget.zone?.name);
  late final _day = TextEditingController(text: _fmt(widget.zone?.day));
  late final _evening = TextEditingController(text: _fmt(widget.zone?.evening));
  late final _night = TextEditingController(text: _fmt(widget.zone?.night));
  late String _category = widget.zone?.category ?? 'outdoor';
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, _day, _evening, _night]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = Zone(
      code: _code.text.trim(),
      name: _name.text.trim(),
      category: _category,
      day: _num(_day),
      evening: _num(_evening),
      night: _num(_night),
      sortOrder: widget.zone?.sortOrder ?? 100,
    ).toJson();
    try {
      final api = context.read<ApiClient>();
      if (widget.zone == null) {
        await api.post('/api/admin/zones', body);
      } else {
        await api.put('/api/admin/zones/${widget.zone!.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    Widget norm(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
          ),
        );
    return AlertDialog(
      title: Text(widget.zone == null ? tr('Нова зона') : tr('Редакция на зона')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'outdoor', label: Text(tr('Открита територия'))),
                  ButtonSegment(value: 'indoor', label: Text(tr('Помещение'))),
                ],
                selected: {_category},
                onSelectionChanged: (s) => setState(() => _category = s.first),
              ),
              gap,
              TextField(controller: _code, decoration: InputDecoration(labelText: tr('Код (напр. т. от таблицата)'))),
              gap,
              TextField(controller: _name, maxLines: null, decoration: InputDecoration(labelText: tr('Наименование'))),
              gap,
              Row(children: [
                norm(_day, tr('Ден')),
                const SizedBox(width: 8),
                norm(_evening, tr('Вечер')),
                const SizedBox(width: 8),
                norm(_night, tr('Нощ')),
              ]),
              if (_error != null) ...[
                gap,
                InfoBanner(message: _error!, color: Theme.of(context).colorScheme.error, icon: Icons.error_outline),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Отказ'))),
        FilledButton(onPressed: _save, child: Text(tr('Запази'))),
      ],
    );
  }
}

// ---------------- Стандарти ----------------

class _StandardsTab extends StatelessWidget {
  const _StandardsTab();

  Future<void> _edit(BuildContext context, Standard? standard) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _StandardDialog(standard: standard));
    if (saved == true && context.mounted) await context.read<UserData>().reloadZonesAndStandards();
  }

  @override
  Widget build(BuildContext context) {
    final standards = context.watch<UserData>().standards;
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          ReadableWidth(
            child: _ListCard(
              children: [
                for (final s in standards)
                  _ListRow(
                    title: s.name,
                    badge: s.isDefault ? StatusPill(label: tr('по подразбиране'), color: theme.colorScheme.primary) : null,
                    lines: [
                      'f1–f4: ${s.poles.map((p) => _fmt(p)).join(' / ')} Hz',
                      'F ${_fmt((s.params['fast'] as num).toDouble())} s · S ${_fmt((s.params['slow'] as num).toDouble())} s · '
                          'I ${_fmt((s.params['impulse_rise'] as num).toDouble())} / ${_fmt((s.params['impulse_decay'] as num).toDouble())} s',
                    ],
                    onTap: () => _edit(context, s),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: Text(tr('Стандарт')),
      ),
    );
  }
}

class _StandardDialog extends StatefulWidget {
  const _StandardDialog({this.standard});

  final Standard? standard;

  @override
  State<_StandardDialog> createState() => _StandardDialogState();
}

class _StandardDialogState extends State<_StandardDialog> {
  late final Map<String, dynamic> _p = widget.standard?.params ??
      {'poles': [20.598997, 107.65265, 737.86223, 12194.217], 'fast': 0.125, 'slow': 1.0, 'impulse_rise': 0.035, 'impulse_decay': 1.5};
  late final _code = TextEditingController(text: widget.standard?.code);
  late final _name = TextEditingController(text: widget.standard?.name);
  late final _poles = [
    for (final v in (_p['poles'] as List)) TextEditingController(text: _fmt((v as num).toDouble())),
  ];
  late final _taus = {
    for (final k in ['fast', 'slow', 'impulse_rise', 'impulse_decay'])
      k: TextEditingController(text: _fmt((_p[k] as num).toDouble())),
  };
  late bool _default = widget.standard?.isDefault ?? false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, ..._poles, ..._taus.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = {
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'is_default': _default,
      'sort_order': widget.standard?.sortOrder ?? 100,
      'params': {
        'poles': [for (final c in _poles) _num(c)],
        for (final e in _taus.entries) e.key: _num(e.value),
      },
    };
    try {
      final api = context.read<ApiClient>();
      if (widget.standard == null) {
        await api.post('/api/admin/standards', body);
      } else {
        await api.put('/api/admin/standards/${widget.standard!.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    Widget field(TextEditingController c, String label, {String? suffix}) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        );
    return AlertDialog(
      title: Text(widget.standard == null ? tr('Нов стандарт') : tr('Редакция на стандарт')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('Наименование'))),
              gap,
              TextField(controller: _code, decoration: InputDecoration(labelText: tr('Код'))),
              gap,
              Text(tr('Полюсни честоти на филтрите A и C'), style: Theme.of(context).textTheme.labelLarge),
              gap,
              Row(children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  field(_poles[i], 'f${i + 1}', suffix: 'Hz'),
                ],
              ]),
              gap,
              Text(tr('Времеви константи'), style: Theme.of(context).textTheme.labelLarge),
              gap,
              Row(children: [
                field(_taus['fast']!, 'F', suffix: 's'),
                const SizedBox(width: 8),
                field(_taus['slow']!, 'S', suffix: 's'),
              ]),
              gap,
              Row(children: [
                field(_taus['impulse_rise']!, tr('I нарастване'), suffix: 's'),
                const SizedBox(width: 8),
                field(_taus['impulse_decay']!, tr('I спад'), suffix: 's'),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('По подразбиране')),
                value: _default,
                onChanged: (v) => setState(() => _default = v),
              ),
              if (_error != null)
                InfoBanner(message: _error!, color: Theme.of(context).colorScheme.error, icon: Icons.error_outline),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Отказ'))),
        FilledButton(onPressed: _save, child: Text(tr('Запази'))),
      ],
    );
  }
}

// ---------------- Потребители ----------------

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<ApiClient>().get('/api/admin/users') as List;
      if (mounted) setState(() => _users = list.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _setAdmin(Map<String, dynamic> u, bool admin) async {
    try {
      await context.read<ApiClient>().put('/api/admin/users/${u['id']}/role', {'role': admin ? 'admin' : 'user'});
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthService>().user;
    if (_error != null) return Center(child: Text(_error!));
    if (_users == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListCard(
                  children: [
                    for (final u in _users!)
                      _ListRow(
                        title: u['username'] as String,
                        lines: [(u['email'] as String?) ?? ''],
                        // Администраторът не може да премахне собствените си права.
                        onTap: u['id'] == me?.id ? null : () => _setAdmin(u, u['is_admin'] != true),
                        trailing: Switch(
                          value: u['is_admin'] == true,
                          onChanged: u['id'] == me?.id ? null : (v) => _setAdmin(u, v),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(tr('Включено = администратор'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
