class BinderModel {
  final String id; 
  final String name;
  final String coverUrl; // 💡 画像URL、または単色カラーのカラーコード（例: '0xFF212121'）が入ります
  final int sortOrder; // バインダー自体の並び順
  final List<String> refillIds; // ✨ ④追加：リフィルの並び順を維持するためのIDリスト

  // 💡 お気に入りリフィルの共通名称をシステム定数として定義
  static const String favoriteRefillName = '❤ お気に入り';

  // 🎨 ⑤追加：表紙用の単色カラー12色の定義（カラーコードを文字列として管理）
  // 画面（UI）側からは「BinderModel.coverColors」で簡単に呼び出せます。
  static const Map<String, String> coverColors = {
    '黒': '0xFF212121',
    'グレー': '0xFF9E9E9E',
    'ピンク': '0xFFF48FB1',
    '水色': '0xFF90CAF9',
    '青': '0xFF2196F3',
    '緑': '0xFF81C784',
    '紫': '0xFFB39DDB',
    '黄色': '0xFFFFF59D',
    '茶': '0xFF8D6E63',
    'オレンジ': '0xFFFFB74D',
    '赤': '0xFFE57373',
    'クリーム': '0xFFFFF9C4',
  };

  BinderModel({
    this.id = '', 
    required this.name,
    required this.coverUrl,
    this.sortOrder = 0, 
    this.refillIds = const [], // ✨ ④追加：デフォルトは空のリスト
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id, 
      'name': name,
      'coverUrl': coverUrl,
      'sortOrder': sortOrder, 
      'refillIds': refillIds, // ✨ ④追加：Firestore保存用のマップに含める
    };
  }

  factory BinderModel.fromMap(Map<String, dynamic> map) {
    return BinderModel(
      id: map['id'] as String? ?? '', 
      name: map['name'] as String? ?? '',
      coverUrl: map['coverUrl'] as String? ?? '',
      sortOrder: map['sortOrder'] as int? ?? 0, 
      // ✨ ④追加：安全にList<String>にキャストして復元する（データがない場合は空リスト）
      refillIds: (map['refillIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  BinderModel copyWith({
    String? id,
    String? name,
    String? coverUrl,
    int? sortOrder,
    List<String>? refillIds, // ✨ ④追加：コピーメソッドに対応
  }) {
    return BinderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      sortOrder: sortOrder ?? this.sortOrder,
      refillIds: refillIds ?? this.refillIds, // ✨ ④追加
    );
  }

  // 🔄 追加：リフィルの並び順を入れ替えた新しいインスタンスを生成するメソッド
  // FlutterのReorderableListViewで発生するインデックスのズレを自動で補正します。
  BinderModel reorderRefills(int oldIndex, int newIndex) {
    // インデックスの安全チェック
    if (oldIndex < 0 || oldIndex >= refillIds.length) return this;

    final List<String> newRefillIds = List.from(refillIds);

    // ReorderableListViewの仕様に対応：要素を後ろに動かすとき、
    // 移動先のインデックスが1つ大きく取得されるため補正が必要になります。
    int targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }

    // 要素を移動
    final String movedId = newRefillIds.removeAt(oldIndex);
    newRefillIds.insert(targetIndex, movedId);

    // 並び替え後の新しいリストを持ったBinderModelを返す
    return copyWith(refillIds: newRefillIds);
  }
}
