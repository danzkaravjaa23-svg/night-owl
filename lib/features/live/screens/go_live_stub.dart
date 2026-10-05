import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';

class GoLiveScreen extends StatelessWidget {
  const GoLiveScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          leading: IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(AppRoutes.feed),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: const EmptyState(
          icon: Icons.videocam_off_outlined,
          title: 'Шууд дамжуулалт түр боломжгүй',
          subtitle: 'Шууд дамжуулалт хараахан идэвхжээгүй байна. '
              'Пост, story болон видео хуваалцах боломжтой.',
        ),
      );
}
