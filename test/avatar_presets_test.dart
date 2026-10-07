import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/constants/avatar_presets.dart';
import 'package:night_owl_ub/core/widgets/app_avatar.dart';

String? assetName(Image image) {
  final provider = image.image is ResizeImage
      ? (image.image as ResizeImage).imageProvider
      : image.image;
  return provider is AssetImage ? provider.assetName : null;
}

void main() {
  test('four distinct choices round-trip through the saved avatar field', () {
    expect(NightOwlAvatars.all, hasLength(4));
    expect(NightOwlAvatars.all.map((p) => p.value).toSet(), hasLength(4));
    expect(NightOwlAvatars.all.map((p) => p.assetPath).toSet(), hasLength(4));
    for (final preset in NightOwlAvatars.all) {
      expect(NightOwlAvatars.fromValue(' ${preset.value} '), same(preset));
    }
    expect(NightOwlAvatars.fromValue('nightowl://avatar/missing'), isNull);
    expect(NightOwlAvatars.fromValue('https://photos.example/me.jpg'), isNull);
  });

  testWidgets('all selected owls render locally with ring and online status',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      for (final preset in NightOwlAvatars.all)
        AppAvatar(
            imageUrl: preset.value,
            size: 64,
            showRing: true,
            showOnlineDot: true),
    ])));
    await tester.pumpAndSettle();
    expect(find.byType(CachedNetworkImage), findsNothing);
    for (final preset in NightOwlAvatars.all) {
      expect(
          find.byWidgetPredicate(
              (w) => w is Image && assetName(w) == preset.assetPath),
          findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing and invalid photos show an owl instead of a blank avatar',
      (tester) async {
    for (final value in [
      null,
      '',
      '  ',
      'nightowl://avatar/missing',
      'javascript:alert(1)',
      'file:///private/photo.png'
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: AppAvatar(imageUrl: value, initial: 'Z', size: 48)));
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('Z'), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              assetName(w) == NightOwlAvatars.defaultPreset.assetPath),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'uploaded photo keeps its URL and receives the owl error fallback',
      (tester) async {
    const photo = 'https://photos.example/me.jpg';
    await tester.pumpWidget(
        const MaterialApp(home: AppAvatar(imageUrl: photo, size: 48)));
    final network =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(network.imageUrl, photo);
    final context = tester.element(find.byType(AppAvatar));
    await tester.pumpWidget(MaterialApp(
        home: network.errorWidget!(context, photo, Exception('offline'))));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            assetName(w) == NightOwlAvatars.defaultPreset.assetPath),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
