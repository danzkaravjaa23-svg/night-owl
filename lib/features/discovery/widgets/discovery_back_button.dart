import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DiscoveryBackButton extends StatelessWidget {
  final String fallback;
  const DiscoveryBackButton({super.key, this.fallback = '/discovery'});

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'Буцах',
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallback);
        }
      });
}
