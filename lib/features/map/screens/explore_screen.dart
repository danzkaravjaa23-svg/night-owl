import 'package:flutter/material.dart';
import 'map_screen.dart';

/// Map first, with a list switch for venues without a registered location.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});
  @override
  Widget build(BuildContext context) => const MapScreen(embedded: true);
}
