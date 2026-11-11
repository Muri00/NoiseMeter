import 'package:flutter_test/flutter_test.dart';
import 'package:noise_meter/models/models.dart';

void main() {
  test('indicatorName follows IEC 61672 notation', () {
    expect(indicatorName('LAF'), 'LA,F');
    expect(indicatorName('LZSmax'), 'LZ,S,max');
    expect(indicatorName('LAeq'), 'LA,eq');
  });

  test('indicatorDescription explains the code in words', () {
    expect(indicatorDescription('LAFmax'), 'Максимално ниво, филтър A, бързо (F)');
    expect(indicatorDescription('LAeq'), 'Еквивалентно ниво, филтър A');
    expect(indicatorDescription('LZS'), 'Текущо ниво, без честотен филтър (Z), бавно (S)');
    expect(indicatorDescription('Lpmin'), 'Минимално звуково налягане без филтри');
  });

  test('formatHz', () {
    expect(formatHz(20), '20 Hz');
    expect(formatHz(31.5), '31.5 Hz');
    expect(formatHz(20000), '20 kHz');
    expect(formatHz(12500), '12.5 kHz');
  });

  test('Device JSON round trip', () {
    final d = Device.fromJson({
      'id': 1, 'brand': 'miniDSP', 'model': 'UMIK-1', 'serial_number': '2182175',
      'sensitivity_dbfs': -18, 'freq_min_hz': 20, 'freq_max_hz': 20000, 'calibration_offset_db': null,
    });
    expect(d.title, 'miniDSP UMIK-1');
    expect(d.toJson()['sensitivity_dbfs'], -18.0);
  });
}
