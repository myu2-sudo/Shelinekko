import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/analytics_service.dart'; // ★ AnalyticsServiceをインポート

class PurchaseManager {
  // --- RevenueCatで発行された「Public API Key」をここに貼る ---
  static const _apiKey = "appl_kLXumCOCcHfjXEdWkpoGnUnmUKC";

  // --- RevenueCatで作った「Entitlement ID」を入れる ---
  static const _entitlementId = "premium";

  // 初期化処理（アプリ起動時に1回呼ぶ）
  static Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);

    // FirebaseのユーザーIDを取得してRevenueCatに紐付ける
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    PurchasesConfiguration configuration = PurchasesConfiguration(_apiKey);
    if (uid != null) {
      configuration.appUserID = uid; // これでFirebaseと同期される
    }
    
    await Purchases.configure(configuration);
  }

  // 商品セット（Offering）を取得する
  static Future<Offering?> fetchOffering() async {
    try {
      Offerings offerings = await Purchases.getOfferings();
      return offerings.current; // 「Default」に設定したOfferingが返る
    } catch (e) {
      return null;
    }
  }

  // 💡 追加：月額サブスクリプション用パッケージ（$rc_monthly）を直接取得するメソッド
  static Future<Package?> fetchMonthlyPackage() async {
    try {
      Offering? offering = await fetchOffering();
      if (offering != null) {
        // RevenueCatの管理画面で割り当てた「Monthly」パッケージを返す
        return offering.monthly;
      }
      return null;
    } catch (e) {
      print("Error fetching monthly package: $e");
      return null;
    }
  }

  // 💡 追加：課金ダイアログ/画面が開かれたときに呼び出すログ送信処理
  static Future<void> logPaywallImpression({required String sourceScreen}) async {
    await AnalyticsService.logPaywallImpression(sourceScreen: sourceScreen);
  }

  // 購入処理を実行する（★sourceScreenを追加して流入元画面を記録）
  static Future<bool> purchase(Package package, {required String sourceScreen}) async {
    try {
      CustomerInfo customerInfo = await Purchases.purchasePackage(package);
      
      // 購入後、権限（プレミアム）が有効になったか確認
      bool isSuccess = customerInfo.entitlements.active.containsKey(_entitlementId);

      if (isSuccess) {
        // ★ 課金成功時に Analytics イベントを送信！
        await AnalyticsService.logPurchase(
          productId: package.storeProduct.identifier,
          price: package.storeProduct.price,
          currency: package.storeProduct.currencyCode,
          sourceScreen: sourceScreen, // 例: 'mypage', 'binder_export'
        );
      }

      return isSuccess;
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        // キャンセル以外のエラーが発生した場合
        print("Error purchasing: $e");
      }
      return false;
    }
  }

  // 💡 追加：購入の復元（リストア）処理
  // ※Appleの審査ガイドラインで「サブスクリプション購入画面にはリストアボタンの設置」が必須となっています
  static Future<bool> restorePurchases() async {
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      return customerInfo.entitlements.active.containsKey(_entitlementId);
    } catch (e) {
      print("Error restoring purchases: $e");
      return false;
    }
  }

  // 課金済み（有効な月額サブスクリプションがあるか）どうかをチェックする
  static Future<bool> isPremium() async {
    try {
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.containsKey(_entitlementId);
    } catch (e) {
      return false;
    }
  }
}
