import 'dart:ui';

import 'package:auramind/auramind_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final values in [<double>[], [0.6], [0.4, 0.7, 0.55]]) {
    test('LinePainter paints ${values.length} value(s) without error', () {
      final recorder = PictureRecorder();
      LinePainter(values).paint(Canvas(recorder), const Size(300, 200));
      expect(recorder.endRecording(), isNotNull);
    });
  }
}
