import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Издадените сертификати (изискване 8). Новите се издават от екрана "История".
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => CertificatesScreenState();
}

class CertificatesScreenState extends State<CertificatesScreen> {
  static final _date = DateFormat('dd.MM.yyyy HH:mm');

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

  Future<void> _share(CertificateInfo c) async {
    setState(() => _sharing = c.id);
    try {
      await downloadAndShare(context.read<ApiClient>(), '/api/certificates/${c.id}/pdf', 'certificate_${c.number}.pdf');
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
        header: const BandTitle(
          subtitle: 'Издадени протоколи от измерване. Нов сертификат се издава от "История".',
        ),
        children: [
          if (_error != null) InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          if (items == null && _error == null)
            const SectionCard(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
          if (items != null && items.isEmpty)
            const SectionCard(
              title: 'Няма издадени сертификати',
              icon: Icons.verified_outlined,
              child: Text('Отворете "История", изберете период и натиснете "Сертификат".'),
            ),
          for (final c in items ?? <CertificateInfo>[]) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _sharing == null ? () => _share(c) : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconBadge(icon: Icons.picture_as_pdf_outlined, color: AppColors.danger, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('№ ${c.number}', style: theme.textTheme.titleMedium),
                            if (c.title != null) Text(c.title!, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${_date.format(c.issuedAt)} · точки: ${c.pointCount}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            StatusPill(
                              label: c.conclusion.startsWith('Установено е превишение') ? 'Превишение' : 'В норма',
                              color: c.conclusion.startsWith('Установено е превишение') ? AppColors.danger : AppColors.success,
                            ),
                          ],
                        ),
                      ),
                      _sharing == c.id
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.share_outlined, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
