import 'package:flutter/material.dart';
import '../widgets/admin_gate.dart';
import 'admin_review_queue_screen.dart';

class AdminContentScreen extends StatelessWidget {
  const AdminContentScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const AdminGate(child: AdminReviewQueueScreen());
}
