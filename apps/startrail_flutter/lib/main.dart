import 'package:flutter/material.dart';

void main() => runApp(const StarTrailApp());

class StarTrailApp extends StatelessWidget {
  const StarTrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拾星迹',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff465d91)),
        useMaterial3: true,
      ),
      home: const VaultWelcomePage(),
    );
  }
}

class VaultWelcomePage extends StatelessWidget {
  const VaultWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拾星迹')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '你的记录，只属于你',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text('默认离线保存，并在本机加密。', textAlign: TextAlign.center),
                const SizedBox(height: 32),
                FilledButton(onPressed: null, child: const Text('创建 Vault')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: null, child: const Text('打开 Vault')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
