import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  
  // デフォルトを「新規登録モード」に設定（はじめてアプリを使う人向け）
  bool _isSignUpMode = true; 

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 現在匿名ログイン中かどうかを確認
  bool get _isAnonymous => _authService.currentUser?.isAnonymous ?? false;

  // メールアドレスでの処理（モードに応じて新規登録・ログイン・データ引き継ぎを実行）
  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メールアドレスとパスワードを入力してください')),
      );
      return;
    }

    if (_isSignUpMode && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('パスワードは6文字以上で入力してください'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isSignUpMode || _isAnonymous) {
        // 新規登録 / ゲストデータ引き継ぎ連携
        await _authService.signUpOrLinkWithEmail(email, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isAnonymous ? 'データを引き継いで会員登録しました！✨' : '会員登録が完了しました！🎉'),
            ),
          );
        }
      } else {
        // 既存アカウントへのログイン
        await _authService.signInWithEmail(email, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ログインに成功しました！')),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = 'エラーが発生しました';
        // 💡 重複登録エラーのメッセージを修正
        if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
          errorMessage = '既に登録されているメールアドレスです';
        } else if (e.code == 'weak-password') {
          errorMessage = 'パスワードは6文字以上で設定してください。';
        } else if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
          errorMessage = 'メールアドレスまたはパスワードが正しくありません。';
        } else {
          errorMessage = 'エラー: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // パスワード再設定ダイアログの表示
  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('パスワードの再設定', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ご登録のメールアドレスを入力してください。\nパスワード再設定用リンクをお送りします。',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailController,
                decoration: const InputDecoration(
                  labelText: 'メールアドレス',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
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
                final email = resetEmailController.text.trim();
                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('メールアドレスを入力してください')),
                  );
                  return;
                }
                Navigator.pop(dialogCtx);
                setState(() => _isLoading = true);
                try {
                  await _authService.sendPasswordResetEmail(email);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('再設定メールを送信しました。メールをご確認ください ✉️'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  if (mounted) {
                    String message = 'エラーが発生しました';
                    if (e.code == 'user-not-found') {
                      message = '登録されていないメールアドレスです';
                    } else if (e.code == 'invalid-email') {
                      message = 'メールアドレスの形式が正しくありません。';
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
              child: const Text('送信'),
            ),
          ],
        );
      },
    );
  }

  // Appleサインイン処理（匿名時は自動でデータ引き継ぎ）
  Future<void> _handleAppleAuth() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInOrLinkWithApple();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isAnonymous ? 'データを引き継いでAppleで登録しました！' : 'Appleでログインしました！')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = 'エラーが発生しました';
        if (e.code == 'credential-already-in-use') {
          errorMessage = 'このApple IDは既に別のアカウントに連携されています。';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 匿名（お試しゲスト）利用
  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInAnonymously();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('お試し利用を開始します（後から会員登録できます）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: Text(_isAnonymous
            ? '会員登録（データ引き継ぎ）'
            : (_isSignUpMode ? '新規会員登録' : 'ログイン')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.style, size: 80, color: Colors.pinkAccent),
                    const SizedBox(height: 16),
                    Text(
                      _isAnonymous
                          ? '作成したデータはそのまま引き継がれます ✨'
                          : (_isSignUpMode ? 'コレクションをはじめよう！' : 'おかえりなさい！'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 28),

                    // メールアドレス入力
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    // パスワード入力
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'パスワード',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        helperText: _isSignUpMode ? '※パスワードは6文字以上で入力してください' : null,
                        helperStyle: const TextStyle(color: Colors.grey),
                      ),
                      obscureText: true,
                    ),

                    // 「パスワードをお忘れの方」リンク（ログインモード時のみ表示）
                    if (!_isSignUpMode && !_isAnonymous) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: const Text(
                            'パスワードをお忘れの方はこちら',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                    ],

                    // メインアクションボタン
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pinkAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _handleEmailAuth,
                        child: Text(
                          _isAnonymous
                              ? 'データを引き継いで会員登録'
                              : (_isSignUpMode ? 'メールで会員登録' : 'メールでログイン'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // サブアクションボタン（「会員登録」↔「ログイン」のモード切替）※匿名連携時は非表示
                    if (!_isAnonymous)
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[400]!),
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _isSignUpMode = !_isSignUpMode;
                            });
                          },
                          child: Text(
                            _isSignUpMode
                                ? 'すでにアカウントをお持ちの方（ログイン）'
                                : 'アカウントをお持ちでない方（新規会員登録）',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text('または', style: TextStyle(color: Colors.grey)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Appleでサインインボタン
                    SignInWithAppleButton(
                      onPressed: _handleAppleAuth,
                      text: _isAnonymous ? 'Appleで連携して登録' : 'Appleでサインイン',
                    ),

                    // お試し（ゲスト利用）※完全未ログイン時のみ下部に表示
                    if (!_isAnonymous) ...[
                      const SizedBox(height: 28),
                      TextButton(
                        onPressed: _handleGuestLogin,
                        child: const Text(
                          '登録せずに試す（お試しゲスト利用）',
                          style: TextStyle(
                            color: Colors.grey,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
