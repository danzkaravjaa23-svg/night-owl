import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/venue_story_activity.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';

/// A narrow request seam also keeps provider tests independent of real auth.
final venueStoryActivityLoaderProvider = Provider<Future<dynamic> Function()>(
  (ref) => () => SupabaseService.client
      .rpc('venue_story_activity_today')
      .timeout(const Duration(seconds: 8)),
);

/// Errors stay explicit; a failed request must never masquerade as zero stories.
/// During a reload consumers should hide previous values until AsyncData arrives,
/// because a changed session or relationship may have different visibility.
final venueStoryActivityProvider =
    FutureProvider.autoDispose<Map<String, VenueStoryActivity>>((ref) async {
  // Also observe auth events: same-ID sign-out/re-login invalidates old work.
  ref.watch(authUserProvider);
  ref.watch(sessionUserIdProvider);
  ref.watch(socialVersionProvider);
  final load = ref.watch(venueStoryActivityLoaderProvider);
  var disposed = false;
  var foreground = WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  Timer? refresh;
  final observer = _StoryActivityLifecycle(() {
    foreground = true;
    ref.invalidateSelf();
  }, () {
    foreground = false;
    refresh?.cancel();
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    disposed = true;
    refresh?.cancel();
    WidgetsBinding.instance.removeObserver(observer);
  });
  try {
    final activities = parseVenueStoryActivities(await load());
    if (!disposed && foreground) {
      refresh = Timer(
        nextVenueStoryActivityRefresh(DateTime.now(), activities.values),
        ref.invalidateSelf,
      );
    }
    return activities;
  } catch (_) {
    // Offline or rollout errors are retried without a table-wide subscription.
    if (!disposed && foreground) {
      refresh = Timer(const Duration(minutes: 1), ref.invalidateSelf);
    }
    rethrow;
  }
});

class _StoryActivityLifecycle extends WidgetsBindingObserver {
  final VoidCallback refresh;
  final VoidCallback pause;
  _StoryActivityLifecycle(this.refresh, this.pause);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    } else {
      pause();
    }
  }
}
