import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/services/supabase_service.dart'
    show pendingPasswordRecovery;

void main() {
  late StreamController<AuthState> events;
  late AuthGate gate;
  final session = Session(
      accessToken: 'fixture-only-token',
      tokenType: 'bearer',
      user: const User(
          id: 'fixture-owner',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-11-03T00:00:00Z'));

  setUp(() {
    pendingPasswordRecovery = true;
    events = StreamController<AuthState>.broadcast(sync: true);
    gate = AuthGate(authStream: events.stream);
  });
  tearDown(() async {
    gate.dispose();
    await events.close();
    pendingPasswordRecovery = false;
  });

  for (final event in [AuthChangeEvent.signedIn, AuthChangeEvent.signedOut]) {
    test('explicit $event ends recovery and clears the startup marker', () {
      var notifications = 0;
      gate.addListener(() => notifications++);
      events.add(AuthState(AuthChangeEvent.passwordRecovery, session));
      expect(gate.recovery, isTrue);
      events.add(AuthState(
          event, event == AuthChangeEvent.signedOut ? null : session));
      expect(gate.recovery, isFalse);
      expect(pendingPasswordRecovery, isFalse);
      expect(notifications, 2);
    });
  }

  test('initial session and token refresh preserve an active recovery', () {
    for (final event in [
      AuthChangeEvent.initialSession,
      AuthChangeEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated,
    ]) {
      events.add(AuthState(event, session));
      expect(gate.recovery, isTrue);
      expect(pendingPasswordRecovery, isTrue);
    }
  });

  test('finishing recovery cannot be revived from the startup marker', () {
    var notifications = 0;
    gate.addListener(() => notifications++);
    gate.finishRecovery();
    expect(gate.recovery, isFalse);
    expect(pendingPasswordRecovery, isFalse);
    expect(notifications, 1);
    final reopened = AuthGate(authStream: const Stream<AuthState>.empty());
    expect(reopened.recovery, isFalse);
    reopened.dispose();
    events.add(AuthState(AuthChangeEvent.passwordRecovery, session));
    expect(gate.recovery, isTrue,
        reason: 'A later, explicit recovery link must still work.');
  });

  test('auth stream errors do not escape or silently finish recovery', () {
    var notifications = 0;
    gate.addListener(() => notifications++);
    events.addError(
        StateError('synthetic refresh failure'), StackTrace.current);
    expect(gate.recovery, isTrue);
    expect(pendingPasswordRecovery, isTrue);
    expect(notifications, 0);
    events.add(const AuthState(AuthChangeEvent.signedOut, null));
    expect(gate.recovery, isFalse);
    expect(notifications, 1);
  });

  test('disposing a gate cancels its stream subscription', () async {
    final isolatedEvents = StreamController<AuthState>.broadcast(sync: true);
    final isolatedGate = AuthGate(authStream: isolatedEvents.stream);
    var notifications = 0;
    isolatedGate.addListener(() => notifications++);
    expect(isolatedEvents.hasListener, isTrue);
    isolatedGate.dispose();
    expect(isolatedEvents.hasListener, isFalse);
    isolatedEvents.add(AuthState(AuthChangeEvent.passwordRecovery, session));
    expect(notifications, 0);
    await isolatedEvents.close();
  });
}
