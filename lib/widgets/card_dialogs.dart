import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../models/card_model.dart';
import '../models/binder_model.dart';
import '../services/firebase_service.dart';

/// 画像のクロップサイズ（比率）を選択するダイアログ
Future<CropAspectRatio?> _showAspectRatioPickerDialog(BuildContext context) async {
  return showDialog<CropAspectRatio?>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('画像サイズの選択', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.crop_portrait, color: Colors.pinkAccent),
            title: const Text('レギュラーカード'),
            subtitle: const Text('63:88'),
            onTap: () => Navigator.pop(dialogCtx, const CropAspectRatio(ratioX: 63, ratioY: 88)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.style_outlined, color: Colors.pinkAccent),
            title: const Text('フォトカード・チェキ'),
            subtitle: const Text('54：86'),
            onTap: () => Navigator.pop(dialogCtx, const CropAspectRatio(ratioX: 54, ratioY: 86)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.crop_square, color: Colors.pinkAccent),
            title: const Text('正方形'),
            subtitle: const Text('1 : 1'),
            onTap: () => Navigator.pop(dialogCtx, const CropAspectRatio(ratioX: 1, ratioY: 1)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, null),
          child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
        ),
      ],
    ),
  );
}

/// 画像表示用共通コンポーネント
class CardImage extends StatefulWidget {
  final String urlOrBase64;
  const CardImage({super.key, required this.urlOrBase64});

  @override
  State<CardImage> createState() => _CardImageState();
}

class _CardImageState extends State<CardImage> {
  late String _displayUrl;

  @override
  void initState() {
    super.initState();
    _displayUrl = widget.urlOrBase64;
  }

  @override
  void didUpdateWidget(covariant CardImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlOrBase64 != widget.urlOrBase64) {
      setState(() {
        _displayUrl = widget.urlOrBase64;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayUrl.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    // 単色カラー表示の判定（16進数文字を正確にパースするように修正）
    if (_displayUrl.startsWith('color:')) {
      final hexStr = _displayUrl
          .replaceFirst('color:', '')
          .replaceAll('0x', '')
          .replaceAll('0X', '')
          .replaceAll('#', '');
      final colorInt = int.tryParse(hexStr, radix: 16) ?? 0xFFE0E0E0;
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Color(colorInt),
      );
    }
    
    // ローカルファイル（/ または file://）の判定
    if (!kIsWeb && (_displayUrl.startsWith('/') || _displayUrl.startsWith('file://'))) {
      final cleanPath = _displayUrl.startsWith('file://')
          ? Uri.parse(_displayUrl).toFilePath()
          : _displayUrl;
      return Image.file(
        File(cleanPath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    // Base64判定
    if (!_displayUrl.startsWith('http')) {
      try {
        return Image.memory(
          base64Decode(_displayUrl),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      } catch (e) {
        return Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      }
    }

    // ネットワーク画像表示
    return Image.network(
      _displayUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
            strokeWidth: 2,
            color: Colors.pinkAccent[100],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

class CardDialogs {
  // 1. お問い合わせダイアログ
  static void showFeedbackDialog(
    BuildContext context, {
    required String uid,
    required Future<void> Function(String title, String content, String email) onSend,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _FeedbackDialog(uid: uid, onSend: onSend),
    );
  }

  // 2. 課金制限ダイアログ (戻り値をFuture<bool?>化)
  static Future<bool?> showPaywallDialog(
    BuildContext context, {
    required int maxFreeCardCount,
    required VoidCallback onPremiumPurchased,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // 決済中に背景タップで閉じられないようにガード
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber, size: 50),
            SizedBox(height: 10),
            Text('プレミアムプランのご案内', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber[200]!)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🌟 プレミアムプラン特典:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
                  SizedBox(height: 6),
                  Text('・カード登録枚数が最大3,000枚！', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('・バインダーの表紙をギャラリーから変更可能', style: TextStyle(fontSize: 12)),
                  Text('・広告の完全非表示', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text('月額 130円', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.pinkAccent)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false), // 購入キャンセル時はfalse
            child: const Text('戻る', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              onPremiumPurchased();
              Navigator.pop(dialogCtx, true); // 購入成功時はtrue
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 プレミアムプランを購入しました！（テスト適用）')));
              }
            },
            child: const Text('プランに加入する'),
          ),
        ],
      ),
    );
  }

  // 3. 並べ替え順設定シート
  static void showSortOrderBottomSheet(
    BuildContext context, {
    required String currentSortOrder,
    required ValueChanged<String> onSortOrderChanged,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('並べ替え順を変更', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            ListTile(
              leading: const Icon(Icons.back_hand_outlined, color: Colors.pinkAccent),
              title: const Text('カスタム（ドラッグで自由に並べ替え）'),
              trailing: currentSortOrder == 'custom' ? const Icon(Icons.check, color: Colors.pinkAccent) : null,
              onTap: () { onSortOrderChanged('custom'); Navigator.pop(sheetCtx); },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded, color: Colors.blue),
              title: const Text('登録日が新しい順'),
              trailing: currentSortOrder == 'newest' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { onSortOrderChanged('newest'); Navigator.pop(sheetCtx); },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded, color: Colors.amber),
              title: const Text('登録日が古い順'),
              trailing: currentSortOrder == 'oldest' ? const Icon(Icons.check, color: Colors.amber) : null,
              onTap: () { onSortOrderChanged('oldest'); Navigator.pop(sheetCtx); },
            ),
          ],
        ),
      ),
    );
  }

