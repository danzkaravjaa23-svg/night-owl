import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';

enum AppPolicy {
  terms('Үйлчилгээний нөхцөл', 'terms.html'),
  privacy('Нууцлалын бодлого', 'privacy.html'),
  support('Тусламж', 'support.html');

  final String title;
  final String file;
  const AppPolicy(this.title, this.file);

  Uri get uri => Uri.parse(
      '${AppConstants.publicAppUrl.replaceFirst(RegExp(r'/+$'), '')}/$file');
}

Future<void> openAppPolicy(BuildContext context, AppPolicy policy,
    {Future<bool> Function(Uri)? open}) async {
  try {
    if (await (open ?? ((uri) => launchUrl(uri)))(policy.uri)) return;
  } catch (_) {
    // The full policy address remains available if the system browser fails.
  }
  if (!context.mounted) return;
  await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(policy.title),
            scrollable: true,
            content: SelectableText(
                'Хуудсыг нээж чадсангүй. Доорх холбоосыг хуулж хөтөчдөө нээгээрэй.\n\n${policy.uri}\n\nТусламж: osokhe@gmail.com'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Хаах')),
            ],
          ));
}

class PolicyLinks extends StatelessWidget {
  const PolicyLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          for (final policy in [AppPolicy.terms, AppPolicy.privacy])
            TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => openAppPolicy(context, policy),
                child: Text(policy.title)),
        ],
      );
}
