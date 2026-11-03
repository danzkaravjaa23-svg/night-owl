import 'package:flutter/material.dart';
import '../widgets/admin_gate.dart';
import 'admin_records_screen.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const AdminGate(child: AdminRecordsScreen(kind: 'users'));
}