  // 4. クイック追加メニュー
  static void showAddMenu(
    BuildContext context, {
    required String? openedBinderName,
    required VoidCallback onAddBinder,
    required VoidCallback onAddRefill,
    required VoidCallback onAddCard,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.folder_open, color: Colors.amber), title: const Text('新しいバインダーを追加'), onTap: () { Navigator.pop(sheetCtx); onAddBinder(); }),
            if (openedBinderName != null)
              ListTile(leading: const Icon(Icons.layers_rounded, color: Colors.pinkAccent), title: const Text('新しいリフィルを追加'), onTap: () { Navigator.pop(sheetCtx); onAddRefill(); }),
            ListTile(leading: const Icon(Icons.add_photo_alternate, color: Colors.blueAccent), title: const Text('新しいカードを追加'), onTap: () { Navigator.pop(sheetCtx); onAddCard(); }),
          ],
        ),
      ),
    );
  }

  // 5. 新規カード追加フォーム
  static void showAddCardForm(
    BuildContext context, {
    required String? openedBinderName,
    required String? openedRefillName,
    required List<BinderModel> binders,
    required Map<String, List<String>> refills,
    required Map<String, dynamic>? lastRegisteredData,
    required bool isPremiumUser,
    required int totalActiveCardCount,
    required int maxFreeCardCount,
    required Function(CardModel newCard, Map<String, dynamic> lastData) onCardAdded,
    required Function(BuildContext dialogContext, Function(String) onCreated) showAddBinderDialog, 
    required Function(BuildContext dialogContext, String binderName, Function(String) onCreated) showAddRefillDialog, 
    required Future<bool> Function() onPaywallTriggered,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _AddCardForm(
        openedBinderName: openedBinderName,
        openedRefillName: openedRefillName,
        binders: binders,
        refills: refills,
        lastRegisteredData: lastRegisteredData,
        isPremiumUser: isPremiumUser,
        totalActiveCardCount: totalActiveCardCount,
        maxFreeCardCount: maxFreeCardCount,
        onCardAdded: onCardAdded,
        showAddBinderDialog: showAddBinderDialog,
        showAddRefillDialog: showAddRefillDialog,
        onPaywallTriggered: onPaywallTriggered,
      ),
    );
  }

  // 6. 新規バインダー作成・編集ダイアログ
  static void showAddBinderDialog(
    BuildContext context, {
    required List<String> presetCovers,
    required bool isPremiumUser,
    required Function(String name, String coverUrl) onCreated,
    required List<String> existingBinderNames, 
    String? initialName,
    String? initialCoverUrl,
    bool isEditing = false,
    Future<bool> Function()? onPaywallTriggered,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _AddBinderDialog(
        presetCovers: presetCovers,
        isPremiumUser: isPremiumUser,
        onCreated: onCreated,
        existingBinderNames: existingBinderNames, 
        initialName: initialName,
        initialCoverUrl: initialCoverUrl,
        isEditing: isEditing,
        onPaywallTriggered: onPaywallTriggered,
      ),
    );
  }

  // 7. 新規リフィル作成ダイアログ
  static void showAddRefillDialog(BuildContext context, {required String binderName, required Function(String refillName) onCreated}) {
    String newRefillName = '';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('「$binderName」にリフィル追加'),
        content: TextField(decoration: const InputDecoration(hintText: 'リフィル名を入力 (例: 1st シングル)'), onChanged: (val) => newRefillName = val),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () {
            if (newRefillName.isNotEmpty) { 
              if (newRefillName == '✨ すべてのカード' || newRefillName == BinderModel.favoriteRefillName) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('そのリフィル名はシステムで使用されているため作成できません。')),
                );
              } else {
                onCreated(newRefillName); 
              }
            }
            Navigator.pop(dialogCtx);
          }, child: const Text('追加')),
        ],
      ),
    );
  }

  // 8. バインダー削除確認ダイアログ
  static void showDeleteBinderDialog(BuildContext context, {required BinderModel binder, required int totalCards, required VoidCallback onDelete}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('バインダー「${binder.name}」の削除'),
        content: totalCards > 0 ? Text('このバインダー内には現在 $totalCards 枚のカードが存在するため削除できません。') : const Text('このバインダーを完全に削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          if (totalCards == 0)
            TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('削除する', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 9. リフィル削除確認ダイアログ
  static void showDeleteRefillDialog(BuildContext context, {required String refillName, required int totalCards, required VoidCallback onDelete}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('リフィル「$refillName」の削除'),
        content: totalCards > 0 ? Text('このリフィル内には現在 $totalCards 種のカードが存在するため削除できません。') : const Text('このリフィルを完全に削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          if (totalCards == 0)
            TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('削除する', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 10. ページ表示枠数設定ダイアログ
  static void showSettingsDialog(BuildContext context, {required double cardsPerPage, required ValueChanged<double> onChanged}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (builderCtx, setDialogState) => AlertDialog(
          title: const Text('1ページの表示設定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('上限: ${cardsPerPage.round()} 枠', style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: cardsPerPage, min: 4, max: 15, divisions: 11, activeColor: Colors.pinkAccent, 
                onChanged: (val) { setDialogState(() => cardsPerPage = val); onChanged(val); }
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(builderCtx), child: const Text('閉じる'))],
        ),
      ),
    );
  }

  // 11. カード詳細ダイアログ
  static void showCardDetailDialog(
    BuildContext context, {
    required CardModel card,
    required bool isFromTrash,
    required bool isPremiumUser,
    required int totalActiveCardCount,
    required int maxFreeCardCount,
    required VoidCallback onFavoriteToggled,
    required Function(CardModel updatedCard) onCardUpdated,
    required VoidCallback onDeletePressed,
    required Function(CardModel currentCard) onMovePressed, 
    required VoidCallback onRestorePressed,
    required Future<bool> Function() onPaywallTriggered,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _CardDetailDialog(
        card: card,
        isFromTrash: isFromTrash,
        isPremiumUser: isPremiumUser,
        totalActiveCardCount: totalActiveCardCount,
        maxFreeCardCount: maxFreeCardCount,
        onFavoriteToggled: onFavoriteToggled,
        onCardUpdated: onCardUpdated,
        onDeletePressed: onDeletePressed,
        onMovePressed: onMovePressed,
        onRestorePressed: onRestorePressed,
        onPaywallTriggered: onPaywallTriggered,
      ),
    );
  }

  // 12. 単一カードゴミ箱移動確認
  static void showDeleteConfirmDialog(BuildContext context, {required VoidCallback onDelete, int count = 1}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('カードの移動'), 
        content: Text(count > 1 ? 'このカード（$count枚）をゴミ箱に移動しますか？' : 'このカードをゴミ箱に移動しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('ゴミ箱へ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 13. 単一カード復元確認
  static void showRestoreConfirmDialog(BuildContext context, {required VoidCallback onRestore, int count = 1}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('復元の確認'), 
        content: Text(count > 1 ? 'このカード（$count枚）を復元しますか？' : 'このカードを復元しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onRestore(); Navigator.pop(dialogCtx); }, child: const Text('復元する', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // 14. 単一カード完全消去確認
  static void showPermanentlyDeleteDialog(BuildContext context, {required VoidCallback onDelete, int count = 1}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('完全に消去'), 
        content: Text(count > 1 ? 'このカード（$count枚）を完全に削除しますか？この操作は戻せません。' : 'このカードを完全に削除しますか？この操作は戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('完全に消す', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 15. まとめて復元確認
  static void showBulkRestoreConfirmDialog(BuildContext context, {required int count, required VoidCallback onRestore}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('まとめて復元'), content: Text('選択された $count 枚のカードをすべて復元しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onRestore(); Navigator.pop(dialogCtx); }, child: const Text('復元する', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );
  }

  // 16. 一括完全消去確認
  static void showBulkPermanentDeleteConfirmDialog(BuildContext context, {required int count, required VoidCallback onDelete}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('一括完全消去'), content: Text('選択された $count 枚のカードを【完全に消去】しますか？\n（この操作は元に戻せません）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('完全に消す', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 17. まとめてゴミ箱移動確認
  static void showBulkDeleteConfirmDialog(BuildContext context, {required int count, required String unit, required VoidCallback onDelete}) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('まとめてゴミ箱へ移動'), content: Text('選択された $count $unit のカードをゴミ箱に移動しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('キャンセル')),
          TextButton(onPressed: () { onDelete(); Navigator.pop(dialogCtx); }, child: const Text('移動する', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // 18. 一括移動先指定ダイアログ
  static void showBulkMoveDialog(
    BuildContext context, {
    required int count, required String unit,
    required List<BinderModel> binders, required Map<String, List<String>> refills,
    required Function(String selectedBinder, String selectedRefill) onMove,
    required Function(BuildContext dialogContext, Function(String) onCreated) showAddBinderDialog, 
    required Function(BuildContext dialogContext, String binderName, Function(String) onCreated) showAddRefillDialog, 
  }) {
    final uniqueBinders = <String, BinderModel>{};
    for (var b in binders) {
      uniqueBinders[b.name] = b;
    }
    final localBinders = uniqueBinders.values.toList();
    final localRefills = Map<String, List<String>>.from(refills);

    if (localBinders.isEmpty) {
      localBinders.add(BinderModel(name: 'マイコレクション', coverUrl: ''));
    }

    String selectedBinder = localBinders.first.name;
    List<String> getAvailableRefills(String bName) {
      final list = (localRefills[bName] ?? []).where((r) => r != '✨ すべてのカード' && r != BinderModel.favoriteRefillName).toList();
      return list.toSet().toList(); 
    }
    List<String> currentRefillOptions = getAvailableRefills(selectedBinder);
    String selectedRefill = currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (builderCtx, setDialogState) {
          final refillOptions = getAvailableRefills(selectedBinder);
          return AlertDialog(
            title: Text('$count $unit のカードを一括移動', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('移動先バインダー', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedBinder, isExpanded: true,
                  items: [
                    ...localBinders.map((b) => DropdownMenuItem<String>(value: b.name, child: Text(b.name))),
                    const DropdownMenuItem<String>(value: '__NEW_BINDER__', child: Text('➕ 新しいバインダーを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (val) {
                    if (val == '__NEW_BINDER__') {
                      showAddBinderDialog(builderCtx, (newBinderName) {
                        setDialogState(() {
                          if (!localBinders.any((b) => b.name == newBinderName)) {
                            localBinders.add(BinderModel(name: newBinderName, coverUrl: ''));
                          }
                          selectedBinder = newBinderName; 
                          currentRefillOptions = getAvailableRefills(selectedBinder);
                          selectedRefill = currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト';
                        });
                      });
                    } else if (val != null) {
                      setDialogState(() {
                        selectedBinder = val; 
                        currentRefillOptions = getAvailableRefills(selectedBinder);
                        selectedRefill = currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text('移動先リフィル', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: refillOptions.contains(selectedRefill) ? selectedRefill : (refillOptions.isNotEmpty ? refillOptions.first : null),
                  isExpanded: true,
                  items: [
                    ...refillOptions.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))),
                    const DropdownMenuItem<String>(value: '__NEW_REFILL__', child: Text('➕ 新しいリフィルを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (val) {
                    if (val == '__NEW_REFILL__') {
                      showAddRefillDialog(builderCtx, selectedBinder, (newRefillName) {
                        setDialogState(() { 
                          if (localRefills[selectedBinder] == null) {
                            localRefills[selectedBinder] = [];
                          }
                          if (!localRefills[selectedBinder]!.contains(newRefillName)) {
                            localRefills[selectedBinder]!.add(newRefillName);
                          }
                          currentRefillOptions = getAvailableRefills(selectedBinder); 
                          selectedRefill = newRefillName; 
                        });
                      });
                    } else if (val != null) {
                      setDialogState(() => selectedRefill = val);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(builderCtx), child: const Text('キャンセル')),
              TextButton(
                onPressed: () { 
                  Navigator.of(builderCtx).pop(); 
                  onMove(selectedBinder, selectedRefill); 
                }, 
                child: const Text('移動する', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))
              ),
            ],
          );
        },
      ),
    );
  }

  // 19. 単一カードの別リフィル移動指定ダイアログ
  static void showMoveCardDialog(
    BuildContext context, {
    required CardModel masterCard,
    required List<BinderModel> binders, required Map<String, List<String>> refills,
    required Function(CardModel updatedCard, String selectedBinder, String selectedRefill) onMove,
    required Function(BuildContext dialogContext, Function(String) onCreated) showAddBinderDialog, 
    required Function(BuildContext dialogContext, String binderName, Function(String) onCreated) showAddRefillDialog, 
  }) {
    final uniqueBinders = <String, BinderModel>{};
    for (var b in binders) {
      uniqueBinders[b.name] = b;
    }
    final localBinders = uniqueBinders.values.toList();
    final localRefills = Map<String, List<String>>.from(refills);

    if (localBinders.isEmpty) {
      localBinders.add(BinderModel(name: 'マイコレクション', coverUrl: ''));
    }

    String initialBinder = localBinders.first.name;
    for (var b in localBinders) {
      final list = localRefills[b.name] ?? [];
      if (list.contains(masterCard.refill)) { initialBinder = b.name; break; }
    }
    String selectedBinder = initialBinder;
    
    List<String> getAvailableRefills(String bName) {
      final list = (localRefills[bName] ?? []).where((r) => r != '✨ すべてのカード' && r != BinderModel.favoriteRefillName).toList();
      return list.toSet().toList(); 
    }
    
    List<String> currentRefillOptions = getAvailableRefills(selectedBinder);
    String selectedRefill = currentRefillOptions.contains(masterCard.refill) ? masterCard.refill : (currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (builderCtx, setDialogState) {
          final refillOptions = getAvailableRefills(selectedBinder);
          return AlertDialog(
            title: const Text('カードを別のリフィルへ移動', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('移動先バインダー', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedBinder, isExpanded: true,
                  items: [
                    ...localBinders.map((b) => DropdownMenuItem<String>(value: b.name, child: Text(b.name))),
                    const DropdownMenuItem<String>(value: '__NEW_BINDER__', child: Text('➕ 新しいバインダーを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (val) {
                    if (val == '__NEW_BINDER__') {
                      showAddBinderDialog(builderCtx, (newBinderName) {
                        setDialogState(() {
                          if (!localBinders.any((b) => b.name == newBinderName)) {
                            localBinders.add(BinderModel(name: newBinderName, coverUrl: ''));
                          }
                          selectedBinder = newBinderName; 
                          currentRefillOptions = getAvailableRefills(selectedBinder);
                          selectedRefill = currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト';
                        });
                      });
                    } else if (val != null) {
                      setDialogState(() {
                        selectedBinder = val; 
                        currentRefillOptions = getAvailableRefills(selectedBinder);
                        selectedRefill = currentRefillOptions.isNotEmpty ? currentRefillOptions.first : 'デフォルト';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text('移動先リフィル', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: refillOptions.contains(selectedRefill) ? selectedRefill : (refillOptions.isNotEmpty ? refillOptions.first : null),
                  isExpanded: true,
                  items: [
                    ...refillOptions.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))),
                    const DropdownMenuItem<String>(value: '__NEW_REFILL__', child: Text('➕ 新しいリフィルを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (val) {
                    if (val == '__NEW_REFILL__') {
                      showAddRefillDialog(builderCtx, selectedBinder, (newRefillName) {
                        setDialogState(() { 
                          if (localRefills[selectedBinder] == null) {
                            localRefills[selectedBinder] = [];
                          }
                          if (!localRefills[selectedBinder]!.contains(newRefillName)) {
                            localRefills[selectedBinder]!.add(newRefillName);
                          }
                          currentRefillOptions = getAvailableRefills(selectedBinder); 
                          selectedRefill = newRefillName; 
                        });
                      });
                    } else if (val != null) {
                      setDialogState(() => selectedRefill = val);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () { 
                  final updatedCard = CardModel(
                    id: masterCard.id,
                    refill: selectedRefill,
                    count: masterCard.count,
                    frontUrl: masterCard.frontUrl,
                    thumbnailFrontUrl: masterCard.thumbnailFrontUrl,
                    backUrl: masterCard.backUrl,
                    tags: masterCard.tags,
                    memo: masterCard.memo,
                    date: masterCard.date,
                    isDeleted: masterCard.isDeleted,
                    isFavorite: masterCard.isFavorite,
                    timestamp: masterCard.timestamp,
                  );

                  Navigator.of(builderCtx).pop(); 
                  Navigator.of(context).pop();    

                  onMove(updatedCard, selectedBinder, selectedRefill); 
                }, 
                child: const Text('移動する', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// 内部専用ウィジェット
// ==========================================

class _FeedbackDialog extends StatefulWidget {
  final String uid;
  final Future<void> Function(String title, String content, String email) onSend;

  const _FeedbackDialog({
    required this.uid,
    required this.onSend,
  });

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _emailController;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: Colors.pinkAccent),
          SizedBox(width: 8),
          Text('お問い合わせ / ご要望', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              enabled: !_isSending,
              decoration: const InputDecoration(labelText: '件名', labelStyle: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              enabled: !_isSending,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '返信先のメールアドレス (任意)',
                labelStyle: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contentController,
              maxLines: 4,
              enabled: !_isSending,
              decoration: const InputDecoration(labelText: '内容を入力してください', labelStyle: TextStyle(fontSize: 13)),
            ),
            if (_isSending) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.pinkAccent), 
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
          onPressed: _isSending ? null : () async {
            if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('件名と内容を入力してください。')),
              );
              return;
            }
            setState(() => _isSending = true);
            try {
              await widget.onSend(
                _titleController.text,
                _contentController.text,
                _emailController.text.trim(),
              );
              if (mounted) {
                Navigator.pop(context); 
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('お問い合わせを送信しました。ありがとうございました！📬')),
                );
              }
            } catch (e) {
              if (mounted) {
                setState(() => _isSending = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
              }
            }
          },
          child: const Text('送信'),
        ),
      ],
    );
  }
}

class _AddCardForm extends StatefulWidget {
  final String? openedBinderName;
  final String? openedRefillName;
  final List<BinderModel> binders;
  final Map<String, List<String>> refills;
  final Map<String, dynamic>? lastRegisteredData;
  final bool isPremiumUser; 
  final int totalActiveCardCount; 
  final int maxFreeCardCount; 
  final Function(CardModel newCard, Map<String, dynamic> lastData) onCardAdded;
  final Function(BuildContext dialogContext, Function(String) onCreated) showAddBinderDialog; 
  final Function(BuildContext dialogContext, String binderName, Function(String) onCreated) showAddRefillDialog;
  final Future<bool> Function() onPaywallTriggered;

  const _AddCardForm({
    required this.openedBinderName,
    required this.openedRefillName,
    required this.binders,
    required this.refills,
    required this.lastRegisteredData,
    required this.isPremiumUser, 
    required this.totalActiveCardCount, 
    required this.maxFreeCardCount, 
    required this.onCardAdded,
    required this.showAddBinderDialog,
    required this.showAddRefillDialog,
    required this.onPaywallTriggered, 
  });

  @override
  State<_AddCardForm> createState() => _AddCardFormState();
}

class _AddCardFormState extends State<_AddCardForm> {
  late String _selectedBinder;
  late List<String> _currentRefillOptions;
  late String _selectedRefill;

  late List<BinderModel> _localBinders;
  late Map<String, List<String>> _localRefills;

  late final TextEditingController _memoController;
  late final TextEditingController _tagController;
  late final TextEditingController _dateController;
  bool _noDate = false; 
  int _count = 1;
  
  String _imagePathOrUrl = '';
  String _backImagePathOrUrl = ''; 
  bool _isUploading = false;

  List<String> _getAvailableRefills(String bName) {
    final list = (_localRefills[bName] ?? []).where((r) => r != '✨ すべてのカード' && r != BinderModel.favoriteRefillName).toList();
    return list.toSet().toList(); 
  }

  @override
  void initState() {
    super.initState();
    final uniqueBinders = <String, BinderModel>{};
    for (var b in widget.binders) {
      uniqueBinders[b.name] = b;
    }
    _localBinders = uniqueBinders.values.toList();
    _localRefills = Map<String, List<String>>.from(widget.refills);

    if (_localBinders.isEmpty) {
      _localBinders.add(BinderModel(name: 'マイコレクション', coverUrl: ''));
    }

    _selectedBinder = widget.openedBinderName ?? _localBinders.first.name;
    _currentRefillOptions = _getAvailableRefills(_selectedBinder);
    _selectedRefill = _currentRefillOptions.isNotEmpty ? _currentRefillOptions.first : 'デフォルト';

    if (widget.openedRefillName != null && 
        widget.openedRefillName != '✨ すべてのカード' && 
        widget.openedRefillName != BinderModel.favoriteRefillName) {
      _selectedRefill = widget.openedRefillName!;
    }

    _memoController = TextEditingController();
    _tagController = TextEditingController();
    _dateController = TextEditingController(text: '2026年${DateTime.now().month.toString().padLeft(2, '0')}月');
  }

  @override
  void dispose() {
    _memoController.dispose();
    _tagController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, {required bool isFront}) async {
    final picker = ImagePicker();
    try {
      final pickedImage = await picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1600);
      if (pickedImage != null && mounted) {
        final selectedAspectRatio = await _showAspectRatioPickerDialog(context);
        if (selectedAspectRatio == null) return; // キャンセル時

        final bool isOriginal = selectedAspectRatio.ratioX == -1;
        final CropAspectRatio? cropAspectRatio = isOriginal ? null : selectedAspectRatio;

        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedImage.path,
          aspectRatio: cropAspectRatio,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 85, 
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isFront ? '表面のトリミング' : '裏面のトリミング',
              toolbarColor: Colors.pinkAccent,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: isOriginal ? CropAspectRatioPreset.original : CropAspectRatioPreset.square,
              lockAspectRatio: !isOriginal,
            ),
            IOSUiSettings(
              title: isFront ? '表面のトリミング' : '裏面のトリミング',
              aspectRatioLockEnabled: !isOriginal,
              resetAspectRatioEnabled: isOriginal,
            ),
          ],
        );

        if (croppedFile != null) {
          setState(() { 
            if (isFront) {
              _imagePathOrUrl = croppedFile.path;
            } else {
              _backImagePathOrUrl = croppedFile.path;
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像の取得またはトリミングに失敗しました。')));
      }
    }
  }

  void _showImagePickerModal(BuildContext context, {required bool isFront}) {
    showModalBottomSheet(
      context: context,
      builder: (pickerCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue), 
              title: const Text('カメラで撮影'), 
              onTap: () { Navigator.pop(pickerCtx); _pickImage(ImageSource.camera, isFront: isFront); }
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.pink), 
              title: const Text('ギャラリーから選択'), 
              onTap: () { Navigator.pop(pickerCtx); _pickImage(ImageSource.gallery, isFront: isFront); }
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('カードをコレクションに追加', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                if (widget.lastRegisteredData != null)
                  TextButton.icon(
                    icon: const Icon(Icons.history, size: 16, color: Colors.pinkAccent),
                    label: const Text('前回と同じにする', style: TextStyle(fontSize: 12, color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                    onPressed: _isUploading ? null : () {
                      setState(() {
                        final lastBinder = widget.lastRegisteredData!['binder'];
                        if (!_localBinders.any((b) => b.name == lastBinder)) {
                          _localBinders.add(BinderModel(name: lastBinder, coverUrl: ''));
                        }
                        _selectedBinder = lastBinder;

                        final lastRefill = widget.lastRegisteredData!['refill'];
                        if (_localRefills[_selectedBinder] == null) {
                          _localRefills[_selectedBinder] = [];
                        }
                        if (!_localRefills[_selectedBinder]!.contains(lastRefill)) {
                          _localRefills[_selectedBinder]!.add(lastRefill);
                        }

                        _currentRefillOptions = _getAvailableRefills(_selectedBinder);
                        if (_currentRefillOptions.contains(lastRefill)) {
                          _selectedRefill = lastRefill;
                        } else {
                          _selectedRefill = _currentRefillOptions.isNotEmpty ? _currentRefillOptions.first : 'デフォルト';
                        }
                        _memoController.text = widget.lastRegisteredData!['memo'] ?? '';
                        _tagController.text = widget.lastRegisteredData!['tagsRaw'] ?? '';
                        _dateController.text = widget.lastRegisteredData!['date'] ?? '';
                        _noDate = _dateController.text.isEmpty; 
                        _count = widget.lastRegisteredData!['count'] ?? 1;
                        _imagePathOrUrl = '';
                        _backImagePathOrUrl = ''; 
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 15),
            
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      const Text('表面 (必須)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _isUploading ? null : () => _showImagePickerModal(context, isFront: true),
                        child: Container(
                          height: 150, width: 105, 
                          decoration: BoxDecoration(
                            color: Colors.grey[100], borderRadius: BorderRadius.circular(10), 
                            border: Border.all(color: _imagePathOrUrl.isNotEmpty ? Colors.grey[300]! : Colors.pinkAccent.withOpacity(0.5), width: 2), 
                          ), 
                          child: _imagePathOrUrl.isNotEmpty 
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CardImage(urlOrBase64: _imagePathOrUrl),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined, color: Colors.pinkAccent, size: 32),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  
                  Column(
                    children: [
                      const Text('裏面 (任意)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _backImagePathOrUrl.isEmpty
                          ? GestureDetector(
                              onTap: _isUploading ? null : () => _showImagePickerModal(context, isFront: false),
                              child: Container(
                                height: 150, width: 105, 
                                decoration: BoxDecoration(
                                  color: Colors.grey[100], borderRadius: BorderRadius.circular(10), 
                                  border: Border.all(color: Colors.grey[300]!, width: 2, style: BorderStyle.solid), 
                                ), 
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, color: Colors.grey, size: 24),
                                    SizedBox(height: 4),
                                    Text('裏面を追加', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            )
                          : Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: _isUploading ? null : () => _showImagePickerModal(context, isFront: false),
                                  child: Container(
                                    height: 150, width: 105, 
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100], borderRadius: BorderRadius.circular(10), 
                                      border: Border.all(color: Colors.grey[300]!, width: 2), 
                                    ), 
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CardImage(urlOrBase64: _backImagePathOrUrl),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -6, right: -6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _backImagePathOrUrl = ''),
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.redAccent,
                                      child: Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 15),
            const Text('保存先バインダー', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _selectedBinder, isExpanded: true,
              items: [
                ..._localBinders.map((b) => DropdownMenuItem<String>(value: b.name, child: Text(b.name))),
                const DropdownMenuItem<String>(value: '__NEW_BINDER__', child: Text('➕ 新しいバインダーを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
              ],
              onChanged: _isUploading ? null : (val) {
                if (val == '__NEW_BINDER__') {
                  widget.showAddBinderDialog(context, (newBinderName) { 
                    setState(() {
                      if (!_localBinders.any((b) => b.name == newBinderName)) {
                        _localBinders.add(BinderModel(name: newBinderName, coverUrl: ''));
                      }
                      _selectedBinder = newBinderName;
                      _currentRefillOptions = _getAvailableRefills(_selectedBinder);
                      _selectedRefill = _currentRefillOptions.isNotEmpty ? _currentRefillOptions.first : 'デフォルト';
                    });
                  });
                } else if (val != null) {
                  setState(() {
                    _selectedBinder = val;
                    _currentRefillOptions = _getAvailableRefills(_selectedBinder);
                    _selectedRefill = _currentRefillOptions.isNotEmpty ? _currentRefillOptions.first : 'デフォルト';
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            const Text('保存先リフィル', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: (_currentRefillOptions.contains(_selectedRefill)) ? _selectedRefill : (_currentRefillOptions.isNotEmpty ? _currentRefillOptions.first : null),
              isExpanded: true,
              items: [
                ..._currentRefillOptions.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))),
                const DropdownMenuItem<String>(value: '__NEW_REFILL__', child: Text('➕ 新しいリフィルを作成...', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
              ],
              onChanged: _isUploading ? null : (val) {
                if (val == '__NEW_REFILL__') {
                  widget.showAddRefillDialog(context, _selectedBinder, (newRefillName) { 
                    setState(() {
                      if (_localRefills[_selectedBinder] == null) {
                        _localRefills[_selectedBinder] = [];
                      }
                      if (!_localRefills[_selectedBinder]!.contains(newRefillName)) {
                        _localRefills[_selectedBinder]!.add(newRefillName);
                      }
                      _currentRefillOptions = _getAvailableRefills(_selectedBinder);
                      _selectedRefill = newRefillName;
                    });
                  });
                } else if (val != null) {
                  setState(() => _selectedRefill = val);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: _memoController, enabled: !_isUploading, decoration: const InputDecoration(labelText: 'メモ (例: 〇〇会場にて)', labelStyle: TextStyle(fontSize: 13))),
            const SizedBox(height: 10),
            TextField(controller: _tagController, enabled: !_isUploading, decoration: const InputDecoration(labelText: 'タグ (コンマ区切り: 自引き,限定)', labelStyle: TextStyle(fontSize: 13))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    enabled: !_noDate && !_isUploading,
                    decoration: InputDecoration(
                      labelText: '入手日', 
                      labelStyle: const TextStyle(fontSize: 13),
                      hintText: _noDate ? '選択しない' : '',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isUploading ? null : () {
                    setState(() {
                      _noDate = !_noDate;
                      if (_noDate) {
                        _dateController.text = '';
                      } else {
                        _dateController.text = '2026年${DateTime.now().month.toString().padLeft(2, '0')}月';
                      }
                    });
                  },
                  child: Text(_noDate ? '日付を設定' : '選択しない', style: const TextStyle(color: Colors.pinkAccent)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('枚数: '),
                IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.black54), onPressed: _isUploading ? null : () => setState(() => _count = max(1, _count - 1))),
                Text('$_count 枚', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.black54), onPressed: _isUploading ? null : () => setState(() => _count++)),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _isUploading ? null : () async {
                  if (_imagePathOrUrl.isEmpty) {
                    showDialog(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('登録エラー', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: const Text('表面の画像は必須です。\n画像を選択してからもう一度お試しください。⚠️'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            child: const Text('OK', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  // ユーザーの課金ステータスを可変変数で追う
                  bool currentPremiumStatus = widget.isPremiumUser;

                  // 無料上限チェック
                  if (!currentPremiumStatus && (widget.totalActiveCardCount + _count) > widget.maxFreeCardCount) {
                    // ペイウォール表示をawaitして、購入されたかどうかを待つ
                    final purchased = await widget.onPaywallTriggered(); 
                    if (purchased != true) {
                      // 課金されずに戻ってきた場合は処理を中断（入力フォームの状態は維持される）
                      return; 
                    }
                    currentPremiumStatus = true;
                  }

                  // プレミアム会員含め上限3,000枚のチェックを追加
                  if (widget.totalActiveCardCount + _count > 3000) {
                    showDialog(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('上限エラー', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: const Text('カードの最大登録枚数（3,000枚）を超えるため追加できません。⚠️'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            child: const Text('OK', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  String imgPath = _imagePathOrUrl;
                  String thumbImgPath = _imagePathOrUrl;
                  String backImgPath = _backImagePathOrUrl;
                  final firebaseService = FirebaseService();
                  
                  final bool needFrontUpload = _imagePathOrUrl.isNotEmpty && !_imagePathOrUrl.startsWith('http') && !_imagePathOrUrl.startsWith('color:');
                  final bool needBackUpload = _backImagePathOrUrl.isNotEmpty && !_backImagePathOrUrl.startsWith('http') && !_backImagePathOrUrl.startsWith('color:');

                  if (needFrontUpload || needBackUpload) {
                    setState(() => _isUploading = true);
                    try {
                      final baseId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
                      
                      // 表面のオリジナルと軽量サムネイルのアップロード
                      if (needFrontUpload) {
                        final cleanFrontPath = _imagePathOrUrl.startsWith('file://') ? Uri.parse(_imagePathOrUrl).toFilePath() : _imagePathOrUrl;
                        final uploadResult = await firebaseService.uploadCardImage(XFile(cleanFrontPath), '${baseId}_front');
                        if (uploadResult != null) {
                          imgPath = uploadResult.originalUrl;
                          thumbImgPath = uploadResult.thumbnailUrl;
                        } else {
                          throw Exception('表面画像のアップロードに失敗しました。');
                        }
                      }
                      
                      // 裏面のアップロード
                      if (needBackUpload) {
                        final cleanBackPath = _backImagePathOrUrl.startsWith('file://') ? Uri.parse(_backImagePathOrUrl).toFilePath() : _backImagePathOrUrl;
                        final uploadResult = await firebaseService.uploadCardImage(XFile(cleanBackPath), '${baseId}_back');
                        if (uploadResult != null) {
                          backImgPath = uploadResult.originalUrl;
                        } else {
                          throw Exception('裏面画像のアップロードに失敗しました。');
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _isUploading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像の保存に失敗しました: $e')));
                      }
                      return; 
                    }
                  }

                  final tagsList = _tagController.text.split(RegExp(r'[ ,、]+')).where((t) => t.isNotEmpty).toList();

                  final newCard = CardModel(
                    id: '', 
                    refill: _selectedRefill, 
                    count: _count, 
                    frontUrl: imgPath, 
                    thumbnailFrontUrl: thumbImgPath, 
                    backUrl: backImgPath, 
                    tags: tagsList, 
                    memo: _memoController.text, 
                    date: _noDate ? '' : _dateController.text, 
                    isDeleted: false, 
                    isFavorite: false, 
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                  );

                  final savedData = {
                    'binder': _selectedBinder, 'refill': _selectedRefill, 'memo': _memoController.text, 'tagsRaw': _tagController.text, 'date': _noDate ? '' : _dateController.text, 'count': _count, 'frontUrl': imgPath, 'backUrl': backImgPath,
                  };
                  
                  if (mounted) {
                    setState(() => _isUploading = false);
                    widget.onCardAdded(newCard, savedData);
                    Navigator.pop(context);
                  }
                },
                child: _isUploading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('コレクションに刻む'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _AddBinderDialog extends StatefulWidget {
  final List<String> presetCovers;
  final bool isPremiumUser;
  final Function(String name, String coverUrl) onCreated;
  final List<String> existingBinderNames; 
  final String? initialName;
  final String? initialCoverUrl;
  final bool isEditing;
  final Future<bool> Function()? onPaywallTriggered;

  const _AddBinderDialog({
    required this.presetCovers,
    required this.isPremiumUser,
    required this.onCreated,
    required this.existingBinderNames, 
    this.initialName,
    this.initialCoverUrl,
    this.isEditing = false,
    this.onPaywallTriggered,
  });

  @override
  State<_AddBinderDialog> createState() => _AddBinderDialogState();
}

class _AddBinderDialogState extends State<_AddBinderDialog> {
  late String _newName;
  late String _selectedCoverUrl; 
  late final TextEditingController _nameController;
  
  bool _isUploading = false;

  final List<int> _presetColors = [
    0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF2196F3, 0xFF00BCD4,
    0xFF4CAF50, 0xFFFFEB3B, 0xFFFF9800, 0xFF795548, 0xFF212121,
  ];

  @override
  void initState() {
    super.initState();
    _newName = widget.initialName ?? '';
    _selectedCoverUrl = widget.initialCoverUrl ?? widget.presetCovers.first;
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickBinderCover(ImageSource source) async {
    if (!widget.isPremiumUser) {
      if (widget.onPaywallTriggered != null) {
        final purchased = await widget.onPaywallTriggered!();
        if (purchased != true) return; // 未購入時は中断
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カスタム表紙の設定はプレミアムプラン限定機能です。')),
        );
        return;
      }
    }

    final picker = ImagePicker();
    try {
      final pickedImage = await picker.pickImage(source: source, maxWidth: 400, maxHeight: 600);
      if (pickedImage != null) {
        setState(() { 
          _selectedCoverUrl = pickedImage.path; 
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像の取得に失敗しました。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'バインダーの編集' : '新規バインダー作成'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_isUploading,
              decoration: const InputDecoration(hintText: 'バインダー名を入力'), 
              onChanged: (val) => _newName = val
            ),
            const SizedBox(height: 20),
            const Text('現在の表紙プレビュー', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Center(
              child: Container(
                width: 90, height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)],
                  border: Border.all(color: Colors.pinkAccent.withOpacity(0.5), width: 2)
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8), 
                  child: CardImage(urlOrBase64: _selectedCoverUrl),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 16, color: Colors.blue), 
                  label: const Text('カメラ', style: TextStyle(fontSize: 11, color: Colors.blue)), 
                  onPressed: _isUploading ? null : () => _pickBinderCover(ImageSource.camera),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 16, color: Colors.pink), 
                  label: const Text('写真から選ぶ', style: TextStyle(fontSize: 11, color: Colors.pink)), 
                  onPressed: _isUploading ? null : () => _pickBinderCover(ImageSource.gallery),
                ),
              ],
            ),
            const Divider(height: 25),
            const Text('または単色カラーから選択', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _presetColors.length,
                itemBuilder: (itemCtx, idx) {
                  final colorVal = _presetColors[idx];
                  final colorStr = 'color:0x${colorVal.toRadixString(16).padLeft(8, '0').toUpperCase()}';
                  final isSelected = _selectedCoverUrl == colorStr;
                  return GestureDetector(
                    onTap: _isUploading ? null : () => setState(() => _selectedCoverUrl = colorStr),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 40,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.pinkAccent : Colors.grey[300]!,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 15),
            const Text('またはプリセットから選択', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal, itemCount: widget.presetCovers.length,
                itemBuilder: (itemCtx, idx) {
                  final url = widget.presetCovers[idx];
                  final isSelected = _selectedCoverUrl == url;
                  return GestureDetector(
                    onTap: _isUploading ? null : () => setState(() => _selectedCoverUrl = url),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8), width: 55,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? Colors.pinkAccent : Colors.grey[300]!, width: isSelected ? 3 : 1),
                      ),
                      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(url, fit: BoxFit.cover)),
                    ),
                  );
                },
              ),
            ),
            if (_isUploading) ...[
              const SizedBox(height: 15),
              const Center(
                child: CircularProgressIndicator(color: Colors.pinkAccent),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context), 
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _isUploading ? null : () async {
            final trimmedName = _newName.trim();
            if (trimmedName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('バインダー名を入力してください。')));
              return;
            }

            final isDuplicate = widget.existingBinderNames.any((name) => name.toLowerCase() == trimmedName.toLowerCase());
            if (isDuplicate) {
              if (!widget.isEditing || trimmedName != widget.initialName?.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('同じ名前のバインダーが既に存在します。⚠️')),
                );
                return;
              }
            }

            String coverUrlToSave = _selectedCoverUrl;

            if (_selectedCoverUrl.isNotEmpty && 
                !_selectedCoverUrl.startsWith('http') && 
                !_selectedCoverUrl.startsWith('color:')) {
              
              setState(() => _isUploading = true);
              try {
                final firebaseService = FirebaseService();
                final cleanCoverPath = _selectedCoverUrl.startsWith('file://') ? Uri.parse(_selectedCoverUrl).toFilePath() : _selectedCoverUrl;
                final uploadedUrl = await firebaseService.uploadBinderCoverImage(
                  XFile(cleanCoverPath), 
                  trimmedName,
                );

                if (uploadedUrl != null) {
                  coverUrlToSave = uploadedUrl;
                } else {
                  throw Exception('バインダー表紙のアップロードURL取得に失敗しました。');
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isUploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('表紙画像のアップロードに失敗しました: $e')));
                }
                return;
              }
            }

            if (mounted) {
              setState(() => _isUploading = false);
              widget.onCreated(trimmedName, coverUrlToSave);
              Navigator.pop(context); 
            }
          }, 
          child: Text(widget.isEditing ? '保存' : '作成'),
        ),
      ],
    );
  }
}

class _CardDetailDialog extends StatefulWidget {
  final CardModel card;
  final bool isFromTrash;
  final bool isPremiumUser;
  final int totalActiveCardCount;
  final int maxFreeCardCount;
  final VoidCallback onFavoriteToggled;
  final Function(CardModel updatedCard) onCardUpdated;
  final VoidCallback onDeletePressed;
  final Function(CardModel currentCard) onMovePressed; 
  final VoidCallback onRestorePressed;
  final Future<bool> Function() onPaywallTriggered;

  const _CardDetailDialog({
    required this.card,
    required this.isFromTrash,
    required this.isPremiumUser,
    required this.totalActiveCardCount,
    required this.maxFreeCardCount,
    required this.onFavoriteToggled,
    required Function(CardModel updatedCard) this.onCardUpdated,
    required this.onDeletePressed,
    required this.onMovePressed,
    required this.onRestorePressed,
    required this.onPaywallTriggered,
  });

  @override
  State<_CardDetailDialog> createState() => _CardDetailDialogState();
}

class _CardDetailDialogState extends State<_CardDetailDialog> {
  bool _showBack = false;
  bool _isEditing = false; 
  bool _isUploading = false;
  late CardModel _localCard;

  late final TextEditingController _memoEditController;
  late final TextEditingController _tagEditController;
  late final TextEditingController _dateEditController;
  late final TextEditingController _frontUrlEditController;
  late final TextEditingController _backUrlEditController;
  late bool _noDateEdit; 

  @override
  void initState() {
    super.initState();
    _localCard = widget.card;
    _memoEditController = TextEditingController(text: _localCard.memo);
    _tagEditController = TextEditingController(text: _localCard.tags.join(', '));
    _dateEditController = TextEditingController(text: _localCard.date);
    _frontUrlEditController = TextEditingController(text: _localCard.frontUrl);
    _backUrlEditController = TextEditingController(text: _localCard.backUrl);
    _noDateEdit = _localCard.date.isEmpty;
  }

  @override
  void dispose() {
    _memoEditController.dispose();
    _tagEditController.dispose();
    _dateEditController.dispose();
    _frontUrlEditController.dispose();
    _backUrlEditController.dispose();
    super.dispose();
  }

  Future<void> _pickEditImage(ImageSource source, {required bool isFront}) async {
    final picker = ImagePicker();
    try {
      final pickedImage = await picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1600);
      if (pickedImage != null && mounted) {
        final selectedAspectRatio = await _showAspectRatioPickerDialog(context);
        if (selectedAspectRatio == null) return; // キャンセル時

        final bool isOriginal = selectedAspectRatio.ratioX == -1;
        final CropAspectRatio? cropAspectRatio = isOriginal ? null : selectedAspectRatio;

        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedImage.path,
          aspectRatio: cropAspectRatio,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 85,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: isFront ? '表面のトリミング' : '裏面のトリミング',
              toolbarColor: Colors.pinkAccent,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: isOriginal ? CropAspectRatioPreset.original : CropAspectRatioPreset.square,
              lockAspectRatio: !isOriginal,
            ),
            IOSUiSettings(
              title: isFront ? '表面のトリミング' : '裏面のトリミング',
              aspectRatioLockEnabled: !isOriginal,
              resetAspectRatioEnabled: isOriginal,
            ),
          ],
        );

        if (croppedFile != null) {
          setState(() {
            if (isFront) {
              _frontUrlEditController.text = croppedFile.path;
            } else {
              _backUrlEditController.text = croppedFile.path;
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像の取得またはトリミングに失敗しました。')));
      }
    }
  }

  void _showEditImagePickerModal(BuildContext context, {required bool isFront}) {
    showModalBottomSheet(
      context: context,
      builder: (pickerCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue), 
              title: const Text('カメラで撮影'), 
              onTap: () { Navigator.pop(pickerCtx); _pickEditImage(ImageSource.camera, isFront: isFront); }
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.pink), 
              title: const Text('ギャラリーから選択'), 
              onTap: () { Navigator.pop(pickerCtx); _pickEditImage(ImageSource.gallery, isFront: isFront); }
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_isEditing ? 'カード情報を編集' : 'カード詳細', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Row(
            children: [
              if (!widget.isFromTrash && !_isEditing)
                IconButton(
                  icon: Icon(_localCard.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pinkAccent),
                  onPressed: () { 
                    final updated = CardModel(
                      id: _localCard.id,
                      refill: _localCard.refill,
                      count: _localCard.count,
                      frontUrl: _localCard.frontUrl,
                      thumbnailFrontUrl: _localCard.thumbnailFrontUrl,
                      backUrl: _localCard.backUrl,
                      tags: _localCard.tags,
                      memo: _localCard.memo,
                      date: _localCard.date,
                      isDeleted: _localCard.isDeleted,
                      isFavorite: !_localCard.isFavorite,
                      timestamp: _localCard.timestamp,
                    );
                    setState(() {
                      _localCard = updated;
                    });
                    widget.onFavoriteToggled(); 
                    widget.onCardUpdated(updated); 
                  },
                ),
              if (!widget.isFromTrash && !_isUploading)
                IconButton(
                  icon: Icon(_isEditing ? Icons.visibility : Icons.edit, color: Colors.pinkAccent), 
                  onPressed: () => setState(() => _isEditing = !_isEditing),
                ),
            ],
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isEditing) ...[
              GestureDetector(
                onTap: () { if (_localCard.backUrl.isNotEmpty) setState(() => _showBack = !_showBack); },
                child: Container(
                  height: 230, width: 160, 
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12), 
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ), 
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11), 
                    child: CardImage(urlOrBase64: _showBack ? _localCard.backUrl : _localCard.frontUrl),
                  ),
                ),
              ),
              const SizedBox(height: 6), 
              Text(_localCard.backUrl.isNotEmpty ? (_showBack ? '裏面を表示中' : '表面を表示中') : '（裏面未登録）', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(widget.isFromTrash ? 'ゴミ箱内の枚数: ' : '所持枚数: '), 
                if (!widget.isFromTrash)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.pinkAccent), 
                    onPressed: () { 
                      if (_localCard.count > 0) { 
                        final updated = CardModel(
                          id: _localCard.id,
                          refill: _localCard.refill,
                          count: _localCard.count - 1,
                          frontUrl: _localCard.frontUrl,
                          thumbnailFrontUrl: _localCard.thumbnailFrontUrl, 
                          backUrl: _localCard.backUrl,
                          tags: _localCard.tags,
                          memo: _localCard.memo,
                          date: _localCard.date,
                          isDeleted: _localCard.isDeleted,
                          isFavorite: _localCard.isFavorite,
                          timestamp: _localCard.timestamp,
                        );
                        setState(() {
                          _localCard = updated;
                        });
                        widget.onCardUpdated(updated); 
                      } 
                    }
                  ),
                Text('${_localCard.count} 枚', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (!widget.isFromTrash)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.pinkAccent), 
                    onPressed: () async { 
                      bool currentPremiumStatus = widget.isPremiumUser;
                      // 詳細ダイアログ内での増枠時にも上限チェック
                      if (!currentPremiumStatus && (widget.totalActiveCardCount + 1) > widget.maxFreeCardCount) { 
                        final purchased = await widget.onPaywallTriggered(); 
                        if (purchased != true) return;
                        currentPremiumStatus = true;
                      }

                      // 3,000枚上限チェックを追加
                      if (widget.totalActiveCardCount + 1 > 3000) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('カードの最大登録枚数（3,000枚）に達しているため追加できません。')),
                        );
                        return;
                      }

                      final updated = CardModel(
                        id: _localCard.id,
                        refill: _localCard.refill,
                        count: _localCard.count + 1,
                        frontUrl: _localCard.frontUrl,
                        thumbnailFrontUrl: _localCard.thumbnailFrontUrl, 
                        backUrl: _localCard.backUrl,
                        tags: _localCard.tags,
                        memo: _localCard.memo,
                        date: _localCard.date,
                        isDeleted: _localCard.isDeleted,
                        isFavorite: _localCard.isFavorite,
                        timestamp: _localCard.timestamp,
                      );
                      setState(() {
                        _localCard = updated;
                      });
                      widget.onCardUpdated(updated); 
                    }
                  ),
              ]),
              const Divider(height: 16),
              Wrap(spacing: 6, children: _localCard.tags.map((tag) => Chip(label: Text(tag, style: const TextStyle(fontSize: 10)), backgroundColor: Colors.pink[50])).toList()),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('📅 入手: ${_localCard.date.isEmpty ? "設定なし" : _localCard.date}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Text('📝 メモ: ${_localCard.memo}', style: const TextStyle(fontSize: 12, color: Colors.black87))])),
            ] else ...[
              TextField(controller: _memoEditController, enabled: !_isUploading, decoration: const InputDecoration(labelText: 'メモ', labelStyle: TextStyle(fontSize: 12))),
              TextField(controller: _tagEditController, enabled: !_isUploading, decoration: const InputDecoration(labelText: 'タグ (コンマかスペース区切り)', labelStyle: TextStyle(fontSize: 12))),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateEditController,
                      enabled: !_noDateEdit && !_isUploading,
                      decoration: InputDecoration(
                        labelText: '入手日',
                        labelStyle: const TextStyle(fontSize: 12),
                        hintText: _noDateEdit ? '選択しない' : '',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isUploading ? null : () {
                      setState(() {
                        _noDateEdit = !_noDateEdit;
                        if (_noDateEdit) {
                          _dateEditController.text = '';
                        } else {
                          _dateEditController.text = _localCard.date.isNotEmpty ? _localCard.date : '2026年${DateTime.now().month.toString().padLeft(2, '0')}月';
                        }
                      });
                    },
                    child: Text(_noDateEdit ? '日付を設定' : '選択しない', style: const TextStyle(color: Colors.pinkAccent, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('画像変更', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 表面画像プレビュー＆変更
                  Column(
                    children: [
                      const Text('表面 (必須)', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _isUploading ? null : () => _showEditImagePickerModal(context, isFront: true),
                        child: Container(
                          height: 130, width: 90,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.pinkAccent.withOpacity(0.5), width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: CardImage(urlOrBase64: _frontUrlEditController.text),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
                        icon: const Icon(Icons.edit, size: 12, color: Colors.pinkAccent),
                        label: const Text('変更', style: TextStyle(fontSize: 11, color: Colors.pinkAccent)),
                        onPressed: _isUploading ? null : () => _showEditImagePickerModal(context, isFront: true),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  // 裏面画像プレビュー＆追加／変更／削除
                  Column(
                    children: [
                      const Text('裏面 (任意)', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      _backUrlEditController.text.isEmpty
                          ? GestureDetector(
                              onTap: _isUploading ? null : () => _showEditImagePickerModal(context, isFront: false),
                              child: Container(
                                height: 130, width: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!, width: 2),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, color: Colors.grey, size: 20),
                                    SizedBox(height: 2),
                                    Text('追加', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            )
                          : Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: _isUploading ? null : () => _showEditImagePickerModal(context, isFront: false),
                                  child: Container(
                                    height: 130, width: 90,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey[300]!, width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: CardImage(urlOrBase64: _backUrlEditController.text),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -6, right: -6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _backUrlEditController.text = ''),
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.redAccent,
                                      child: Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
                        icon: Icon(_backUrlEditController.text.isEmpty ? Icons.add : Icons.edit, size: 12, color: Colors.pinkAccent),
                        label: Text(_backUrlEditController.text.isEmpty ? '追加' : '変更', style: const TextStyle(fontSize: 11, color: Colors.pinkAccent)),
                        onPressed: _isUploading ? null : () => _showEditImagePickerModal(context, isFront: false),
                      ),
                    ],
                  ),
                ],
              ),
              if (_isUploading) ...[
                const SizedBox(height: 15),
                const CircularProgressIndicator(color: Colors.pinkAccent),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                  onPressed: _isUploading ? null : () async {
                    if (_frontUrlEditController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('表面の画像は必須です。')),
                      );
                      return;
                    }

                    setState(() => _isUploading = true);
                    
                    String frontToSave = _frontUrlEditController.text.trim();
                    String thumbToSave = _localCard.thumbnailFrontUrl;
                    String backToSave = _backUrlEditController.text.trim();
                    final firebaseService = FirebaseService();

                    try {
                      if (frontToSave.isNotEmpty && !frontToSave.startsWith('http') && !frontToSave.startsWith('color:')) {
                        final cleanFrontPath = frontToSave.startsWith('file://') ? Uri.parse(frontToSave).toFilePath() : frontToSave;
                        final uploadResult = await firebaseService.uploadCardImage(XFile(cleanFrontPath), '${_localCard.id}_front');
                        if (uploadResult != null) {
                          frontToSave = uploadResult.originalUrl;
                          thumbToSave = uploadResult.thumbnailUrl;
                        }
                      }
                      if (backToSave.isNotEmpty && !backToSave.startsWith('http') && !backToSave.startsWith('color:')) {
                        final cleanBackPath = backToSave.startsWith('file://') ? Uri.parse(backToSave).toFilePath() : backToSave;
                        final uploadResult = await firebaseService.uploadCardImage(XFile(cleanBackPath), '${_localCard.id}_back');
                        if (uploadResult != null) {
                          backToSave = uploadResult.originalUrl;
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _isUploading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像のアップロードに失敗しました: $e')));
                      }
                      return;
                    }

                    final tagsList = _tagEditController.text.split(RegExp(r'[ ,、]+')).where((t) => t.isNotEmpty).toList();

                    final updated = CardModel(
                      id: _localCard.id,
                      refill: _localCard.refill,
                      count: _localCard.count,
                      frontUrl: frontToSave,
                      thumbnailFrontUrl: thumbToSave,
                      backUrl: backToSave,
                      tags: tagsList,
                      memo: _memoEditController.text,
                      date: _noDateEdit ? '' : _dateEditController.text,
                      isDeleted: _localCard.isDeleted,
                      isFavorite: _localCard.isFavorite,
                      timestamp: _localCard.timestamp,
                    );

                    if (mounted) {
                      setState(() {
                        _localCard = updated;
                        _isEditing = false;
                        _isUploading = false;
                      });
                      widget.onCardUpdated(updated); 
                    }
                  },
                  child: const Text('変更を保存する', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ]
          ],
        ),
      ), 
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            widget.isFromTrash 
            ? ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, elevation: 0),
                icon: const Icon(Icons.restore, size: 16), 
                label: Text(_localCard.count > 1 ? '復元 (${_localCard.count}枚)' : '復元する'),
                onPressed: () async { 
                  bool currentPremiumStatus = widget.isPremiumUser;
                  // ゴミ箱から復元する際の上限チェック（まとめて所持枚数分で計算）
                  if (!currentPremiumStatus && (widget.totalActiveCardCount + _localCard.count) > widget.maxFreeCardCount) { 
                    final purchased = await widget.onPaywallTriggered(); 
                    if (purchased != true) return;
                    currentPremiumStatus = true;
                  }

                  // 3,000枚上限チェック（まとめて所持枚数分で計算）
                  if (widget.totalActiveCardCount + _localCard.count > 3000) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('カードの最大登録枚数（3,000枚）に達しているため復元できません。')),
                    );
                    return;
                  }

                  Navigator.pop(context); widget.onRestorePressed();
                },
              )
            : Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent), 
                    onPressed: _isUploading ? null : () {
                      widget.onDeletePressed();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_outlined, color: Colors.blueAccent), 
                    tooltip: '別のリフィルへ移動', 
                    onPressed: _isUploading ? null : () => widget.onMovePressed(_localCard), 
                  ),
                ],
              ),
            TextButton(
              onPressed: _isUploading ? null : () => Navigator.pop(context), 
              child: const Text('閉じる', style: TextStyle(color: Colors.pinkAccent)),
            ),
          ],
        )
      ]
    );
  }
}
