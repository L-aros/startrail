import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'timeline_page.dart';
import 'vault_backend.dart';
import 'vault_paths.dart';

enum VaultView { welcome, create, unlock, unlocked }

class StarTrailApp extends StatefulWidget {
  const StarTrailApp({super.key, this.backend, this.paths});

  final VaultBackend? backend;
  final VaultPaths? paths;

  @override
  State<StarTrailApp> createState() => _StarTrailAppState();
}

class _StarTrailAppState extends State<StarTrailApp> {
  late final VaultBackend _backend = widget.backend ?? IsolateVaultBackend();
  late final VaultPaths _paths = widget.paths ?? PlatformVaultPaths();
  final _password = TextEditingController();
  var _view = VaultView.welcome;
  var _path = '';
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _backend.lock();
    super.dispose();
  }

  Future<void> _startCreate() async {
    final path = await _paths.defaultVaultPath();
    if (!mounted) return;
    setState(() {
      _path = path;
      _view = VaultView.create;
      _error = null;
    });
  }

  Future<void> _chooseCreatePath() async {
    final path = await _paths.chooseCreationPath();
    if (!mounted || path == null) return;
    setState(() => _path = path);
  }

  Future<void> _chooseVault() async {
    final path = await _paths.chooseExistingVault();
    if (!mounted || path == null) return;
    setState(() {
      _path = path;
      _view = VaultView.unlock;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty || _path.isEmpty) return;
    final encoded = utf8.encode(_password.text);
    _password.clear();
    final passwordBytes = Int8List.fromList(encoded);
    encoded.fillRange(0, encoded.length, 0);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final error = _view == VaultView.create
          ? await _backend.create(_path, passwordBytes)
          : await _backend.unlock(_path, passwordBytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error == null) {
          _view = VaultView.unlocked;
        } else {
          _error = error;
        }
      });
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _lock() async {
    await _backend.lock();
    if (!mounted) return;
    setState(() {
      _view = VaultView.welcome;
      _path = '';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拾星迹',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff465d91)),
        useMaterial3: true,
      ),
      home: _view == VaultView.unlocked
          ? TimelinePage(backend: _backend, onLock: _lock)
          : Scaffold(
              appBar: AppBar(title: const Text('拾星迹')),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: switch (_view) {
                      VaultView.welcome => _welcome(),
                      VaultView.create => _credentials(create: true),
                      VaultView.unlock => _credentials(create: false),
                      VaultView.unlocked => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _welcome() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '你的记录，只属于你',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text('默认离线保存，并在本机加密。', textAlign: TextAlign.center),
      const SizedBox(height: 32),
      FilledButton(onPressed: _startCreate, child: const Text('创建 Vault')),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _chooseVault, child: const Text('打开 Vault')),
    ],
  );

  Widget _credentials({required bool create}) => AutofillGroup(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          create ? '创建加密 Vault' : '解锁 Vault',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(_path, key: const Key('vault-path')),
        if (create) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _chooseCreatePath,
            child: const Text('选择其他位置'),
          ),
          const Text('密码不可恢复。请妥善保管；忘记密码将无法打开 Vault。'),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('vault-password'),
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          enableIMEPersonalizedLearning: false,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, key: const Key('vault-error')),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '处理中…' : (create ? '创建并解锁' : '解锁')),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _password.clear();
                  _view = VaultView.welcome;
                  _error = null;
                }),
          child: const Text('返回'),
        ),
      ],
    ),
  );
}
