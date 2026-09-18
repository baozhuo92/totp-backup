import 'package:flutter/material.dart';

import '../../services/lock_service.dart';
import 'account_list_page.dart';

/// 本地锁解锁页：主口令输入 + 指纹解锁（启用时）。
/// 主口令校验基于 PBKDF2 指纹，错误提示不区分原因。
class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _passwordController = TextEditingController();
  bool _unlocking = false;
  bool _showFingerprint = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final available = await LockService.instance.isBiometricAvailable();
    if (!mounted) return;
    setState(() => _showFingerprint = available);
  }

  /// 主口令解锁
  Future<void> _unlockByPassword() async {
    if (_unlocking) return;
    setState(() {
      _unlocking = true;
      _error = null;
    });
    final ok = await LockService.instance
        .unlockWithPassword(_passwordController.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AccountListPage()),
      );
    } else {
      setState(() {
        _unlocking = false;
        _error = '主口令错误';
      });
    }
  }

  /// 指纹解锁（系统弹指纹验证）
  Future<void> _unlockByBiometric() async {
    if (_unlocking) return;
    setState(() {
      _unlocking = true;
      _error = null;
    });
    final ok = await LockService.instance.unlockWithBiometric();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AccountListPage()),
      );
    } else {
      setState(() {
        _unlocking = false;
        _error = '指纹验证未通过，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                '输入主口令解锁',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                enabled: !_unlocking,
                decoration: InputDecoration(
                  labelText: '主口令',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
                onSubmitted: (_) => _unlockByPassword(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _unlocking ? null : _unlockByPassword,
                child: _unlocking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('解锁'),
              ),
              if (_showFingerprint) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _unlocking ? null : _unlockByBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('指纹解锁'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
