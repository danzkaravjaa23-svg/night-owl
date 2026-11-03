import 'package:flutter/material.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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
        // Large text wraps the controls and list introduction onto more lines.
        // Give the retained map/list enough room for useful content; the outer
        // scroll still makes the discovery action reachable on short screens.
        final textGrowth =
            (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, 24.0);
        final mapHeight =
            (constraints.maxHeight - 116).clamp(500.0, 760.0) + textGrowth * 20;
        return SingleChildScrollView(
            key: const PageStorageKey('explore-discovery-scroll'),
            controller: _scroll,
            child: Column(children: [
              SizedBox(
                  height: mapHeight, child: const MapScreen(embedded: true)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Material(
                  color: AppColors.accentStart
                      .withValues(alpha: AppColors.isDarkMode ? .12 : .07),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: _showDiscovery,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome_outlined,
                            color: AppColors.accentStart, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Эвент, богино видео үзэх',
                                  style: AppTextStyles.labelLg
                                      .copyWith(color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text('Багийн сонголт · Газруудын бичлэг',
                                  style: AppTextStyles.bodyXs.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.4)),
                            ])),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_downward_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
              Column(key: _discovery, children: [
                const FeaturedEventsSection(),
                const ExploreReelsSection(),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Divider(height: 1, color: AppColors.hairline)),
                TextButton.icon(
                    onPressed: _showMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Газрын зураг руу буцах')),
                const SizedBox(height: 24),
              ]),
            ]));
      }));
}
