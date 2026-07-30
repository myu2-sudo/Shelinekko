import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 現在のログインユーザーを取得
  User? get currentUser => _auth.currentUser;

  // ログイン状態の変化を流すストリーム
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- 匿名（ゲスト）サインイン ---
  Future<UserCredential?> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      print('匿名サインインエラー: ${e.message}');
      rethrow;
    }
  }

  // --- メールアドレス新規登録 / 匿名からの引き継ぎ連携 ---
  Future<UserCredential?> signUpOrLinkWithEmail(String email, String password) async {
    final user = _auth.currentUser;
    final credential = EmailAuthProvider.credential(email: email, password: password);

    try {
      if (user != null && user.isAnonymous) {
        return await user.linkWithCredential(credential);
      } else {
        return await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      print('メール登録/連携エラー: ${e.message}');
      rethrow;
    }
  }

  // --- メールアドレス/パスワード ログイン ---
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      print('ログインエラー: ${e.message}');
      rethrow;
    }
  }

  // --- パスワード再設定メールの送信 ---
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      print('パスワード再設定メール送信エラー: ${e.message}');
      rethrow;
    }
  }

   // --- 💡 パスワード変更（現在のパスワードで再認証後に更新） ---
  Future<void> updatePasswordWithReauth({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'ユーザーが見つかりません。',
        );
      }

      // 1. 現在のメールアドレスとパスワードでクレデンシャルを作成
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      // 2. 再認証を実行（パスワードが合っているか検証）
      await user.reauthenticateWithCredential(credential);

      // 3. パスワードを更新
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      print('パスワード変更エラー: ${e.message}');
      rethrow;
    }
  }


  // --- 💡 アカウント削除（退会） ---
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.delete();
      }
    } on FirebaseAuthException catch (e) {
      print('アカウント削除エラー: ${e.message}');
      rethrow;
    }
  }

  // --- Appleでサインイン / 匿名からの引き継ぎ連携 ---
  Future<UserCredential?> signInOrLinkWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final user = _auth.currentUser;
      if (user != null && user.isAnonymous) {
        return await user.linkWithCredential(oauthCredential);
      } else {
        return await _auth.signInWithCredential(oauthCredential);
      }
    } on FirebaseAuthException catch (e) {
      print('Appleサインイン/連携エラー: $e');
      rethrow;
    } catch (e) {
      print('Appleサインインエラー: $e');
      rethrow;
    }
  }

  // --- ログアウト ---
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Nonce生成用ヘルパーメソッド
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = List<int>.generate(
      length,
      (_) => charset.codeUnitAt(
        DateTime.now().microsecondsSinceEpoch % charset.length,
      ),
    );
    return String.fromCharCodes(random);
  }
}
