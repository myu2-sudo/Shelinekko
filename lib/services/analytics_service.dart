import 'package:firebase_analytics/firebase_analytics.dart';

/// Firebase Analyticsの計測ロジックをまとめたサービススクラス
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Analyticsインスタンスの取得（NavigatorObserver等で利用）
  static FirebaseAnalytics get analytics => _analytics;

  // ==========================================
  // 1. ユーザー属性・識別
  // ==========================================

  /// ログインユーザーのIDを設定（Firebase AuthやRevenueCatのAppUserIDを渡す）
  static Future<void> setUserId(String userId) async {
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      print('Analytics Error (setUserId): $e');
    }
  }

  /// ユーザープロパティを設定（例: 会員ステータスなど）
  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      print('Analytics Error (setUserProperty): $e');
    }
  }

  // ==========================================
  // 2. 画面ログ（定着率・滞在の追跡）
  // ==========================================

  /// 手動で画面表示ログを送信したい場合に呼び出し
  static Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      print('Analytics Error (logScreenView): $e');
    }
  }

  // ==========================================
  // 3. 課金・コンバージョン関連イベント
  // ==========================================

  /// 課金画面（ペイウォール）が表示された時に送信
  static Future<void> logPaywallImpression({
    required String sourceScreen,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'paywall_impression',
        parameters: {
          'source_screen': sourceScreen, // 例: 'mypage', 'binder_limit_dialog'
        },
      );
    } catch (e) {
      print('Analytics Error (logPaywallImpression): $e');
    }
  }

  /// 課金が成功した時に送信（標準のpurchaseイベント）
  static Future<void> logPurchase({
    required String productId,
    required double price,
    required String currency,
    required String sourceScreen,
  }) async {
    try {
      await _analytics.logPurchase(
        currency: currency,
        value: price,
        items: [
          AnalyticsEventItem(
            itemId: productId,
            price: price,
          ),
        ],
        parameters: {
          // ★どの画面を経由して課金に至ったかをログに残す
          'source_screen': sourceScreen,
        },
      );
    } catch (e) {
      print('Analytics Error (logPurchase): $e');
    }
  }

  // ==========================================
  // 4. カスタム機能利用イベント（定着率分析用）
  // ==========================================

  /// アプリ内の重要なアクション（カード追加、バインダー作成など）を追跡
  static Future<void> logCustomEvent({
    required String eventName,
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(
        name: eventName,
        parameters: parameters,
      );
    } catch (e) {
      print('Analytics Error (logCustomEvent): $e');
    }
  }
}
