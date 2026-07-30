import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../models/card_model.dart';
import '../models/binder_model.dart';
import '../services/firebase_service.dart';
import '../services/analytics_service.dart';
import '../purchase_manager.dart';
import '../widgets/card_dialogs.dart';
import 'export_screen.dart';
import '../screens/mypage_screen.dart';

class BinderScreen extends StatefulWidget {
  const BinderScreen({super.key});
  @override
  State<BinderScreen> createState() => _BinderScreenState();
}

class _BinderScreenState extends State<BinderScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final ImagePicker _picker = ImagePicker();
  bool _isLoadingUser = true;

  String? _openedBinderName;
  String? _openedRefillName; 
  bool _isTrashMode = false; 
  bool _showAllDuplicates = false; 
  bool _isPageMode = true; 
  double _cardsPerPage = 9.0; 
  bool _showRefillCounts = true;
  String _searchQuery = '';
  String? _selectedTagFilter;
  String _sortOrder = 'custom';
  bool _isSelectMode = false;
  final Set<String> _selectedCardUniqueKeys = {};
  Map<String, dynamic>? _lastRegisteredData;

  final int _maxFreeCardCount = 50; 
  final int _maxPremiumCardCount = 3000; // カード上限枚数を3,000枚に設定
  bool _isPremiumUser = false;     

  final List<String> _presetColors = [
    '#FF5252',
    '#FFA500',
    '#fffa73',
    '#8fda94',
    '#98d5fb',
    '#2e6be7',
    '#9494f9',
    '#f7a2d9',
    '#795548',
    '#9E9E9E',
    '#212121',
    '#fbfae6',
  ];

  final List<String> _presetCovers = [
    'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=400', 
    'https://images.unsplash.com/photo-1557683316-973673baf926?w=400', 
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400', 
    'https://images.unsplash.com/photo-1518531933037-91b2f5f229cc?w=400', 
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=400', 
  ];

  final List<BinderModel> _defaultBinders = [
    BinderModel(name: 'マイコレクション', coverUrl: 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=400'),
  ];

  final Map<String, List<String>> _defaultRefills = {
    'マイコレクション': ['ノーマル'],
  };

  List<BinderModel> _binders = [];
  Map<String, List<String>> _refills = {};
  List<CardModel> _cardsData = [];

  List<CardModel> get _activeCards => _cardsData.where((c) => c.isDeleted != true).toList();
  List<CardModel> get _trashedCards => _cardsData.where((c) => c.isDeleted == true).toList();
  
  int get _totalActiveCardCount => _cardsData.fold(0, (sum, item) => sum + item.count);

  String _generateUniqueId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
  }

  String _getIdFromUniqueKey(String key) {
    final lastUnderscore = key.lastIndexOf('_');
    return lastUnderscore != -1 ? key.substring(0, lastUnderscore) : key;
  }

  /// プレミアム状態に応じてバインダーの表紙URLを返すヘルパー
  String _getBinderCoverUrl(BinderModel binder) {
    final bool isPreset = _presetColors.contains(binder.coverUrl) || _presetCovers.contains(binder.coverUrl);
    
    if (!_isPremiumUser && !isPreset) {
      return _presetCovers[0]; 
    }
    return binder.coverUrl;
  }

  List<CardModel> _getCurrentDisplayPool() {
    if (_isTrashMode) return _trashedCards;
    List<CardModel> pool;
    if (_openedRefillName == '✨ すべてのカード') {
      pool = _activeCards.where((c) => c.refill.startsWith("${_openedBinderName ?? ''}_")).toList();
    } else if (_openedRefillName == '❤️ お気に入り') {
      pool = _activeCards.where((c) => c.refill.startsWith("${_openedBinderName ?? ''}_") && c.isFavorite == true).toList();
    } else {
      final compositeKey = "${_openedBinderName ?? ''}_$_openedRefillName";
      pool = _activeCards.where((c) => c.refill == compositeKey).toList();
    }
    if (_searchQuery.isNotEmpty) {
      pool = pool.where((c) => 
        c.memo.toLowerCase().contains(_searchQuery.toLowerCase()) || 
        (c.date != null && c.date!.toLowerCase().contains(_searchQuery.toLowerCase()))
      ).toList();
    }
    if (_selectedTagFilter != null) {
      pool = pool.where((c) => c.tags.contains(_selectedTagFilter)).toList();
    }
    List<CardModel> sortedPool = List<CardModel>.from(pool);
    if (_sortOrder == 'newest') {
      sortedPool.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else if (_sortOrder == 'oldest') {
      sortedPool.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    return sortedPool;
  }

  List<CardModel> _getFlattenedDisplayCards() {
    final pool = _getCurrentDisplayPool();
    List<CardModel> flattened = [];
    for (var card in pool) {
      if (_showAllDuplicates) {
        for (int i = 0; i < card.count; i++) {
          final cloned = card.copyWith(displayIndex: i, uniqueKey: "${card.id}_$i");
          flattened.add(cloned);
        }
      } else {
        final cloned = card.copyWith(displayIndex: 0, uniqueKey: "${card.id}_0");
        flattened.add(cloned);
      }
    }
    return flattened;
  }

  @override
  void initState() {
    super.initState();
    // ★ 画面表示ログをAnalyticsへ送信
    AnalyticsService.logScreenView('binder_screen');
    _signInAnonymouslyAndLoadData();
  }

  Future<void> _signInAnonymouslyAndLoadData() async {
    try {
      if (_firebaseService.currentUser == null || _firebaseService.currentUser!.uid.isEmpty) {
        await _firebaseService.signInAnonymously();
      }
      debugPrint("ログイン中のユーザーUID: ${_firebaseService.currentUser?.uid}");
      await _loadUserDataFromFirestore();
    } catch (e) {
      debugPrint("【画面エラー】ログインまたはデータ読み込みに失敗しました: $e");
      if (!mounted) return;
      setState(() { _isLoadingUser = false; });
    }
  }

  Future<void> _loadUserDataFromFirestore() async {
    final user = _firebaseService.currentUser;
    if (user == null) {
      setState(() { _isLoadingUser = false; });
      return;
    }
    try {
      _firebaseService.getTotalCardCount(user.uid).then((count) {
        debugPrint("【システム】起動時にFirestoreから検出した総カードドキュメント数: $count");
      });

      final data = await _firebaseService.loadFullUserData(user.uid);
      
      // RevenueCatの課金状態も取得
      bool isRevenueCatPremium = await PurchaseManager.isPremium();

      if (data != null) {
        List<BinderModel> loadedBinders = [];
        if (data['binders'] != null) {
          final List<dynamic> decoded = jsonDecode(data['binders']);
          loadedBinders = decoded.map<BinderModel>((e) => BinderModel.fromMap(Map<String, dynamic>.from(e))).toList();
        } else {
          loadedBinders = List<BinderModel>.from(_defaultBinders);
        }
        List<CardModel> loadedCards = [];
        if (data['cards'] != null) {
          final List<dynamic> decoded = jsonDecode(data['cards']);
          loadedCards = decoded.map((e) => CardModel.fromMap(Map<String, dynamic>.from(e))).toList();
        }
        final now = DateTime.now();
        loadedCards.removeWhere((card) {
          if (card.isDeleted == true && card.deletedAt != null) {
            final deletedDate = DateTime.parse(card.deletedAt!);
            return now.difference(deletedDate).inDays >= 30;
          }
          return false;
        });

        for (int i = 0; i < loadedCards.length; i++) {
          if (!loadedCards[i].refill.contains('_')) {
            final defaultBinderName = loadedBinders.isNotEmpty ? loadedBinders[0].name : 'マイコレクション';
            loadedCards[i] = loadedCards[i].copyWith(refill: "${defaultBinderName}_${loadedCards[i].refill}");
          }
        }

        Map<String, List<String>> loadedRefills = {};
        if (data['refills'] != null) {
          final Map<String, dynamic> decoded = jsonDecode(data['refills']);
          decoded.forEach((key, value) { loadedRefills[key] = List<String>.from(value); });
        } else {
          loadedRefills = Map<String, List<String>>.from(_defaultRefills);
        }
        if (!mounted) return;
        setState(() {
          _binders = loadedBinders; _refills = loadedRefills; _cardsData = loadedCards;
          _isPremiumUser = isRevenueCatPremium || (data['isPremiumUser'] == true);
          _isLoadingUser = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _binders = List<BinderModel>.from(_defaultBinders);
          _refills = Map<String, List<String>>.from(_defaultRefills);
          _cardsData = []; 
          _isPremiumUser = isRevenueCatPremium; 
          _isLoadingUser = false;
        });
        await _saveData();
      }
    } catch (e) {
      debugPrint("【エラー】Firestoreからのデータ読み込みエラー: $e");
      if (!mounted) return;
      setState(() { _isLoadingUser = false; });
    }
  }

  Future<bool> _saveData() async {
    final user = _firebaseService.currentUser;
    if (user == null) return false;
    try {
      await _firebaseService.saveUserData(
        uid: user.uid, binders: _binders, refills: _refills, cards: _cardsData, isPremiumUser: _isPremiumUser,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // ★ RevenueCat経由の購入処理（sourceScreenを渡す）
  Future<void> _handlePremiumPurchase({String sourceScreen = 'binder_screen'}) async {
    final Package? package = await PurchaseManager.fetchMonthlyPackage();
    if (package == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入パッケージを取得できませんでした。ネットワーク状況を確認してください。')),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
    );

    try {
      // ★ RevenueCatでの実際の課金実行 ＆ Analyticsに送信
      bool success = await PurchaseManager.purchase(
        package,
        sourceScreen: sourceScreen,
      );

      if (mounted) Navigator.pop(context); // ローディング削除

      if (success) {
        setState(() {
          _isPremiumUser = true;
        });
        await _saveData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('プレミアムプランに登録しました！カード上限が3,000枚に拡張されました。🎉'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('購入処理がキャンセルまたは失敗しました。')),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("【購入エラー】: $e");
    }
  }

  // ★ 課金ダイアログ表示の補助メソッド
  void _triggerPaywall(String sourceScreen) {
    PurchaseManager.logPaywallImpression(sourceScreen: sourceScreen);
    CardDialogs.showPaywallDialog(
      context, 
      maxFreeCardCount: _maxFreeCardCount,
      onPremiumPurchased: () => _handlePremiumPurchase(sourceScreen: sourceScreen),
    );
  }

  List<String> _getAllUniqueTags() {
    Set<String> tags = {};
    for (var card in _activeCards) { tags.addAll(card.tags); }
    return tags.toList();
  }

  Map<String, int> _getRefillMetrics(String binderName, String refillName) {
    List<CardModel> targets;
    if (refillName == '✨ すべてのカード') {
      targets = _activeCards.where((c) => c.refill.startsWith("${binderName}_")).toList();
    } else if (refillName == '❤️ お気に入り') {
      targets = _activeCards.where((c) => c.refill.startsWith("${binderName}_") && c.isFavorite == true).toList();
    } else {
      final compositeKey = "${binderName}_$refillName";
      targets = _activeCards.where((c) => c.refill == compositeKey).toList();
    }
    return {'kinds': targets.length, 'sheets': targets.fold(0, (sum, item) => sum + item.count)};
  }

  void _reorderBinders(BinderModel draggedBinder, BinderModel targetBinder) {
    if (draggedBinder.name == targetBinder.name) return;
    setState(() {
      final draggedIdx = _binders.indexWhere((b) => b.name == draggedBinder.name);
      final targetIdx = _binders.indexWhere((b) => b.name == targetBinder.name);
      if (draggedIdx != -1 && targetIdx != -1) {
        final item = _binders.removeAt(draggedIdx);
        _binders.insert(targetIdx, item);
      }
    });
    _saveData();
  }

  void _reorderCards(CardModel draggedCard, CardModel targetCard) {
    if (draggedCard.id == targetCard.id) return;
    setState(() {
      final draggedIdx = _cardsData.indexWhere((c) => c.id == draggedCard.id);
      final targetIdx = _cardsData.indexWhere((c) => c.id == targetCard.id);
      if (draggedIdx != -1 && targetIdx != -1) {
        final item = _cardsData.removeAt(draggedIdx);
        _cardsData.insert(targetIdx, item); 
      }
    });
    _saveData();
  }

  void _reorderRefills(String draggedRefill, String targetRefill) {
    final binderName = _openedBinderName;
    if (binderName == null || draggedRefill == targetRefill) return;
    setState(() {
      final list = _refills[binderName];
      if (list != null) {
        final draggedIdx = list.indexOf(draggedRefill);
        final targetIdx = list.indexOf(targetRefill);
        if (draggedIdx != -1 && targetIdx != -1) {
          final item = list.removeAt(draggedIdx);
          list.insert(targetIdx, item);
        }
      }
    });
    _saveData();
  }

  void _executeIndividualRestore(CardModel flattenedCard) {
    setState(() {
      final masterIdx = _cardsData.indexWhere((c) => c.id == flattenedCard.id);
      if (masterIdx == -1) return;
      final master = _cardsData[masterIdx];
      if (_showAllDuplicates && master.count > 1) {
        _cardsData[masterIdx] = master.copyWith(count: master.count - 1);
        final newId = _generateUniqueId();
        _cardsData.insert(0, CardModel(id: newId, refill: master.refill, count: 1, frontUrl: master.frontUrl, thumbnailFrontUrl: master.thumbnailFrontUrl, backUrl: master.backUrl, tags: master.tags, memo: master.memo, date: master.date, isDeleted: false, deletedAt: null, isFavorite: master.isFavorite, timestamp: master.timestamp));
      } else {
        _cardsData[masterIdx] = master.copyWith(isDeleted: false, deletedAt: null);
      }
    });
    _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_showAllDuplicates ? 'カードを1枚元のリフィルに復元しました！✨' : 'カードを元のリフィルに復元しました！✨')));
  }

  void _executeIndividualPermanentDelete(CardModel flattenedCard) {
    setState(() {
      final masterIdx = _cardsData.indexWhere((c) => c.id == flattenedCard.id);
      if (masterIdx == -1) return;
      final master = _cardsData[masterIdx];
      if (_showAllDuplicates && master.count > 1) { 
        _cardsData[masterIdx] = master.copyWith(count: master.count - 1); 
      } else { 
        _cardsData.removeAt(masterIdx); 
      }
    });
    _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('完全に削除しました 🗑️')));
  }

  void _wrapperShowAddBinderDialog(BuildContext ctx, {required Function(String) onCreated}) {
    final TextEditingController nameController = TextEditingController();
    String selectedCover = _presetColors.first;

    showDialog(
      context: ctx,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulCtx, setDialogState) {
            Future<void> pickImage(ImageSource source) async {
              if (!_isPremiumUser) {
                _triggerPaywall('add_binder_custom_cover');
                return;
              }
              try {
                final XFile? pickedFile = await _picker.pickImage(
                  source: source, 
                  imageQuality: 70,
                  maxWidth: 600,
                  maxHeight: 800,
                );
                if (pickedFile != null) {
                  setDialogState(() {
                    selectedCover = pickedFile.path; 
                  });
                }
              } catch (e) {
                debugPrint("画像選択エラー: $e");
              }
            }

            return AlertDialog(
              title: const Text('新しいバインダーを追加', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      onChanged: (val) => setDialogState(() {}),
                      decoration: const InputDecoration(hintText: 'バインダー名を入力してください'),
                    ),
                    const SizedBox(height: 20),
                    const Align(alignment: Alignment.centerLeft, child: Text('表紙のデザインを選択', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const SizedBox(height: 10),
                    Container(
                      width: 80, height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SafeCardImage(urlOrBase64: selectedCover),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: Icon(Icons.camera_alt, color: _isPremiumUser ? Colors.pinkAccent : Colors.grey),
                          label: Text('カメラ', style: TextStyle(color: _isPremiumUser ? Colors.pinkAccent : Colors.grey)),
                          onPressed: () => pickImage(ImageSource.camera),
                        ),
                        TextButton.icon(
                          icon: Icon(Icons.photo_library, color: _isPremiumUser ? Colors.pinkAccent : Colors.grey),
                          label: Text('ギャラリー', style: TextStyle(color: _isPremiumUser ? Colors.pinkAccent : Colors.grey)),
                          onPressed: () => pickImage(ImageSource.gallery),
                        ),
                      ],
                    ),
                    const Divider(),
                    const Align(alignment: Alignment.centerLeft, child: Text('単色から選ぶ', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_presetColors.length, (i) {
                          final colorHex = _presetColors[i];
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedCover = colorHex),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 35, height: 35,
                              decoration: BoxDecoration(
                                color: Color(int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16)),
                                shape: BoxShape.circle,
                                border: selectedCover == colorHex ? Border.all(color: Colors.black87, width: 2.5) : Border.all(color: Colors.grey.withOpacity(0.3)),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: Text('写真プリセットから選ぶ', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_presetCovers.length, (i) {
                          final url = _presetCovers[i];
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedCover = url),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 45, height: 60,
                              decoration: BoxDecoration(
                                border: selectedCover == url ? Border.all(color: Colors.pinkAccent, width: 3) : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Image.network(url, fit: BoxFit.cover),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                  onPressed: nameController.text.trim().isEmpty ? null : () async {
                    final name = nameController.text.trim();
                    
                    final isDuplicate = _binders.any((b) => b.name == name);
                    if (isDuplicate) {
                      showDialog(
                        context: dialogContext,
                        builder: (errorContext) => AlertDialog(
                          title: const Text('エラー', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: const Text('同じ名前のバインダーが既に存在します。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(errorContext),
                              child: const Text('OK', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                    
                    showDialog(
                      context: dialogContext,
                      barrierDismissible: false,
                      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
                    );

                    String finalCoverUrl = selectedCover;
                    if (!finalCoverUrl.startsWith('http') && !finalCoverUrl.startsWith('#') && !finalCoverUrl.startsWith('data:')) {
                      final file = File(finalCoverUrl);
                      if (file.existsSync()) {
                        final uploadedUrl = await _firebaseService.uploadBinderCoverImage(XFile(finalCoverUrl), name);
                        if (uploadedUrl != null) finalCoverUrl = uploadedUrl;
                      }
                    }

                    if (dialogContext.mounted) Navigator.pop(dialogContext);

                    setState(() { 
                      _binders.add(BinderModel(name: name, coverUrl: finalCoverUrl)); 
                      _refills[name] = ['デフォルト']; 
                    });
                    await _saveData();
                    Navigator.pop(dialogContext);
                    onCreated(name);
                  },
                  child: const Text('作成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _wrapperShowEditBinderDialog(BuildContext ctx, int index) {
    final oldBinder = _binders[index];
    final TextEditingController nameController = TextEditingController(text: oldBinder.name);
    String selectedCover = oldBinder.coverUrl;

    showDialog(
      context: ctx,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulCtx, setDialogState) {
            Future<void> pickImage(ImageSource source) async {
              if (!_isPremiumUser) {
                _triggerPaywall('edit_binder_custom_cover');
                return;
              }
              try {
                final XFile? pickedFile = await _picker.pickImage(
                  source: source, 
                  imageQuality: 70,
                  maxWidth: 600,
                  maxHeight: 800,
                );
                if (pickedFile != null) {
                  setDialogState(() {
                    selectedCover = pickedFile.path; 
                  });
                }
              } catch (e) {
                debugPrint("【画像処理エラー】: $e");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('エラー詳細: $e'), 
                    backgroundColor: Colors.redAccent,
                    duration: const Duration(seconds: 6),
                  ));
                }
                return; 
              }
            }

            return AlertDialog(
              title: const Text('バインダーを編集', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      onChanged: (val) => setDialogState(() {}),
                      decoration: const InputDecoration(hintText: 'バインダー名を入力してください'),
                    ),
                    const SizedBox(height: 20),
                    const Align(alignment: Alignment.centerLeft, child: Text('表紙のデザインを変更', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const SizedBox(height: 10),
                    Container(
                      width: 80, height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SafeCardImage(urlOrBase64: selectedCover),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: Icon(Icons.camera_alt, color: _isPremiumUser ? Colors.pinkAccent : Colors.grey),
                          label: Text('カメラ', style: TextStyle(color: _isPremiumUser ? Colors.pinkAccent : Colors.grey)),
                          onPressed: () => pickImage(ImageSource.camera),
                        ),
                        TextButton.icon(
                          icon: Icon(Icons.photo_library, color: _isPremiumUser ? Colors.pinkAccent : Colors.grey),
                          label: Text('ギャラリー', style: TextStyle(color: _isPremiumUser ? Colors.pinkAccent : Colors.grey)),
                          onPressed: () => pickImage(ImageSource.gallery),
                        ),
                      ],
                    ),
                    const Divider(),
                    const Align(alignment: Alignment.centerLeft, child: Text('単色から選ぶ', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_presetColors.length, (i) {
                          final colorHex = _presetColors[i];
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedCover = colorHex),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 35, height: 35,
                              decoration: BoxDecoration(
                                color: Color(int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16)),
                                shape: BoxShape.circle,
                                border: selectedCover == colorHex ? Border.all(color: Colors.black87, width: 2.5) : Border.all(color: Colors.grey.withOpacity(0.3)),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: Text('写真プリセットから選ぶ', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_presetCovers.length, (i) {
                          final url = _presetCovers[i];
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedCover = url),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 45, height: 60,
                              decoration: BoxDecoration(
                                border: selectedCover == url ? Border.all(color: Colors.pinkAccent, width: 3) : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Image.network(url, fit: BoxFit.cover),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  label: const Text('削除', style: TextStyle(color: Colors.redAccent)),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    
                    final binderName = oldBinder.name; 
                    
                    final totalCards = _activeCards
                        .where((c) => c.refill.startsWith("${binderName}_"))
                        .fold(0, (sum, item) => sum + item.count);
                    
                    CardDialogs.showDeleteBinderDialog(
                      context, 
                      binder: oldBinder, 
                      totalCards: totalCards, 
                      onDelete: () { 
                        setState(() { 
                          _binders.removeWhere((b) => b.name == binderName); 
                          _refills.remove(binderName); 
                        }); 
                        _saveData(); 
                      }
                    );
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                      onPressed: nameController.text.trim().isEmpty ? null : () async {
                        final newName = nameController.text.trim();
                        
                        if (oldBinder.name != newName) {
                          final isDuplicate = _binders.any((b) => b.name == newName);
                          if (isDuplicate) {
                            showDialog(
                              context: dialogContext,
                              builder: (errorContext) => AlertDialog(
                                title: const Text('エラー', style: TextStyle(fontWeight: FontWeight.bold)),
                                content: const Text('同じ名前のバインダーが既に存在します。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(errorContext),
                                    child: const Text('OK', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                        }

                        showDialog(
                          context: dialogContext,
                          barrierDismissible: false,
                          builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
                        );

                        String finalCoverUrl = selectedCover;
                        if (!finalCoverUrl.startsWith('http') && !finalCoverUrl.startsWith('#') && !finalCoverUrl.startsWith('data:')) {
                          final file = File(finalCoverUrl);
                          if (file.existsSync()) {
                            final uploadedUrl = await _firebaseService.uploadBinderCoverImage(XFile(file.path), newName);
                            if (uploadedUrl != null) finalCoverUrl = uploadedUrl;
                          }
                        }

                        if (dialogContext.mounted) Navigator.pop(dialogContext);

                        setState(() {
                          _binders[index] = BinderModel(name: newName, coverUrl: finalCoverUrl);
                          if (oldBinder.name != newName) {
                            final savedRefills = _refills.remove(oldBinder.name);
                            if (savedRefills != null) _refills[newName] = savedRefills;
                            for (int i = 0; i < _cardsData.length; i++) {
                              if (_cardsData[i].refill.startsWith("${oldBinder.name}_")) {
                                final pureRefillName = _cardsData[i].refill.replaceFirst("${oldBinder.name}_", "");
                                _cardsData[i] = _cardsData[i].copyWith(refill: "${newName}_$pureRefillName");
                              }
                            }
                            if (_openedBinderName == oldBinder.name) _openedBinderName = newName;
                          }
                        });
                        await _saveData();
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _wrapperShowAddRefillDialog(BuildContext ctx, {required String binderName, required Function(String) onCreated}) {
    CardDialogs.showAddRefillDialog(ctx, binderName: binderName, onCreated: (newRefillName) async {
      final currentRefills = _refills[binderName] ?? [];
      final isSystemFolder = newRefillName == '✨ すべてのカード' || newRefillName == '❤️ お気に入り';

      if (currentRefills.contains(newRefillName) || isSystemFolder) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('同じ名前のリフィルが既に存在します。'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      setState(() { 
        if (!_refills.containsKey(binderName)) _refills[binderName] = []; 
        _refills[binderName]!.add(newRefillName); 
      });
      await _saveData();
      onCreated(newRefillName);
    });
  }

  void _wrapperShowEditRefillDialog(BuildContext ctx, String oldRefillName) {
    final TextEditingController nameController = TextEditingController(text: oldRefillName);
    showDialog(
      context: ctx,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('リフィルを編集', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: '新しいリフィル名を入力してください'),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
              label: const Text('削除', style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                Navigator.pop(dialogContext);
                final binderName = _openedBinderName ?? '';
                final totalCards = _activeCards.where((c) => c.refill == "${binderName}_$oldRefillName").length;
                
                CardDialogs.showDeleteRefillDialog(
                  ctx, 
                  refillName: oldRefillName, 
                  totalCards: totalCards, 
                  onDelete: () { 
                    setState(() { 
                      if (_openedBinderName != null) { 
                        _refills[_openedBinderName!]!.remove(oldRefillName); 
                      } 
                    }); 
                    _saveData(); 
                  },
                );
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                  onPressed: () async {
                    final newRefillName = nameController.text.trim();
                    if (newRefillName.isEmpty || newRefillName == oldRefillName) {
                      Navigator.pop(dialogContext);
                      return;
                    }

                    final binderName = _openedBinderName ?? '';
                    final refillsList = _refills[binderName] ?? [];
                    final isSystemFolder = newRefillName == '✨ すべてのカード' || newRefillName == '❤️ お気に入り';

                    if (refillsList.contains(newRefillName) || isSystemFolder) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('同じ名前のリフィルが既に存在します。'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setState(() {
                      final idx = refillsList.indexOf(oldRefillName);
                      if (idx != -1) refillsList[idx] = newRefillName;
                      
                      final oldCompositeKey = "${binderName}_$oldRefillName";
                      final newCompositeKey = "${binderName}_$newRefillName";
                      for (int i = 0; i < _cardsData.length; i++) {
                        if (_cardsData[i].refill == oldCompositeKey) {
                          _cardsData[i] = _cardsData[i].copyWith(refill: newCompositeKey);
                        }
                      }
                    });
                    await _saveData();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  bool _isCurrentlyInsideRefill() {
    return _openedRefillName != null && !_isTrashMode;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.pinkAccent), SizedBox(height: 16), Text('データをクラウドから同期中...', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))])));
    }

    final bool isRefillPage = _isCurrentlyInsideRefill();

    String titleText = _isTrashMode 
        ? 'ゴミ箱（30日前自動消去）' 
        : (_openedBinderName == null 
            ? 'Shelinekko' 
            : (_openedRefillName ?? _openedBinderName ?? 'Shelinekko'));

    int crossAxisCount = _cardsPerPage <= 4 ? 2 : (_cardsPerPage >= 12 ? 4 : 3);
    int currentMaxCount = _isPremiumUser ? _maxPremiumCardCount : _maxFreeCardCount;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: isRefillPage 
            ? const SizedBox.shrink() 
            : Column(children: [
                Text(titleText, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    _isPremiumUser 
                        ? '枚数: $_totalActiveCardCount枚' 
                        : '枚数: $_totalActiveCardCount / $currentMaxCount', 
                    style: TextStyle(
                      fontSize: 10, 
                      color: (!_isPremiumUser && _totalActiveCardCount >= currentMaxCount) ? Colors.red : Colors.grey[700], 
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isPremiumUser) ...[const SizedBox(width: 4), const Icon(Icons.workspace_premium, color: Colors.amber, size: 12)]
                ])
              ]),
        centerTitle: true, backgroundColor: Colors.transparent, elevation: 0,
        leading: (_openedBinderName != null || _isTrashMode) ? IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20), onPressed: () => setState(() { _isSelectMode = false; _selectedCardUniqueKeys.clear(); if (_isTrashMode) { _isTrashMode = false; } else if (_openedRefillName != null) { _openedRefillName = null; _searchQuery = ''; _selectedTagFilter = null; _sortOrder = 'custom'; } else { _openedBinderName = null; } })) : null,
        actions: [
          if (_openedBinderName == null && !_isTrashMode)
            const SizedBox(width: 56),
          if (_openedRefillName != null || _isTrashMode) TextButton(onPressed: () => setState(() { _isSelectMode = !_isSelectMode; _selectedCardUniqueKeys.clear(); }), child: Text(_isSelectMode ? 'キャンセル' : '選択', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
          if (_openedBinderName != null && _openedRefillName == null && !_isTrashMode) IconButton(icon: Icon(_showRefillCounts ? Icons.analytics : Icons.analytics_outlined, color: Colors.black87), onPressed: () => setState(() => _showRefillCounts = !_showRefillCounts)),
          if (_openedRefillName != null && !_isTrashMode && !_isSelectMode) ...[
            IconButton(icon: const Icon(Icons.sort_rounded, color: Colors.black87), onPressed: () => CardDialogs.showSortOrderBottomSheet(context, currentSortOrder: _sortOrder, onSortOrderChanged: (val) => setState(() => _sortOrder = val))),
            IconButton(icon: const Icon(Icons.settings, color: Colors.black87), onPressed: () => CardDialogs.showSettingsDialog(context, cardsPerPage: _cardsPerPage, onChanged: (val) => setState(() => _cardsPerPage = val))),
            IconButton(icon: Icon(_isPageMode ? Icons.view_day_outlined : Icons.menu_book, color: Colors.black87), onPressed: () => setState(() => _isPageMode = !_isPageMode)),
          ],
          if ((_openedRefillName != null || _isTrashMode) && !_isSelectMode)
            IconButton(icon: Icon(_showAllDuplicates ? Icons.filter_none : Icons.copy, color: Colors.black87), onPressed: () => setState(() { _showAllDuplicates = !_showAllDuplicates; })),
        ],
      ),
      
      drawer: (_openedBinderName == null && !_isTrashMode)
          ? Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      color: Colors.pinkAccent,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: const [
                        Text(
                          'Shelinekko',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'メニュー',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.black87),
                    title: const Text(
                      'マイページ',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MyPageScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                    title: Text(
                      _isPremiumUser ? 'プレミアムプラン（適用中）' : 'プレミアムプランの案内',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    subtitle: Text(
                      _isPremiumUser ? '最大3,000枚まで登録可能・広告非表示' : 'カード登録数が最大3,000枚に拡張されます',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (_isPremiumUser) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.workspace_premium, color: Colors.amber),
                                SizedBox(width: 8),
                                Text('プレミアムプラン', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            content: const Text('現在プレミアムプランが適用されています。\nカード登録数が最大3,000枚となり、広告は非表示になっています。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      } else {
                        _triggerPaywall('binder_screen_drawer');
                      }
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: Colors.black87),
                    title: const Text(
                      'お問い合わせ',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    onTap: () {
                      Navigator.pop(context); 
                      final user = _firebaseService.currentUser;
                      CardDialogs.showFeedbackDialog(
                        context, 
                        uid: user?.uid ?? 'anonymous', 
                        onSend: (title, content, email) async {
                          await _firebaseService.sendFeedback(
                            uid: user?.uid ?? 'anonymous', 
                            title: title, 
                            content: content, 
                            email: email,
                            platform: Theme.of(context).platform.toString(),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            )
          : null,

      body: Column(
        children: [
          Expanded(child: _buildBody(crossAxisCount)),
          _buildBannerAdPlaceholder(),
        ],
      ),
      floatingActionButton: (_isTrashMode || _isSelectMode) ? null : FloatingActionButton(
        backgroundColor: Colors.black87, child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          CardDialogs.showAddMenu(
            context, 
            openedBinderName: _openedBinderName, 
            onAddBinder: () => _wrapperShowAddBinderDialog(context, onCreated: (_) {}), 
            onAddRefill: () => _wrapperShowAddRefillDialog(context, binderName: _openedBinderName!, onCreated: (_) {}), 
            onAddCard: () {
              CardDialogs.showAddCardForm(
                context, 
                isPremiumUser: _isPremiumUser,
                totalActiveCardCount: _totalActiveCardCount,
                maxFreeCardCount: _maxFreeCardCount,
                onPaywallTriggered: () async {
                  _triggerPaywall('add_card_limit_dialog');
                  return true;
                },
                openedBinderName: _openedBinderName, 
                openedRefillName: (_openedRefillName == '✨ すべてのカード' || _openedRefillName == '❤️ お気に入り') ? null : _openedRefillName,
                binders: _binders, refills: _refills, lastRegisteredData: _lastRegisteredData, 
                showAddBinderDialog: (dialogCtx, callback) => _wrapperShowAddBinderDialog(dialogCtx, onCreated: callback),  
                showAddRefillDialog: (dialogCtx, bName, callback) => _wrapperShowAddRefillDialog(dialogCtx, binderName: bName, onCreated: callback),
                onCardAdded: (newCard, savedData) async {
                  int maxLimit = _isPremiumUser ? _maxPremiumCardCount : _maxFreeCardCount;
                  if ((_totalActiveCardCount + newCard.count) > maxLimit) {
                    if (!_isPremiumUser) {
                      _triggerPaywall('add_card_limit_dialog');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('カードの登録上限（3,000枚）に達しています。'), backgroundColor: Colors.redAccent),
                      );
                    }
                    return false; 
                  }
                  
                  final user = _firebaseService.currentUser;
                  if (user == null) return false; 

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
                  );

                  String frontUrl = newCard.frontUrl;
                  String thumbnailFrontUrl = '';
                  String backUrl = newCard.backUrl;
                  final String newCardId = _generateUniqueId();
                  
                  bool success = false;

                  try {
                    final tempDir = await getTemporaryDirectory();

                    if (frontUrl.startsWith('data:image')) {
                      String cleanBase64 = frontUrl.contains(',') ? frontUrl.split(',')[1] : frontUrl;
                      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
                      final bytes = base64Decode(cleanBase64);
                      final file = File('${tempDir.path}/front_$newCardId.jpg');
                      await file.writeAsBytes(bytes);

                      final uploadResult = await _firebaseService.uploadCardImage(XFile(file.path), '${newCardId}_front');
                      if (uploadResult != null) {
                        frontUrl = uploadResult.originalUrl;
                        thumbnailFrontUrl = uploadResult.thumbnailUrl;
                      } else {
                        throw Exception('表面画像のアップロードに失敗しました。');
                      }
                    } else if (!frontUrl.startsWith('http') && !frontUrl.startsWith('#') && frontUrl.isNotEmpty) {
                      final file = File(frontUrl);
                      if (file.existsSync()) {
                        final uploadResult = await _firebaseService.uploadCardImage(XFile(file.path), '${newCardId}_front');
                        if (uploadResult != null) {
                          frontUrl = uploadResult.originalUrl;
                          thumbnailFrontUrl = uploadResult.thumbnailUrl;
                        } else {
                          throw Exception('表面画像のアップロードに失敗しました。');
                        }
                      }
                    }

                    if (thumbnailFrontUrl.isEmpty) {
                      thumbnailFrontUrl = _firebaseService.predictThumbnailUrl(frontUrl);
                    }

                    if (backUrl.startsWith('data:image')) {
                      String cleanBase64 = backUrl.contains(',') ? backUrl.split(',')[1] : backUrl;
                      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
                      final bytes = base64Decode(cleanBase64);
                      final file = File('${tempDir.path}/back_$newCardId.jpg');
                      await file.writeAsBytes(bytes);

                      final uploadResult = await _firebaseService.uploadCardImage(XFile(file.path), '${newCardId}_back');
                      if (uploadResult != null) {
                        backUrl = uploadResult.originalUrl;
                      } else {
                        throw Exception('裏面画像のアップロードに失敗しました。');
                      }
                    } else if (!backUrl.startsWith('http') && !backUrl.startsWith('#') && backUrl.isNotEmpty) {
                      final file = File(backUrl);
                      if (file.existsSync()) {
                        final uploadResult = await _firebaseService.uploadCardImage(XFile(file.path), '${newCardId}_back');
                        if (uploadResult != null) {
                          backUrl = uploadResult.originalUrl;
                        } else {
                          throw Exception('裏面画像のアップロードに失敗しました。');
                        }
                      }
                    }
                    
                    success = true;

                  } catch (e) {
                    debugPrint("【画像処理エラー】: $e");
                    if (context.mounted) Navigator.pop(context); 
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像のアップロード・処理に失敗しました。'), backgroundColor: Colors.redAccent));
                    }
                  }

                  if (!success) {
                    return false;
                  }

                  if (context.mounted) Navigator.pop(context);
                  if (!mounted) return false; 
                  
                  final oldCards = List<CardModel>.from(_cardsData);
                  final oldLastRegisteredData = _lastRegisteredData;

                  setState(() {
                    String? targetBinder;
                    String? targetRefill;

                    if (savedData != null) {
                      targetBinder = savedData['binder']?.toString() ?? savedData['binderName']?.toString() ?? savedData['selectedBinder']?.toString();
                      targetRefill = savedData['refill']?.toString() ?? savedData['refillName']?.toString() ?? savedData['selectedRefill']?.toString();
                    }

                    if (newCard.refill.contains('_')) {
                      final firstUnderscore = newCard.refill.indexOf('_');
                      targetBinder ??= newCard.refill.substring(0, firstUnderscore);
                      targetRefill ??= newCard.refill.substring(firstUnderscore + 1);
                    } else {
                      targetRefill ??= newCard.refill;
                    }

                    targetBinder ??= _openedBinderName ?? (_binders.isNotEmpty ? _binders[0].name : 'マイコレクション');
                    if (targetRefill == null || targetRefill.isEmpty || targetRefill == '✨ すべてのカード' || targetRefill == '❤️ お気に入り') {
                      targetRefill = 'デフォルト';
                    }

                    final String finalRefill = "${targetBinder}_$targetRefill";
                    int finalTimestamp = DateTime.now().millisecondsSinceEpoch;
                    if (newCard.timestamp is int) finalTimestamp = newCard.timestamp;

                    _cardsData.insert(0, CardModel(
                      id: newCardId, refill: finalRefill, count: newCard.count, frontUrl: frontUrl, thumbnailFrontUrl: thumbnailFrontUrl, backUrl: backUrl,
                      tags: newCard.tags, memo: newCard.memo, date: newCard.date, isDeleted: false, deletedAt: null, isFavorite: false, timestamp: finalTimestamp, 
                    ));
                    _lastRegisteredData = savedData; 
                  });
                  
                  final bool isSaved = await _saveData();
                  
                  if (mounted) {
                    if (isSaved) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新しいカードを追加しました！✨')));
                    } else {
                      setState(() { _cardsData = oldCards; _lastRegisteredData = oldLastRegisteredData; });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('【保存エラー】カードを保存できませんでした。'), backgroundColor: Colors.redAccent));
                    }
                  }

                  return isSaved; 
                }

              );
            },
          );
        },
      ),
      bottomNavigationBar: _isSelectMode ? _buildBulkActionWidgets() : null,
    );
  }

  Widget _buildBannerAdPlaceholder() {
    if (_isPremiumUser || _isSelectMode) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.ads_click, size: 16, color: Colors.grey),
          SizedBox(width: 6),
          Text(
            '【広告】プレミアムプラン登録で非表示になります',
            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionWidgets() {
    final pool = _getFlattenedDisplayCards();
    final isAllSelected = pool.isNotEmpty && pool.every((c) => _selectedCardUniqueKeys.contains(c.uniqueKey!));
    final count = _selectedCardUniqueKeys.length;
    String unit = (_showAllDuplicates || _isTrashMode) ? '枚' : '種';

    return SafeArea(
      child: Container(
        color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)), 
                  icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 16), 
                  label: Text(isAllSelected ? '選択解除' : 'すべて選択', style: const TextStyle(fontSize: 12)), 
                  onPressed: pool.isEmpty ? null : () { setState(() { if (isAllSelected) { for (var c in pool) { _selectedCardUniqueKeys.remove(c.uniqueKey!); } } else { for (var c in pool) { _selectedCardUniqueKeys.add(c.uniqueKey!); } } }); }
                ),
                Text('$count $unit 選択中', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (_isTrashMode) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), 
                    icon: const Icon(Icons.restore, size: 16), label: const Text('一括復元'), 
                    onPressed: count == 0 ? null : () { final displayCards = _getFlattenedDisplayCards(); final selectedCards = displayCards.where((c) => _selectedCardUniqueKeys.contains(c.uniqueKey!)).toList(); for (var sc in selectedCards) { _executeIndividualRestore(sc); } setState(() { _isSelectMode = false; _selectedCardUniqueKeys.clear(); }); }
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), 
                    icon: const Icon(Icons.delete_forever, size: 16), label: const Text('一括消去'), 
                    onPressed: count == 0 ? null : () { final displayCards = _getFlattenedDisplayCards(); final selectedCards = displayCards.where((c) => _selectedCardUniqueKeys.contains(c.uniqueKey!)).toList(); for (var sc in selectedCards) { _executeIndividualPermanentDelete(sc); } setState(() { _isSelectMode = false; _selectedCardUniqueKeys.clear(); }); }
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), 
                    icon: const Icon(Icons.ios_share, size: 16), label: const Text('出力'), 
                    onPressed: count == 0 ? null : () {
                      final displayCards = _getFlattenedDisplayCards();
                      final selectedCards = displayCards.where((c) => _selectedCardUniqueKeys.contains(c.uniqueKey!)).toList();
                      
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ExportScreen(selectedCards: selectedCards),
                        ),
                      );
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white), 
                    icon: const Icon(Icons.drive_file_move_outlined, size: 16), label: const Text('一括移動'), 
                    onPressed: count == 0 ? null : () { CardDialogs.showBulkMoveDialog(context, count: count, unit: unit, binders: _binders, refills: _refills, showAddBinderDialog: (dialogCtx, callback) => _wrapperShowAddBinderDialog(dialogCtx, onCreated: callback), showAddRefillDialog: (dialogCtx, bName, callback) => _wrapperShowAddRefillDialog(dialogCtx, binderName: bName, onCreated: callback), onMove: (selectedBinder, selectedRefill) { setState(() { final targetIds = _selectedCardUniqueKeys.map(_getIdFromUniqueKey).toSet(); final compositeRefill = "${selectedBinder}_$selectedRefill"; for (var id in targetIds) { final targetIdx = _cardsData.indexWhere((c) => c.id == id); if (targetIdx == -1) continue; final target = _cardsData[targetIdx]; if (_showAllDuplicates) { final matchCount = _selectedCardUniqueKeys.where((key) => _getIdFromUniqueKey(key) == id).length; if (target.count > matchCount) { _cardsData[targetIdx] = target.copyWith(count: target.count - matchCount); _cardsData.add(CardModel(id: _generateUniqueId(), refill: compositeRefill, count: matchCount, frontUrl: target.frontUrl, thumbnailFrontUrl: target.thumbnailFrontUrl, backUrl: target.backUrl, tags: target.tags, memo: target.memo, date: target.date, isDeleted: target.isDeleted, deletedAt: target.deletedAt, isFavorite: target.isFavorite, timestamp: target.timestamp)); } else { _cardsData[targetIdx] = target.copyWith(refill: compositeRefill); } } else { _cardsData[targetIdx] = target.copyWith(refill: compositeRefill); } } _isSelectMode = false; _selectedCardUniqueKeys.clear(); }); _saveData(); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('選択したカードを「$selectedRefill」へ一括移動しました！🚀'))); }); }
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), 
                    icon: const Icon(Icons.delete_outline, size: 16), label: const Text('一括削除'), 
                    onPressed: count == 0 ? null : () { setState(() { final targetIds = _selectedCardUniqueKeys.map(_getIdFromUniqueKey).toSet(); for (var id in targetIds) { final targetIdx = _cardsData.indexWhere((c) => c.id == id); if (targetIdx == -1) continue; final target = _cardsData[targetIdx]; if (_showAllDuplicates) { final matchCount = _selectedCardUniqueKeys.where((key) => _getIdFromUniqueKey(key) == id).length; if (target.count > matchCount) { _cardsData[targetIdx] = target.copyWith(count: target.count - matchCount); final newId = _generateUniqueId(); _cardsData.add(CardModel(id: newId, refill: target.refill, count: matchCount, frontUrl: target.frontUrl, thumbnailFrontUrl: target.thumbnailFrontUrl, backUrl: target.backUrl, tags: target.tags, memo: target.memo, date: target.date, isDeleted: true, deletedAt: DateTime.now().toIso8601String(), isFavorite: target.isFavorite, timestamp: target.timestamp)); } else { _cardsData[targetIdx] = target.copyWith(isDeleted: true, deletedAt: DateTime.now().toIso8601String()); } } else { _cardsData[targetIdx] = target.copyWith(isDeleted: true, deletedAt: DateTime.now().toIso8601String()); } } _isSelectMode = false; _selectedCardUniqueKeys.clear(); }); _saveData(); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('指定したカードをゴミ箱に移動しました 🗑️'))); },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(int crossAxisCount) {
    if (_isTrashMode) return _buildTrashPage(crossAxisCount); 
    if (_openedBinderName == null) return _buildBinderPage();
    if (_openedRefillName == null) return _buildRefillPage();
    return _buildCardGridPage(crossAxisCount);
  }

  Widget _buildBinderPage() {
    int totalCount = _binders.length + 1; 
    int totalTrashItems = _trashedCards.fold(0, (sum, c) => sum + c.count);

    return GridView.builder(
      padding: const EdgeInsets.all(16), 
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, 
        crossAxisSpacing: 16, 
        mainAxisSpacing: 20, 
        childAspectRatio: 0.72
      ), 
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index == _binders.length) {
          return GestureDetector(
            onTap: () => setState(() => _isTrashMode = true), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center, 
              children: [
                Expanded(child: Container(width: double.infinity, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[400]!, width: 2)), child: Icon(Icons.delete_sweep_rounded, size: 60, color: Colors.grey[600]))), 
                const SizedBox(height: 10), 
                Text('ゴミ箱 ($totalTrashItems 枚)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[700]))
              ]
            )
          );
        }
        return _buildDragAndDropBinderWrapper(_binders[index], index);
      },
    );
  }

  Widget _buildDragAndDropBinderWrapper(BinderModel binder, int index) {
    final coverUrlToDisplay = _getBinderCoverUrl(binder);

    return LongPressDraggable<BinderModel>(
      data: binder,
      feedback: Material(
        elevation: 6, 
        borderRadius: BorderRadius.circular(14), 
        child: SizedBox(
          width: 100, 
          height: 140, 
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14), 
            child: SafeCardImage(urlOrBase64: coverUrlToDisplay)
          )
        )
      ),
      childWhenDragging: Opacity(
        opacity: 0.3, 
        child: _buildBinderItem(binder, index)
      ),
      child: DragTarget<BinderModel>(
        onWillAcceptWithDetails: (details) => details.data.name != binder.name,
        onAcceptWithDetails: (details) => _reorderBinders(details.data, binder),
        builder: (context, candidateData, rejectedData) { 
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200), 
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14), 
              border: candidateData.isNotEmpty 
                  ? Border.all(color: Colors.pinkAccent, width: 2) 
                  : null
            ), 
            child: _buildBinderItem(binder, index)
          ); 
        },
      ),
    );
  }

  Widget _buildBinderItem(BinderModel binder, int index) {
    final coverUrlToDisplay = _getBinderCoverUrl(binder);

    return GestureDetector(
      onTap: () => setState(() => _openedBinderName = binder.name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, 
        children: [
          Expanded(child: Stack(children: [
            Container(
              width: double.infinity, height: double.infinity, margin: const EdgeInsets.only(left: 8), 
              decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.only(topLeft: Radius.circular(2), bottomLeft: Radius.circular(2), topRight: Radius.circular(14), bottomRight: Radius.circular(14)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(4, 5))], border: Border.all(color: Colors.grey.withOpacity(0.25))), 
              child: ClipRRect(borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomRight: Radius.circular(14)), child: SafeCardImage(urlOrBase64: coverUrlToDisplay))
            ),
            Positioned(top: 0, bottom: 0, left: 2, child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(4, (i) => Container(width: 14, height: 8, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.grey, Colors.white, Colors.black54], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(4)))))),
            Positioned(top: 6, right: 6, child: GestureDetector(onTap: () => _wrapperShowEditBinderDialog(context, index), child: CircleAvatar(radius: 16, backgroundColor: Colors.white.withOpacity(0.8), child: const Icon(Icons.edit, size: 16, color: Colors.black87)))),
          ])),
          const SizedBox(height: 10), 
          Center(child: Text(binder.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildRefillBase({
    required Color containerBgColor,
    required Color borderColor,
    required IconData folderIcon,
    required Color iconColor,
    required String refillName,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: containerBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), shape: BoxShape.circle),
            child: Icon(folderIcon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              refillName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefillPage() {
    final binderName = _openedBinderName ?? '';
    final refillList = ['✨ すべてのカード', '❤️ お気に入り', ...(_refills[binderName] ?? [])];
    
    return GridView.builder(
      padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.1), itemCount: refillList.length,
      itemBuilder: (context, index) {
        final refillName = refillList[index];
        final isSystemFolder = refillName == '✨ すべてのカード' || refillName == '❤️ お気に入り'; 
        final metrics = _getRefillMetrics(binderName, refillName); final kinds = metrics['kinds'] ?? 0; final sheets = metrics['sheets'] ?? 0;
        
        IconData folderIcon = Icons.layers_rounded;
        Color iconColor = Colors.pinkAccent[100]!;
        Color containerBgColor = const Color(0xFFFFF0F3);
        Color borderColor = const Color(0xFFFFDEE4);

        if (refillName == '✨ すべてのカード') {
          folderIcon = Icons.auto_awesome; containerBgColor = const Color(0xFFF0EDE5); borderColor = Colors.black.withOpacity(0.05); iconColor = Colors.amber[800]!;
        } else if (refillName == '❤️ お気に入り') {
          folderIcon = Icons.favorite; containerBgColor = const Color(0xFFFFF0F5); borderColor = Colors.pink.withOpacity(0.15); iconColor = Colors.pinkAccent;
        }

        final Widget baseContent = _buildRefillBase(
          containerBgColor: containerBgColor,
          borderColor: borderColor,
          folderIcon: folderIcon,
          iconColor: iconColor,
          refillName: refillName,
        );

        final Widget itemContent = GestureDetector(
          onTap: () => setState(() => _openedRefillName = refillName),
          child: Stack(children: [
            baseContent,
            Positioned(
              top: 10, right: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isSystemFolder) ...[
                    GestureDetector(onTap: () => _wrapperShowEditRefillDialog(context, refillName), child: CircleAvatar(radius: 14, backgroundColor: Colors.white.withOpacity(0.8), child: const Icon(Icons.edit, size: 14, color: Colors.black87))),
                    const SizedBox(width: 6),
                  ],
                  if (_showRefillCounts) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Text('$kinds種 / $sheets枚', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54))),
                ],
              ),
            ),
          ]),
        );

        if (isSystemFolder) {
          return itemContent;
        }

        return LongPressDraggable<String>(
          data: refillName,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.43,
              height: (MediaQuery.of(context).size.width * 0.43) / 1.1,
              child: baseContent, 
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: itemContent,
          ),
          child: DragTarget<String>(
            onWillAcceptWithDetails: (details) => details.data != refillName,
            onAcceptWithDetails: (details) => _reorderRefills(details.data, refillName),
            builder: (context, candidateData, rejectedData) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: candidateData.isNotEmpty
                      ? Border.all(color: Colors.pinkAccent, width: 2)
                      : null,
                ),
                child: itemContent,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCardGridPage(int crossAxisCount) {
    final displayCards = _getFlattenedDisplayCards(); int perPage = _cardsPerPage.round(); final uniqueTags = _getAllUniqueTags();
    return Column(children: [
      Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: Column(children: [
        TextField(onChanged: (value) => setState(() => _searchQuery = value), decoration: InputDecoration(hintText: 'メモや日付から検索...', prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey), suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchQuery = '')) : null, contentPadding: EdgeInsets.zero, filled: true, fillColor: const Color(0xFFF5F5F5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
        const SizedBox(height: 8),
        SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: [
          ChoiceChip(label: const Text('すべて'), selected: _selectedTagFilter == null, selectedColor: Colors.pink[100], backgroundColor: Colors.grey[200], onSelected: (bool selected) { if (selected) setState(() => _selectedTagFilter = null); }),
          ...uniqueTags.map((tag) => Padding(padding: const EdgeInsets.only(left: 6.0), child: ChoiceChip(label: Text('#$tag'), selected: _selectedTagFilter == tag, selectedColor: Colors.pink[100], backgroundColor: Colors.grey[200], onSelected: (bool selected) => setState(() => _selectedTagFilter = selected ? tag : null)))),
        ])),
      ])),
      if (_sortOrder == 'custom' && !_isSelectMode && !_showAllDuplicates) Container(width: double.infinity, color: Colors.pink[50], padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.touch_app_outlined, size: 14, color: Colors.pinkAccent), const SizedBox(width: 4), Text('カードを長押しで並べ替え、ダブルタップで裏返せます 🔄', style: TextStyle(fontSize: 11, color: Colors.pinkAccent, fontWeight: FontWeight.bold))])),
      Expanded(child: displayCards.isEmpty ? const Center(child: Text('条件に合うカードが見つかりません 🔍')) : _isPageMode ? _buildPageViewGrid(displayCards, perPage, crossAxisCount) : _buildNormalGrid(displayCards, crossAxisCount)),
    ]);
  }

  Widget _buildPageViewGrid(List<CardModel> displayCards, int perPage, int crossAxisCount) {
    int pagesCount = (displayCards.length / perPage).ceil(); final pool = _getCurrentDisplayPool(); int kindsCount = pool.length; int totalSheets = pool.fold(0, (sum, c) => sum + c.count);
    return PageView.builder(itemCount: pagesCount, itemBuilder: (context, pageIndex) {
      int start = pageIndex * perPage; int end = (start + perPage > displayCards.length) ? displayCards.length : start + perPage;
      List<CardModel> pageCards = displayCards.sublist(start, end);
      return Column(children: [
        Expanded(child: GridView.builder(padding: const EdgeInsets.all(16), physics: const NeverScrollableScrollPhysics(), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 54 / 86), itemCount: pageCards.length, itemBuilder: (context, index) => _buildDragAndDropCardWrapper(pageCards[index]))),
        Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Text('${pageIndex + 1} / $pagesCount ページ (該当: $kindsCount 種 / 計 $totalSheets 枚)', style: TextStyle(color: Colors.grey[600], fontSize: 12))),
      ]);
    });
  }

  Widget _buildNormalGrid(List<CardModel> displayCards, int crossAxisCount) => GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 54 / 86), itemCount: displayCards.length, itemBuilder: (context, index) => _buildDragAndDropCardWrapper(displayCards[index]));

  void _handleCardTap(CardModel card, bool isSelected) {
    if (_isSelectMode) {
      setState(() {
        if (isSelected) {
          _selectedCardUniqueKeys.remove(card.uniqueKey!);
        } else {
          _selectedCardUniqueKeys.add(card.uniqueKey!);
        }
      });
    } else {
      _wrapperShowCardDetailDialog(card, isFromTrash: false);
    }
  }

  Widget _buildDragAndDropCardWrapper(CardModel card) {
    final isSelected = _selectedCardUniqueKeys.contains(card.uniqueKey!);

    if (_isSelectMode || _showAllDuplicates || _sortOrder != 'custom') {
      return _FlipCardItem(
        card: card,
        isSelected: isSelected,
        isSelectMode: _isSelectMode,
        showAllDuplicates: _showAllDuplicates,
        onTap: () => _handleCardTap(card, isSelected),
      );
    }
    return LongPressDraggable<CardModel>(
      data: card,
      feedback: Material(
        elevation: 6, 
        borderRadius: BorderRadius.circular(8), 
        child: SizedBox(
          width: 90, 
          height: 90 * 86 / 54, 
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8), 
            child: SafeCardImage(
              urlOrBase64: card.thumbnailFrontUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _FlipCardItem(card: card, isSelected: isSelected, isSelectMode: _isSelectMode, showAllDuplicates: _showAllDuplicates, onTap: () {})),
      child: DragTarget<CardModel>(
        onWillAcceptWithDetails: (details) => details.data.id != card.id,
        onAcceptWithDetails: (details) => _reorderCards(details.data, card),
        builder: (context, candidateData, rejectedData) { return AnimatedContainer(duration: const Duration(milliseconds: 200), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: candidateData.isNotEmpty ? Border.all(color: Colors.pinkAccent, width: 2) : null), child: _FlipCardItem(card: card, isSelected: isSelected, isSelectMode: _isSelectMode, showAllDuplicates: _showAllDuplicates, onTap: () => _handleCardTap(card, isSelected))); },
      ),
    );
  }

  Widget _buildTrashPage(int crossAxisCount) {
    final trashed = _getFlattenedDisplayCards();
    if (trashed.isEmpty) return const Center(child: Text('ゴミ箱は空っぽです 🧹', style: TextStyle(color: Colors.grey, fontSize: 15)));
    return GridView.builder(
      padding: const EdgeInsets.all(16), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: 0.52), itemCount: trashed.length,
      itemBuilder: (context, index) {
        final card = trashed[index]; final deletedDate = DateTime.parse(card.deletedAt!); final remainingDays = 30 - DateTime.now().difference(deletedDate).inDays; final isSelected = _selectedCardUniqueKeys.contains(card.uniqueKey!);
        return GestureDetector(
          onTap: () { if (_isSelectMode) { setState(() { if (isSelected) { _selectedCardUniqueKeys.remove(card.uniqueKey!); } else { _selectedCardUniqueKeys.add(card.uniqueKey!); } }); } else { _wrapperShowCardDetailDialog(card, isFromTrash: true); } },
          child: Column(children: [
            AspectRatio(
              aspectRatio: 54 / 86,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8), 
                  border: Border.all(
                    color: isSelected ? Colors.pinkAccent : Colors.grey.withOpacity(0.4), 
                    width: isSelected ? 3.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ), 
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6), 
                  child: Stack(children: [
                    Positioned.fill(
                      child: SafeCardImage(
                        urlOrBase64: card.thumbnailFrontUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (!_showAllDuplicates && card.count > 1) 
                      Positioned(top: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(10)), child: Text('${card.count}枚', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                    if (!_isSelectMode) Positioned(bottom: 4, left: 4, right: 4, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [CircleAvatar(radius: 16, backgroundColor: Colors.white.withOpacity(0.9), child: IconButton(icon: const Icon(Icons.restore, size: 16, color: Colors.blue), onPressed: () => CardDialogs.showRestoreConfirmDialog(context, onRestore: () => _executeIndividualRestore(card)))), CircleAvatar(radius: 16, backgroundColor: Colors.white.withOpacity(0.9), child: IconButton(icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red), onPressed: () => CardDialogs.showPermanentlyDeleteDialog(context, onDelete: () => _executeIndividualPermanentDelete(card))))])),
                    if (_isSelectMode) Positioned(top: 4, left: 4, child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? Colors.pinkAccent : Colors.white, size: 22)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 4), Text('あと $remainingDays 日', style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ]),
        );
      },
    );
  }

  void _wrapperShowCardDetailDialog(CardModel card, {required bool isFromTrash}) {
    CardDialogs.showCardDetailDialog(
      context, card: card, isFromTrash: isFromTrash, isPremiumUser: _isPremiumUser, totalActiveCardCount: _totalActiveCardCount, maxFreeCardCount: _maxFreeCardCount,
      onFavoriteToggled: () { setState(() { final masterIdx = _cardsData.indexWhere((c) => c.id == card.id); if (masterIdx != -1) { _cardsData[masterIdx] = _cardsData[masterIdx].copyWith(isFavorite: !_cardsData[masterIdx].isFavorite); } }); _saveData(); },
      onCardUpdated: (updatedCard) { setState(() { final index = _cardsData.indexWhere((c) => c.id == updatedCard.id); if (index != -1) _cardsData[index] = updatedCard; }); _saveData(); },
      onDeletePressed: () {
        CardDialogs.showDeleteConfirmDialog(context, onDelete: () {
          if (Navigator.canPop(context)) Navigator.pop(context); 

          Future.delayed(Duration.zero, () {
            if (!mounted) return;
            setState(() {
              final targetIdx = _cardsData.indexWhere((c) => c.id == card.id);
              if (targetIdx == -1) return;
              final targetCard = _cardsData[targetIdx];
              if (_showAllDuplicates && targetCard.count > 1) {
                _cardsData[targetIdx] = targetCard.copyWith(count: targetCard.count - 1); 
                final newId = _generateUniqueId();
                _cardsData.add(CardModel(id: newId, refill: targetCard.refill, count: 1, frontUrl: targetCard.frontUrl, thumbnailFrontUrl: targetCard.thumbnailFrontUrl, backUrl: targetCard.backUrl, tags: targetCard.tags, memo: targetCard.memo, date: targetCard.date, isDeleted: true, deletedAt: DateTime.now().toIso8601String(), isFavorite: targetCard.isFavorite, timestamp: targetCard.timestamp));
              } else { 
                _cardsData[targetIdx] = targetCard.copyWith(isDeleted: true, deletedAt: DateTime.now().toIso8601String()); 
              }
            });
            _saveData();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('カードをゴミ箱に移動しました 🗑️')));
          });
        });
      },
      onMovePressed: (card) {
        CardDialogs.showMoveCardDialog(
          context, masterCard: card, binders: _binders, refills: _refills,
          showAddBinderDialog: (dialogCtx, callback) => _wrapperShowAddBinderDialog(dialogCtx, onCreated: callback), 
          showAddRefillDialog: (dialogCtx, bName, callback) => _wrapperShowAddRefillDialog(dialogCtx, binderName: bName, onCreated: callback), 
          onMove: (card, selectedBinder, selectedRefill) {
            if (Navigator.canPop(context)) Navigator.pop(context); 

            Future.delayed(Duration.zero, () {
              if (!mounted) return;
              setState(() {
                final compositeRefill = "${selectedBinder}_$selectedRefill";
                final masterIdx = _cardsData.indexWhere((c) => c.id == card.id);
                if (masterIdx != -1) _cardsData[masterIdx] = _cardsData[masterIdx].copyWith(refill: compositeRefill);
              });
              _saveData();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$selectedRefill」へ移動しました！🚀')));
            });
          }
        );
      },
      onRestorePressed: () { CardDialogs.showRestoreConfirmDialog(context, onRestore: () { _executeIndividualRestore(card); setState(() { _isSelectMode = false; _selectedCardUniqueKeys.clear(); }); }); },
      onPaywallTriggered: () async {
        _triggerPaywall('card_detail_limit');
        return true;
      },
    );
  }
}

