import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';

/// Издадените сертификати (изискване 8). Новите се издават от екрана "История".
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => CertificatesScreenState();
}

class CertificatesScreenState extends State<CertificatesScreen> {
  static final _date = DateFormat('dd.MM.yyyy');

  /// Ширини на колоните: икона, статус, бутон "Сподели".
  static const _iconWidth = 44.0;
  static const _statusWidth = 96.0;
  static const _shareWidth = 44.0;

  List<CertificateInfo>? _items;
  String? _error;
  int? _sharing;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final list = await context.read<ApiClient>().get('/api/certificates') as List;
      if (mounted) setState(() => _items = list.map((j) => CertificateInfo.fromJson(j)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Отваря PDF-а в приложение за преглед или (share = true) отваря менюто "Сподели".
  Future<void> _open(CertificateInfo c, {bool share = false}) async {
    setState(() => _sharing = c.id);
    try {
      final api = context.read<ApiClient>();
      final path = '/api/certificates/${c.id}/pdf';
      final name = 'certificate_${c.number}.pdf';
      await (share ? downloadAndShare(api, path, name) : downloadAndOpen(api, path, name));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: reload,
      child: BandedListView(
        header: const BandTitle(),
        children: [
          if (_error != null) ...[
            InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
            const SizedBox(height: 24),
          ],
          if (items == null && _error == null)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          if (items != null && items.isEmpty)
            EmptyState(
              icon: Icons.verified_outlined,
              title: tr('Няма издадени сертификати'),
              message: tr('Отворете "История", изберете период и натиснете "Сертификат".'),
            ),
          if (items != null && items.isNotEmpty) ...[
            _columnHeaders(),
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
                    for (final (i, c) in items.indexed) ...[
                      if (i > 0) const Divider(),
                      _row(c),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Малки сиви заглавия на колоните над таблицата.
  Widget _columnHeaders() {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 8),
      child: Row(
        children: [
          SizedBox(width: _iconWidth, child: Text('№', style: style)),
          Expanded(child: Text(tr('Протокол'), style: style)),
          SizedBox(width: _statusWidth, child: Text(tr('Статус'), style: style)),
          const SizedBox(width: _shareWidth),
        ],
      ),
    );
  }

  /// Ред за един протокол: PDF икона, номер, дата и брой точки, обект, заключение и бутон "Сподели".
  Widget _row(CertificateInfo c) {
    final theme = Theme.of(context);
    final exceeded = c.conclusion.startsWith('Установено е превишение');
    final secondary = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return InkWell(
      onTap: _sharing == null ? () => _open(c) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: [
            const SizedBox(
              width: _iconWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.picture_as_pdf, color: AppColors.danger, size: 30),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '№ ${c.number}',
                    style: monoStyle(15, weight: FontWeight.w500, color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('{p0} · Точки: {p1}', {'p0': _date.format(c.issuedAt), 'p1': c.pointCount}),
                    style: secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c.title != null)
                    Text(c.title!, style: secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(
              width: _statusWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: StatusPill(
                  label: exceeded ? tr('Превишение') : tr('В норма'),
                  color: exceeded ? AppColors.danger : AppColors.success,
                ),
              ),
            ),
            SizedBox(
              width: _shareWidth,
              child: _sharing == c.id
                  ? const Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: tr('Сподели'),
                      icon: const Icon(Icons.share_outlined, color: AppColors.ink),
                      onPressed: _sharing == null ? () => _open(c, share: true) : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
