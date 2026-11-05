import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../services/auth_provider_settings.dart';
import 'auth_ui.dart' show OrDivider;

/// Allows auth routes and their sign-in actions to share the same settings
/// source. Outside a supplied scope the app-wide public-settings cache is used.
class AuthProviderSettingsScope extends InheritedWidget {
  final AuthProviderSettings settings;
  const AuthProviderSettingsScope(
      {super.key, required this.settings, required super.child});

  static AuthProviderSettings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AuthProviderSettingsScope>()
          ?.settings ??
      AuthProviderSettings.shared;

  @override
  bool updateShouldNotify(AuthProviderSettingsScope oldWidget) =>
      settings != oldWidget.settings;
}

class AuthProviderOptions extends StatefulWidget {
  final Widget googleButton, appleButton;
  final bool showDivider, enabled;
  const AuthProviderOptions(
      {super.key,
      required this.googleButton,
      required this.appleButton,
      this.showDivider = false,
      this.enabled = true});

  @override
  State<AuthProviderOptions> createState() => _AuthProviderOptionsState();
}

class _AuthProviderOptionsState extends State<AuthProviderOptions> {
  AuthProviderSettings? _settings;
  late Future<AuthProviderAvailability> _availability;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AuthProviderSettingsScope.of(context);
    if (!identical(settings, _settings)) {
      _settings = settings;
      _availability = settings.fetch();
    }
  }

  void _retry() {
    if (!widget.enabled) return;
    final next = _settings!.fetch(refresh: true);
    setState(() {
      _availability = next;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AuthProviderAvailability>(
      future: _availability,
      builder: (context, snapshot) {
        // Do not retain a previously enabled button while retrying a new check.
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                  liveRegion: true,
                  child: Text('Нэвтрэх нэмэлт аргуудыг шалгаж байна…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary))));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(children: [
                Semantics(
                    liveRegion: true,
                    child: Text('Apple, Google нэвтрэлтийг шалгаж чадсангүй.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary))),
                TextButton.icon(
                    key: const ValueKey('auth-providers-retry'),
                    onPressed: widget.enabled ? _retry : null,
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Дахин шалгах')),
              ]));
        }
        final providers = snapshot.requireData;
        if (!providers.anyEnabled) return const SizedBox.shrink();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: widget.showDivider ? 20 : 12),
              if (widget.showDivider) ...[
                const OrDivider(),
                const SizedBox(height: 20),
              ],
              if (providers.google) widget.googleButton,
              if (providers.apple) widget.appleButton,
            ]);
      });
}
