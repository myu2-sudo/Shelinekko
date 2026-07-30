import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart'; 
import '../models/card_model.dart';
import '../models/binder_model.dart';

/// アップロード結果を保持するクラス
class UploadImageResult {
  final String originalUrl;
  final String thumbnailUrl;

  UploadImageResult({required this.originalUrl, required this.thumbnailUrl});
}

/// メタデータ保持構造体
class _ImageMetadata {
  final String ext;
  final String mime;
  final CompressFormat format;

  _ImageMetadata({required this.ext, required this.mime, required this.format});
}

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const bool useFixedUidForDebug = false; 
  static const String debugUid = 'debug_user_codespace';

  User? get currentUser {
    if (useFixedUidForDebug) {
      return _DummyUser(); 
    }
    return _auth.currentUser;
  }

  /// 予測サムネイルURL生成（Firebase Storageの命名規則 `_thumb.ext` に基づく）
  String predictThumbnailUrl(String originalUrl) {
    if (originalUrl.isEmpty || !originalUrl.contains('users%2F')) return originalUrl;
    
    // Firebase StorageのURLパターン（?alt=media 等のパラメータ前で差し替え）
    if (originalUrl.contains('.jpg?')) {
      return originalUrl.replaceFirst('.jpg?', '_thumb.jpg?');
    } else if (originalUrl.contains('.jpeg?')) {
      return originalUrl.replaceFirst('.jpeg?', '_thumb.jpeg?');
    } else if (originalUrl.contains('.png?')) {
      return originalUrl.replaceFirst('.png?', '_thumb.png?');
    }
    return originalUrl;
  }

  // 匿名サインイン
  Future<UserCredential?> signInAnonymously() async {
    if (useFixedUidForDebug) {
      debugPrint("【⚠️デバッグモード】固定UID（$debugUid）を使用するため、Firebase認証をスキップします。");
      return null; 
    }
    try {
      final credential = await _auth.signInAnonymously();
      return credential;
    } catch (e) {
      debugPrint("【エラー】匿名サインインに失敗しました: $e");
      rethrow;
    }
  }

  // ユーザーデータのロード
  Future<DocumentSnapshot<Map<String, dynamic>>> loadUserData(String uid) {
    return _firestore.collection('users').doc(uid).get();
  }

  // サブコレクションのカードデータも自動結合して読み込むメソッド
  Future<Map<String, dynamic>?> loadFullUserData(String uid) async {
    if (uid.isEmpty) return null;

    try {
      final userSnap = await _firestore.collection('users').doc(uid).get();
      if (!userSnap.exists) return null;

      final userData = userSnap.data();
      if (userData == null) return null;

      final cardsSnap = await _firestore.collection('users').doc(uid).collection('cards').get();
      final List<Map<String, dynamic>> cardsList = cardsSnap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      userData['cards'] = jsonEncode(cardsList);
      return userData;
    } catch (e) {
      debugPrint("【エラー】Firestoreデータ読み込みエラー: $e");
      rethrow;
    }
  }

  // 500件制限を回避するため、チャンクに分けてコミットするロジック（上限バリデーション＆同一ID集約追加）
  Future<void> saveUserData({
    required String uid,
    required List<BinderModel> binders,
    required Map<String, List<String>> refills,
    required List<CardModel> cards,
    required bool isPremiumUser,
  }) async {
    if (uid.isEmpty) {
      debugPrint("【エラー】UIDが空のため、データの保存をスキップしました。");
      return;
    }

    // ✨ 同一IDのカードを1つに集約（count / deletedCountの合算）して、ゴミ箱内でのバラつきを防止
    final groupedCards = CardModel.groupById(cards);

    // 【追加ガード】プレミアム上限3,000種類（無料50種類）チェック
    final int maxLimit = isPremiumUser ? 3000 : 50;
    if (groupedCards.length > maxLimit) {
      throw Exception("カードの所持上限（$maxLimit種類）を超えているため保存できません。（現在の指定種類数: ${groupedCards.length}）");
    }
    
    try {
      final userDocRef = _firestore.collection('users').doc(uid);
      await userDocRef.set({
        'userId': uid,
        'binders': jsonEncode(binders.map((b) => b.toMap()).toList()),
        'refills': jsonEncode(refills),
        'isPremiumUser': isPremiumUser,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final cardsCollectionRef = userDocRef.collection('cards');
      final currentCardsSnap = await cardsCollectionRef.get();
      final currentCardIds = currentCardsSnap.docs.map((doc) => doc.id).toSet();
      final newCardIds = groupedCards.map((c) => c.id).where((id) => id.isNotEmpty).toSet();

      final List<Future<void> Function(WriteBatch)> operations = [];

      final idsToDelete = currentCardIds.difference(newCardIds);
      for (var id in idsToDelete) {
        operations.add((batch) async => batch.delete(cardsCollectionRef.doc(id)));
      }

      for (var card in groupedCards) {
        final cardId = card.id.isNotEmpty ? card.id : cardsCollectionRef.doc().id;
        final cardDocRef = cardsCollectionRef.doc(cardId);

        var cardToSave = card;
        final cardData = cardToSave.toMap();
        cardData['id'] = cardId;

        operations.add((batch) async => batch.set(cardDocRef, cardData));
      }

      const chunkSize = 400; 
      for (var i = 0; i < operations.length; i += chunkSize) {
        final chunk = operations.sublist(
          i, 
          i + chunkSize > operations.length ? operations.length : i + chunkSize
        );
        
        final batch = _firestore.batch();
        for (final op in chunk) {
          await op(batch);
        }
        await batch.commit();
      }

      debugPrint("【システム】Firestoreへのデータ保存に成功しました(総操作数: ${operations.length})。UID: $uid");
    } catch (e) {
      debugPrint("【エラー】Firebase保存エラー: $e");
      rethrow; 
    }
  }

  // バインダーとリフィル情報のみを部分保存する軽量メソッド
  Future<void> saveBindersAndRefills({
    required String uid,
    required List<BinderModel> binders,
    required Map<String, List<String>> refills,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).set({
        'binders': jsonEncode(binders.map((b) => b.toMap()).toList()),
        'refills': jsonEncode(refills),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("【エラー】バインダー情報の保存に失敗しました: $e");
      rethrow;
    }
  }

  // リフィルの変更結果を同期するメソッド
  Future<void> saveRefills({
    required String uid,
    required Map<String, List<String>> refills,
  }) async {
    if (uid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).set({
        'refills': jsonEncode(refills),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  // バインダー名の重複チェック
  Future<bool> checkBinderNameDuplicate(String uid, String binderName, {String? currentBinderId}) async {
    if (uid.isEmpty) return false;
    try {
      final userSnap = await _firestore.collection('users').doc(uid).get();
      if (!userSnap.exists) return false;

      final userData = userSnap.data();
      if (userData == null || userData['binders'] == null) return false;

      final List<dynamic> bindersList = jsonDecode(userData['binders']);
      
      return bindersList.any((b) {
        final name = b['name'] ?? b['title'] ?? '';
        final id = b['id'] ?? '';
        
        if (currentBinderId != null && id == currentBinderId) return false;
        return name == binderName;
      });
    } catch (e) {
      return false; 
    }
  }

  // カードの総数を取得するメソッド
  Future<int> getTotalCardCount(String uid) async {
    if (uid.isEmpty) return 0;
    try {
      final countQuery = await _firestore.collection('users').doc(uid).collection('cards').count().get();
      return countQuery.count ?? 0;
    } catch (e) {
      try {
        final snap = await _firestore.collection('users').doc(uid).collection('cards').get();
        return snap.docs.length;
      } catch (_) {
        return 0;
      }
    }
  }

  // プレミアムプランの購入状態を確認（取得）
  Future<bool> checkPremiumStatus(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['isPremiumUser'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// プレミアム会員フラグを明示的に保存・更新する関数
  Future<void> updatePremiumStatus(String uid, bool isPremium) async {
    if (uid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).set({
        'isPremiumUser': isPremium,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("【システム】プレミアムステータスを更新しました（isPremiumUser: $isPremium）");
    } catch (e) {
      debugPrint("【エラー】プレミアムステータスの更新に失敗しました: $e");
      rethrow;
    }
  }

  // テスト用の疑似購入処理
  Future<void> purchasePremiumMock(String uid) async {
    if (uid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).set({
        'isPremiumUser': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// カードを1枚追加する関数（プレミアム3,000枚 / 無料50枚）
  Future<void> addCard(String uid, CardModel card) async {
    if (uid.isEmpty) return;

    try {
      // 1. 現在のプラン状態を確認
      final isPremium = await checkPremiumStatus(uid);
      final int maxLimit = isPremium ? 3000 : 50;

      // 2. 現在のカード総数を取得
      final int currentCount = await getTotalCardCount(uid);

      // 3. 上限チェックのバリデーション
      if (currentCount >= maxLimit) {
        throw Exception("カードの所持上限（$maxLimit枚）に達しているため、これ以上追加できません。");
      }

      // 4. カードをFirestoreのサブコレクションに追加
      final cardsCollectionRef = _firestore.collection('users').doc(uid).collection('cards');
      
      // IDが未発行なら新規発行
      final String cardId = card.id.isNotEmpty ? card.id : cardsCollectionRef.doc().id;
      
      final cardData = card.toMap();
      cardData['id'] = cardId;

      await cardsCollectionRef.doc(cardId).set(cardData, SetOptions(merge: true));
      debugPrint("【システム】カードを追加しました。ID: $cardId (現在の総数: ${currentCount + 1}/$maxLimit)");
    } catch (e) {
      debugPrint("【エラー】カードの追加バリデーション、または保存中にエラーが発生しました: $e");
      rethrow;
    }
  }

  /// フィードバック・お問い合わせの送信（メールアドレスは任意）
  Future<void> sendFeedback({
    required String uid,
    required String title,
    required String content,
    required String platform,
    String? email, // 👈 任意（オプショナル）の返信先メールアドレス
  }) async {
    final Map<String, dynamic> data = {
      'userId': uid,
      'title': title,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'device': platform,
    };

    // メールアドレスが入力されている場合のみ追加保存
    if (email != null && email.trim().isNotEmpty) {
      data['email'] = email.trim();
    }

    await _firestore.collection('feedbacks').add(data);
  }

  /// お問い合わせ送信専用メソッド（必要に応じて利用）
  Future<void> sendInquiry({
    required String uid,
    required String message,
    required String platform,
    String? email, // 👈 任意（オプショナル）の返信先メールアドレス
  }) async {
    final Map<String, dynamic> data = {
      'userId': uid,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'device': platform,
    };

    if (email != null && email.trim().isNotEmpty) {
      data['email'] = email.trim();
    }

    await _firestore.collection('inquiries').add(data);
  }

  _ImageMetadata _getImageMetadata(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) {
      return _ImageMetadata(ext: 'png', mime: 'image/png', format: CompressFormat.png);
    } else if (lowerPath.endsWith('.jpeg')) {
      return _ImageMetadata(ext: 'jpeg', mime: 'image/jpeg', format: CompressFormat.jpeg);
    }
    return _ImageMetadata(ext: 'jpg', mime: 'image/jpeg', format: CompressFormat.jpeg);
  }

  // オリジナル用画像圧縮（目標：約250〜300KB）
  Future<XFile> _compressOriginal(XFile file, CompressFormat format, String ext) async {
    if (kIsWeb) return file;
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/orig_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        minWidth: 1080,
        minHeight: 1440,
        quality: 75, 
        format: format,
      );
      return compressed != null ? XFile(compressed.path) : file;
    } catch (e) {
      return file;
    }
  }

  // サムネイル専用画像圧縮（目標：約20〜30KB）
  Future<XFile> _compressThumbnail(XFile file, CompressFormat format, String ext) async {
    if (kIsWeb) return file;
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        minWidth: 320, 
        minHeight: 420,
        quality: 50, 
        format: format,
      );
      return compressed != null ? XFile(compressed.path) : file;
    } catch (e) {
      return file;
    }
  }

  // 1つのファイルをStorageにアップロードしてURLを返す単体関数
  Future<String?> _uploadSingleFile(XFile file, String storagePath, String mime) async {
    try {
      final storageRef = _storage.ref().child(storagePath);
      final bytes = await file.readAsBytes();
      final uploadTask = storageRef.putData(bytes, SettableMetadata(contentType: mime));
      final snapshot = await uploadTask;
      if (snapshot.state == TaskState.success) {
        return await snapshot.ref.getDownloadURL();
      }
    } catch (e) {
      debugPrint("【エラー】ファイルアップロードエラー ($storagePath): $e");
    }
    return null;
  }

  // カード画像アップロード（オリジナルと20〜30KBサムネイルを同時生成）
  Future<UploadImageResult?> uploadCardImage(XFile originalFile, String cardId) async {
    final uid = currentUser?.uid ?? 'unknown_user';
    final String safeCardId = cardId.isNotEmpty 
        ? cardId 
        : 'card_${DateTime.now().millisecondsSinceEpoch}';

    final metadata = _getImageMetadata(originalFile.path);

    try {
      final origFile = await _compressOriginal(originalFile, metadata.format, metadata.ext);
      final thumbFile = await _compressThumbnail(originalFile, metadata.format, metadata.ext);

      final origPath = 'users/$uid/cards/$safeCardId.${metadata.ext}';
      final thumbPath = 'users/$uid/cards/${safeCardId}_thumb.${metadata.ext}';

      final results = await Future.wait([
        _uploadSingleFile(origFile, origPath, metadata.mime),
        _uploadSingleFile(thumbFile, thumbPath, metadata.mime),
      ]);

      final origUrl = results[0];
      final thumbUrl = results[1];

      if (origUrl != null) {
        final String finalThumbUrl = thumbUrl ?? origUrl;
        debugPrint("【完了】オリジナルURL (~300KB): $origUrl");
        debugPrint("【完了】サムネイルURL (20-30KB): $finalThumbUrl");
        return UploadImageResult(originalUrl: origUrl, thumbnailUrl: finalThumbUrl);
      }
    } catch (e) {
      debugPrint("【エラー】カード画像のアップロード処理に失敗: $e");
    }
    return null;
  }

  // バインダー表紙のアップロード
  Future<String?> uploadBinderCoverImage(XFile originalFile, String binderName) async {
    final uid = currentUser?.uid ?? 'unknown_user';
    final String safeBinderName = binderName.isNotEmpty 
        ? Uri.encodeComponent(binderName) 
        : 'binder';
    
    final metadata = _getImageMetadata(originalFile.path);

    final compressed = await _compressOriginal(originalFile, metadata.format, metadata.ext);
    final path = 'users/$uid/binders/${safeBinderName}_${DateTime.now().millisecondsSinceEpoch}.${metadata.ext}';
    
    return _uploadSingleFile(compressed, path, metadata.mime);
  }

  /// バインダーのカスタム表紙画像のURLをFirestoreに書き込んで保存する関数
  Future<void> updateBinderCoverImage({
    required String uid,
    required String binderId,
    required String coverImageUrl,
  }) async {
    if (uid.isEmpty) return;

    try {
      final userDocRef = _firestore.collection('users').doc(uid);
      final userSnap = await userDocRef.get();
      if (!userSnap.exists) return;

      final userData = userSnap.data();
      if (userData == null || userData['binders'] == null) return;

      // 1. JSON文字列からバインダーリストをデコード
      final List<dynamic> bindersList = jsonDecode(userData['binders']);
      
      // 2. 対象のバインダーを探して coverImageUrl を更新
      bool isUpdated = false;
      for (var b in bindersList) {
        if (b['id'] == binderId) {
          b['coverImageUrl'] = coverImageUrl;
          isUpdated = true;
          break;
        }
      }

      if (isUpdated) {
        // 3. 更新したリストを再度JSON化して上書き保存
        await userDocRef.set({
          'binders': jsonEncode(bindersList),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint("【システム】バインダー (ID: $binderId) のカスタム表紙URLをFirestoreに反映しました。");
      } else {
        debugPrint("【警告】指定されたバインダー (ID: $binderId) が見つからなかったため、URLの保存をスキップしました。");
      }
    } catch (e) {
      debugPrint("【エラー】バインダー表紙URLの保存に失敗しました: $e");
      rethrow;
    }
  }
}

class _DummyUser implements User {
  @override
  String get uid => FirebaseService.debugUid;
  @override
  bool get isAnonymous => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
