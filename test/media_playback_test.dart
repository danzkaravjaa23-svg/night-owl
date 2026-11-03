import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:night_owl_ub/core/widgets/network_video.dart';
import 'package:night_owl_ub/features/feed/widgets/story_video.dart';

class _Player extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int, bool>{};
  int created = 0;
  bool initialize = true;
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource dataSource) async {
    final id = ++created;
    streams[id] = StreamController<VideoEvent>();
    if (initialize) {
      streams[id]!.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(640, 360)));
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    await streams[playerId]!.close();
  }

  @override
  Future<void> play(int playerId) async {
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    playing[playerId] = false;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

void main() {
  late _Player player;
  setUp(() {
    player = _Player();
    VideoPlayerPlatform.instance = player;
  });
  Future<void> show(WidgetTester tester, Widget video) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 320, height: 400, child: video)))));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  testWidgets('NetworkVideo keeps an accessible pause button after play',
      (tester) async {
    await show(tester, const NetworkVideo(url: 'https://media.test/clip.mp4'));
    await tester.tap(find.byTooltip('Тоглуулах'));
    await tester.pump();
    expect(player.playing[1], isTrue);
    expect(find.byTooltip('Түр зогсоох').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Түр зогсоох'));
    await tester.pump();
    expect(player.playing[1], isFalse);
    expect(find.byTooltip('Тоглуулах'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'StoryVideo reports initialization timeout and retries a fresh player',
      (tester) async {
    player.initialize = false;
    await show(
        tester, const StoryVideoView(url: 'https://media.test/clip.mp4'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('Видео ачаалж чадсангүй'), findsOneWidget);
    player.initialize = true;
    await tester.tap(find.text('Дахин оролдох'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(player.created, 2);
    expect(find.text('Видео ачаалж чадсангүй'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('StoryVideo turns a decoder error into a retry state',
      (tester) async {
    await show(
        tester, const StoryVideoView(url: 'https://media.test/clip.mp4'));
    player.streams[1]!.addError(
        PlatformException(code: 'VideoError', message: 'unsupported codec'));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.text('Видео ачаалж чадсангүй'), findsOneWidget);
    expect(find.text('Дахин оролдох').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
    // Stream cancellation completes through the platform event queue.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(player.streams[1]!.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
