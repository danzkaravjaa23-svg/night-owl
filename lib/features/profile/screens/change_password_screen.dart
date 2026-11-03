import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../auth/widgets/auth_ui.dart';
import '../../auth/services/account_credentials_service.dart';
import '../../auth/widgets/password_form.dart';

class ChangePasswordScreen extends StatefulWidget {
  final AccountCredentialsService? service;
  const ChangePasswordScreen({super.key, this.service});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  bool _loading = false;
  String? _error;
  String? _owner;
  StreamSubscription<AuthState>? _authSubscription;
  bool _sessionChanged = false;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    final captured = auth.currentSession;
    _owner = captured?.user.id;
    var first = true;
    _authSubscription = auth.onAuthStateChange.listen((state) {
      if (first && identical(state.session, captured)) {
        first = false;
        return;
      }
      first = false;
      if (state.session?.user.id != _owner ||
          const {
            AuthChangeEvent.signedIn,
            AuthChangeEvent.signedOut,
            AuthChangeEvent.passwordRecovery
          }.contains(state.event)) {
        _invalidateSession();
      }
    }, onError: (Object _) => _invalidateSession());
  }

  void _invalidateSession() {
    ++_operation;
    if (mounted) {
      setState(() {
        _sessionChanged = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _back() {
    if (_loading) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.settings);
    }
  }

  Future<void> _update(String password) async {
    if (_loading || _sessionChanged) return;
    final client = Supabase.instance.client;
    if (_owner == null || client.auth.currentUser?.id != _owner) {
      setState(() => _error = 'Бүртгэл солигдсон байна. Дахин нэвтэрнэ үү.');
      return;
    }
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final applied = await (widget.service ?? AccountCredentialsService())
          .updatePassword(password, ownerId: _owner!);
      if (!mounted || operation != _operation || _sessionChanged) return;
      if (!applied || client.auth.currentUser?.id != _owner) {
        setState(() => _error = 'Бүртгэл солигдсон байна. Дахин нэвтэрнэ үү.');
        return;
      }
      TextInput.finishAutofillContext(shouldSave: true);
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _loading = false);
      _back();
      messenger
          .showSnackBar(const SnackBar(content: Text('Нууц үг шинэчлэгдлээ.')));
    } on AccountCredentialsFailure catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() => _error =
            'Нууц үг шинэчилснийг баталж чадсангүй. Дахин оролдоно уу.');
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_loading,
        child: AuthFormScaffold(
          title: 'Нууц үг солих',
          description:
              'Таахад хэцүү, өөр үйлчилгээнд ашиглаагүй нууц үг сонгоно уу.',
          icon: Icons.lock_reset_rounded,
          onBack: _loading ? null : _back,
          child: _sessionChanged
              ? const AuthErrorBox(
                  'Нэвтрэх төлөв өөрчлөгдсөн эсвэл баталгаажуулж чадсангүй. Энэ дэлгэцийг хааж, өөрийн бүртгэлийн тохиргооноос дахин нээнэ үү.')
              : PasswordForm(busy: _loading, error: _error, onSubmit: _update),
        ),
      );
}
