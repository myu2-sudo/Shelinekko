import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import 'login_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // ★ 画面ログ（マイページが開かれたこと）を送信
    AnalyticsService.logScreenView('mypage_screen');
  }

  // 💡 パスワード変更ダイアログ
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('パスワード変更', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('現在のパスワードと新しいパスワードを入力してください。', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '現在のパスワード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                // ★ 「現在のパスワードを忘れた方はこちら」リンクを追加
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final email = FirebaseAuth.instance.currentUser?.email;
                      if (email == null || email.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('登録メールアドレスが確認できませんでした。')),
                        );
                        return;
                      }

                      try {
                        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                        if (mounted) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$email 宛にパスワード再設定メールを送信しました。'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('再設定メールの送信に失敗しました。時間をおいて再度お試しください。'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      '現在のパスワードを忘れた方はこちら',
                      style: TextStyle(fontSize: 12, color: Colors.pinkAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新しいパスワード (6文字以上)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final currentPassword = currentPasswordController.text.trim();
                final newPassword = newPasswordController.text.trim();

                if (currentPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('現在のパスワードを入力してください')),
                  );
                  return;
                }

                if (newPassword.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('新しいパスワードは6文字以上で入力してください'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogCtx);
                setState(() => _isLoading = true);

                try {
                  await _authService.updatePasswordWithReauth(
                    currentPassword: currentPassword,
                    newPassword: newPassword,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('パスワードを変更しました！'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  if (mounted) {
                    String message = 'パスワードの変更に失敗しました';
                    if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                      message = '現在のパスワードが正しくありません。';
                    } else if (e.code == 'weak-password') {
                      message = '新しいパスワードは6文字以上で設定してください。';
                    } else {
                      message = 'エラー: ${e.message}';
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text('変更'),
            ),
          ],
        );
      },
    );
  }

  // 退会（アカウント削除）確認ダイアログ
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('会員退会', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
            ],
          ),
          content: const Text(
            '本当に退会しますか？\n\n※退会すると、保存されているすべてのバインダーやカードデータが永久に削除され、復元できなくなります。',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                setState(() => _isLoading = true);

                try {
                  await _authService.deleteAccount();
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('退会処理が完了しました。ご利用ありがとうございました。')),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  if (mounted) {
                    String message = '退会処理に失敗しました';
                    if (e.code == 'requires-recent-login') {
                      message = 'セキュリティ保護のため、一度ログアウトして再ログインしてから退会をお試しください。';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text('退会する'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text('マイページ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
                final isAnonymous = user?.isAnonymous ?? false;
                final email = user?.email;
                final uid = user?.uid ?? '未取得';

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------------------------------------------
                      // ① アカウント情報カード（メールアドレス / UID）
                      // ---------------------------------------------------
                      const Text(
                        'アカウント情報',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),

                      if (isAnonymous) ...[
                        Card(
                          color: Colors.pink[50],
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.pink[200]!),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.pinkAccent),
                                    SizedBox(width: 8),
                                    Text(
                                      'お試し（ゲスト）利用中',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '作成したカードデータを保持したまま会員登録が可能です。',
                                  style: TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.pinkAccent,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const LoginScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('会員登録する（データを引き継ぐ）'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.email_outlined, color: Colors.pinkAccent),
                                title: const Text('登録メールアドレス', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                subtitle: Text(
                                  (email != null && email.isNotEmpty) ? email : 'Apple ID連携済み',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.badge_outlined, color: Colors.pinkAccent),
                                title: const Text('ユーザーID (UID)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                subtitle: Text(
                                  uid,
                                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Colors.black87),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                                  tooltip: 'UIDをコピー',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: uid));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('UIDをクリップボードにコピーしました！')),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ---------------------------------------------------
                      // ② セキュリティ（パスワード変更）
                      // ---------------------------------------------------
                      if (!isAnonymous && email != null && email.isNotEmpty) ...[
                        const Text(
                          'セキュリティ',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const Icon(Icons.lock_reset, color: Colors.black87),
                            title: const Text('パスワード変更', style: TextStyle(fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _showChangePasswordDialog,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ---------------------------------------------------
                      // ③ アカウント操作（ログアウト / 会員退会）
                      // ---------------------------------------------------
                      const Text(
                        'アカウント操作',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.logout, color: Colors.black87),
                              title: const Text('ログアウト', style: TextStyle(fontWeight: FontWeight.bold)),
                              onTap: () async {
                                await _authService.signOut();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                              title: const Text(
                                '会員退会',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                              subtitle: const Text(
                                'データがすべて削除されます',
                                style: TextStyle(fontSize: 11, color: Colors.redAccent),
                              ),
                              onTap: _showDeleteAccountDialog,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
