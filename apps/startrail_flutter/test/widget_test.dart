import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startrail/main.dart';
import 'package:startrail/src/vault_backend.dart';
import 'package:startrail/src/vault_paths.dart';

void main() {
  testWidgets('uses the formal Chinese brand and offline-first message', (
    tester,
  ) async {
    await tester.pumpWidget(
      StarTrailApp(backend: _FakeBackend(), paths: const _FakePaths()),
    );

    expect(find.text('拾星迹'), findsOneWidget);
    expect(find.text('默认离线保存，并在本机加密。'), findsOneWidget);
    expect(find.text('Flutter Demo'), findsNothing);
  });

  testWidgets('creates, clears password bytes, and locks', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      StarTrailApp(backend: backend, paths: const _FakePaths()),
    );

    await tester.tap(find.text('创建 Vault'));
    await tester.pumpAndSettle();
    expect(find.textContaining('密码不可恢复'), findsOneWidget);
    expect(find.text('C:/private/vault'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('vault-password')), 'secret');
    await tester.tap(find.text('创建并解锁'));
    await tester.pumpAndSettle();
    expect(find.text('Vault 已解锁'), findsOneWidget);
    expect(backend.lastPassword, everyElement(0));

    await tester.tap(find.text('锁定'));
    await tester.pumpAndSettle();
    expect(find.text('打开 Vault'), findsOneWidget);
    expect(backend.lockCount, 1);
  });

  testWidgets('shows only stable authentication failure', (tester) async {
    final backend = _FakeBackend(error: 'VAULT_AUTH_FAILED');
    await tester.pumpWidget(
      StarTrailApp(backend: backend, paths: const _FakePaths()),
    );

    await tester.tap(find.text('打开 Vault'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vault-password')), 'wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('VAULT_AUTH_FAILED'), findsOneWidget);
    expect(find.text('Vault 已解锁'), findsNothing);
    expect(backend.lastPassword, everyElement(0));
  });
}

final class _FakeBackend implements VaultBackend {
  _FakeBackend({this.error});

  final String? error;
  Int8List? lastPassword;
  int lockCount = 0;

  @override
  Future<String?> create(String path, Int8List passwordBytes) async {
    lastPassword = passwordBytes;
    return error;
  }

  @override
  Future<String?> unlock(String path, Int8List passwordBytes) async {
    lastPassword = passwordBytes;
    return error;
  }

  @override
  Future<void> lock() async {
    lockCount++;
  }
}

final class _FakePaths implements VaultPaths {
  const _FakePaths();

  @override
  Future<String?> chooseCreationPath() async => 'C:/chosen/vault';

  @override
  Future<String?> chooseExistingVault() async => 'C:/existing/vault';

  @override
  Future<String> defaultVaultPath() async => 'C:/private/vault';
}