class SafeCardImage extends StatelessWidget {
  final String urlOrBase64;
  final BoxFit fit;

  const SafeCardImage({
    super.key, 
    required this.urlOrBase64,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (urlOrBase64.isEmpty) {
      return Container(color: Colors.grey[300], child: const Icon(Icons.image_not_supported, color: Colors.grey));
    }

    if (urlOrBase64.startsWith('#')) {
      try {
        final hexColor = urlOrBase64.replaceAll('#', '');
        final colorInt = int.parse(hexColor, radix: 16);
        final finalColor = hexColor.length == 6 ? colorInt + 0xFF000000 : colorInt;
        return Container(
          width: double.infinity, height: double.infinity, color: Color(finalColor),
          child: const Center(child: Icon(Icons.style, color: Colors.white70, size: 30)),
        );
      } catch (_) {
        return Container(color: Colors.grey[300]);
      }
    }

    if (urlOrBase64.startsWith('http')) {
      return Image.network(
        urlOrBase64, width: double.infinity, height: double.infinity, fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey)),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent));
        },
      );
    }

    if (urlOrBase64.startsWith('data:image')) {
      try {
        String cleanBase64 = urlOrBase64.contains(',') ? urlOrBase64.split(',')[1] : urlOrBase64;
        cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(cleanBase64);
        return Image.memory(
          bytes, width: double.infinity, height: double.infinity, fit: fit,
          errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey)),
        );
      } catch (_) {
        return Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey));
      }
    }

    try {
      final file = File(urlOrBase64);
      if (file.existsSync()) {
        return Image.file(
          file, width: double.infinity, height: double.infinity, fit: fit,
          errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey)),
        );
      }
    } catch (_) {}

    return Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey));
  }
}

