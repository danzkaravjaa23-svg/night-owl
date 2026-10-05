import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/widgets/sculpted_icon.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'dimensional icons avoid offscreen shader layers in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: Wrap(children: [
            for (var i = 0; i < 16; i++)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: SculptedIcon(Icons.chat_bubble_rounded)),
          ]))));
      expect(find.byType(SculptedIcon), findsNWidgets(16));
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty,
          reason: 'The gradient belongs on the glyph paint; each icon must not '
              'allocate a separate offscreen compositing layer.');
      expect(tester.takeException(), isNull);
    });
  }
}
