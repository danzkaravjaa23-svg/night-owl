import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';
import '../../../core/services/supabase_service.dart' show passwordJustReset;
import '../services/account_credentials_service.dart';
import '../widgets/password_form.dart';

/// Recovery changes only the captured account, then clears that local session.
class ResetPasswordScreen extends StatefulWidget {
  final AccountCredentialsService? service;
  const ResetPasswordScreen({super.key, this.service});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _loading = false;
  String? _error;
  String? _owner;
  StreamSubscription<AuthState>? _authSubscription;
  bool _sessionChanged = false;
  int _operation = 0;
  int _formVersion = 0;

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
      if (state.event == AuthChangeEvent.passwordRecovery &&
          state.session != null) {
        ++_operation;
        if (mounted) {
          setState(() {
            _owner = state.session!.user.id;
            _sessionChanged = false;
            _loading = false;
            _formVersion++;
            _error =
                'Шинэ сэргээх холбоос нээгдлээ. Шинэ нууц үгээ оруулна уу.';
          });
        }
        return;
      }
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

  Future<void> _leave({bool completed = false}) async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser != null && auth.currentUser?.id != _owner) return;
    // This SDK removes the captured local session synchronously before its
    // remote logout await. Bound that wait and never navigate over a new login.
    try {
      await auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (!mounted || auth.currentUser != null) return;
    if (completed) passwordJustReset = true;
    authGate.finishRecovery();
    if (mounted) context.go(AppRoutes.login);
  }

  Future<void> _back() async {
    if (_loading) return;
    if (_sessionChanged) {
      authGate.finishRecovery();
      context.go(AppRoutes.login);
      return;
    }
    setState(() => _loading = true);
    await _leave();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(String password) async {
    if (_loading || _sessionChanged) return;
    if (_owner == null ||
        Supabase.instance.client.auth.currentUser?.id != _owner) {
      setState(() => _error =
          'Холбоосын хугацаа дууссан эсвэл бүртгэл солигдсон байна. Нууц үг сэргээхийг дахин хүсээрэй.');
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
      if (!applied || Supabase.instance.client.auth.currentUser?.id != _owner) {
        setState(() => _error = 'Бүртгэл солигдсон байна. Дахин нэвтэрнэ үү.');
        return;
      }
      TextInput.finishAutofillContext(shouldSave: true);
      await _leave(completed: true);
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
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_loading) _back();
        },
        child: AuthFormScaffold(
          title: 'Шинэ нууц үг',
          description: 'Нууц үгээ шинэчилсний дараа дахин нэвтэрнэ.',
          icon: Icons.password_rounded,
          onBack: _loading ? null : _back,
          child: _sessionChanged
              ? const AuthErrorBox(
                  'Нэвтрэх төлөв өөрчлөгдсөн эсвэл баталгаажуулж чадсангүй. Нэвтрэх хэсэг рүү буцаж, зөв бүртгэлээрээ сэргээх холбоосоо дахин нээнэ үү.')
              : PasswordForm(
                  key: ValueKey(_formVersion),
                  busy: _loading,
                  error: _error,
                  onSubmit: _save),
        ),
      );
}