class _FlipCardItem extends StatefulWidget {
  final CardModel card;
  final bool isSelected;
  final bool isSelectMode;
  final bool showAllDuplicates;
  final VoidCallback onTap;

  const _FlipCardItem({
    required this.card,
    required this.isSelected,
    required this.isSelectMode,
    required this.showAllDuplicates,
    required this.onTap,
  });

  @override
  State<_FlipCardItem> createState() => _FlipCardItemState();
}

class _FlipCardItemState extends State<_FlipCardItem> {
  bool _isFront = true;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final isSelected = widget.isSelected;
    final isFavorite = card.isFavorite == true;

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: () {
        if (card.backUrl.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('このカードには裏面が登録されていません ℹ️'),
              duration: Duration(seconds: 1),
            ),
          );
          return;
        }
        setState(() {
          _isFront = !_isFront;
        });
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _isFront ? 0 : pi),
        duration: const Duration(milliseconds: 400),
        builder: (context, angle, child) {
          final isShowingFrontSide = angle < pi / 2;

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002) 
              ..rotateY(angle),
            alignment: Alignment.center,
            child: Transform(
              transform: isShowingFrontSide ? Matrix4.identity() : Matrix4.rotationY(pi),
              alignment: Alignment.center,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8), 
                  border: Border.all(
                    color: isSelected ? Colors.pinkAccent : Colors.grey.withOpacity(0.3), 
                    width: isSelected ? 3.0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ), 
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6), 
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SafeCardImage(
                          urlOrBase64: isShowingFrontSide ? card.thumbnailFrontUrl : card.backUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (!widget.showAllDuplicates && card.count > 1 && isShowingFrontSide) 
                        Positioned(top: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(10)), child: Text('${card.count}枚', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                      if (isFavorite && !widget.isSelectMode && isShowingFrontSide) 
                        Positioned(top: 4, left: 4, child: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 18)),
                      if (widget.isSelectMode && isShowingFrontSide) 
                        Positioned(top: 4, left: 4, child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? Colors.pinkAccent : Colors.white, size: 22)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
