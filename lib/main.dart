import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb を使うために追加
import 'package:flutter/services.dart'; // PlatformExceptionのために追加
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:purchases_flutter/purchases_flutter.dart'; // 💡 RevenueCatを追加
import 'package:my_card_app/firebase_options.dart'; 
import 'services/firebase_service.dart'; 
import 'services/analytics_service.dart'; // ★ AnalyticsServiceをインポート
import 'screens/binder_screen.dart';
import 'screens/login_screen.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    debugPrint("【システム】Web環境用のAuth Persistence（LOCAL）を設定しました。");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
      // ★ 自動で画面遷移ログ（ScreenView）を取得するためのObserverを設定
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: AnalyticsService.analytics),
      ],
    );
  }
}

/// プレミアム状態を管理する InheritedWidget
class PremiumStatus extends InheritedWidget {
  final bool isPremium;

  const PremiumStatus({
    super.key,
    required this.isPremium,
    required super.child,
  });

  static PremiumStatus of(BuildContext context) {
    final PremiumStatus? result = context.dependOnInheritedWidgetOfExactType<PremiumStatus>();
    assert(result != null, 'No PremiumStatus found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(PremiumStatus oldWidget) => isPremium != oldWidget.isPremium;
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isAdInitialized = false;

  /// 💡 RevenueCatの初期化と状態取得を統合した新しいロジック
  Future<bool> _initializePurchaseAndGetStatus(String uid) async {
    try {
      // ★ Analyticsにログイン中のユーザーIDを自動登録（定着率分析の精度向上）
      await AnalyticsService.setUserId(uid);

      // 1. RevenueCatの設定（デバッグログ有効化）
      await Purchases.setLogLevel(LogLevel.debug);

      // 2. APIキーの設定（iOS環境を想定）
      // TODO: ここにRevenueCatで発行された公開APIキーを貼り付けてください
      PurchasesConfiguration configuration = PurchasesConfiguration("appl_kLXumCOCcHfjXEdWkpoGnUnmUKC");
      configuration.appUserID = uid; // FirebaseのUIDを紐付け
      
      await Purchases.configure(configuration);

      // 3. 購入情報の最新状態を取得（Appleサーバーとの同期）
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      
      // 4. "premium" という識別子の権限（Entitlement）があるか確認
      // ステップ2で設定したIdentifier（premium等）と一致させる必要があります
      bool isStorePremium = customerInfo.entitlements.active.containsKey("premium");

      // 5. Firebase DBの状態も一応確認（同期のため）
      bool isDbPremium = await _firebaseService.checkPremiumStatus(uid);

      // ストア決済またはDB、どちらかがプレミアムならプレミアムとして扱う
      return isStorePremium || isDbPremium;
    } on PlatformException catch (e) {
      debugPrint("【エラー】RevenueCatの初期化に失敗しました: $e");
      // エラー時はフォールバックとしてFirebase DBの結果のみを返す
      return await _firebaseService.checkPremiumStatus(uid);
    } catch (e) {
      return false;
    }
  }

  void _controlAdvertising(bool isPremium) {
    if (_isAdInitialized) return;
    _isAdInitialized = true;

    if (isPremium) {
      debugPrint("【広告】プレミアムユーザーを検出しました。広告をスキップします。");
      return;
    }

    debugPrint("【広告】一般ユーザーです。広告のロードを開始します。");
  }

  Widget _buildMainContent(String uid) {
    return FutureBuilder<bool>(
      // 💡 ここでFirebaseとRevenueCat両方の準備を待つ
      future: _initializePurchaseAndGetStatus(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("購入情報を同期中...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        final isPremium = snapshot.data ?? false;
        _controlAdvertising(isPremium);

        return PremiumStatus(
          isPremium: isPremium,
          child: const BinderScreen(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseService.useFixedUidForDebug) {
      return _buildMainContent(FirebaseService.debugUid);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          debugPrint("【システム】ログイン検出 UID: ${user.uid}");
          return _buildMainContent(user.uid);
        }

        debugPrint("【システム】未ログインです。");
        return const LoginScreen();
      },
    );
  }
}
