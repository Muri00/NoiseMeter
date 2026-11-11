import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Възпроизвеждане на WAV записа от сървъра. Звукът се зарежда едва при първото
/// натискане на „Пусни“ и се изтегля поточно (с превъртане), а не целият наведнъж.
class RecordingPlayer extends StatefulWidget {
  const RecordingPlayer({super.key, required this.measurementId});

  final int measurementId;

  @override
  State<RecordingPlayer> createState() => _RecordingPlayerState();
}

class _RecordingPlayerState extends State<RecordingPlayer> {
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (!_loaded) {
      final api = context.read<ApiClient>();
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        await _player.setAudioSource(AudioSource.uri(
          api.url('/api/measurements/${widget.measurementId}/audio'),
          headers: api.authHeaders,
        ));
        _loaded = true;
      } catch (_) {
        setState(() => _error = tr('Записът не може да бъде зареден'));
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (_player.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
    await _player.play();
  }

  static String _time(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Сиво хапче: пускане/пауза, "WAV", плъзгач и време.
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final completed = snapshot.data?.processingState == ProcessingState.completed;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
              decoration: const ShapeDecoration(color: AppColors.surfaceHigh, shape: StadiumBorder()),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _loading ? null : _toggle,
                    color: AppColors.ink,
                    icon: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(playing && !completed ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    tooltip: playing ? tr('Пауза') : tr('Пусни'),
                  ),
                  const Text(
                    'WAV',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink),
                  ),
                  Expanded(
                    child: StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, posSnap) {
                        final total = _player.duration ?? Duration.zero;
                        final pos = posSnap.data ?? Duration.zero;
                        final max = total.inMilliseconds.toDouble();
                        return Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: AppColors.ink,
                                  inactiveTrackColor: AppColors.outline,
                                  thumbColor: AppColors.ink,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                ),
                                child: Slider(
                                  value: max == 0 ? 0 : pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                                  max: max == 0 ? 1 : max,
                                  onChanged: max == 0 ? null : (v) => _player.seek(Duration(milliseconds: v.round())),
                                ),
                              ),
                            ),
                            Text(
                              '${_time(pos)} / ${_time(total)}',
                              style: monoStyle(12, color: AppColors.textSecondary),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
            ],
          ],
        );
      },
    );
  }
}
