import 'package:flutter/material.dart';
import '../../../core/widgets/app_motion.dart';
import '../../events/widgets/featured_events_section.dart';
import '../../feed/widgets/explore_reels_section.dart';
import 'map_screen.dart';

/// Keep the interactive map mounted while browsing events and short videos.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _scroll = ScrollController();
  final _discovery = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showDiscovery() {
    final target = _discovery.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          duration:
              AppMotion.reduced(context) ? Duration.zero : AppMotion.enter,
          curve: Curves.easeOutCubic);
    }
  }

  void _showMap() {
    if (!_scroll.hasClients) return;
    if (AppMotion.reduced(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0,
          duration: AppMotion.enter, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(builder: (context, constraints) {
        final mapHeight = (constraints.maxHeight - 76).clamp(500.0, 760.0);
        return SingleChildScrollView(
            key: const PageStorageKey('explore-discovery-scroll'),
            controller: _scroll,
            child: Column(children: [
              SizedBox(
                  height: mapHeight, child: const MapScreen(embedded: true)),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: TextButton.icon(
                      onPressed: _showDiscovery,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: const Text('Эвент, богино видео үзэх'))),
              Column(key: _discovery, children: [
                const FeaturedEventsSection(),
                const ExploreReelsSection(),
                const SizedBox(height: 28),
                TextButton.icon(
                    onPressed: _showMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Газрын зураг руу буцах')),
                const SizedBox(height: 24),
              ]),
            ]));
      }));
}
