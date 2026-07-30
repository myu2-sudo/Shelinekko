import 'dart:convert';

class CardModel {
  final String id; // ✨ 修正: int から String に変更
  String refill;
  int count; // 通常表示用の枚数
  int deletedCount; // ✨ 追加: ゴミ箱の中にある枚数
  String frontUrl;
  String thumbnailFrontUrl; // ✨ 追加: 一覧表示用の超軽量サムネイルURL
  String backUrl;
  List<String> tags;
  String memo;
  String date; // 🌟「選択しない」の場合は空文字（''）を格納
  bool isDeleted;
  String? deletedAt;
  bool isFavorite;
  final int timestamp;
  String aspectRatioType; // ✨ 修正: 画像サイズ指定 ('card6388', 'card5486', 'square')

  // UI表示用の一時的な拡張プロパティ（Firestoreには保存しません）
  int? displayIndex;
  String? uniqueKey;

  CardModel({
    required this.id,
    required this.refill,
    required this.count,
    this.deletedCount = 0, // ✨ 追加（デフォルト値 0）
    required this.frontUrl,
    required this.thumbnailFrontUrl,
    required this.backUrl,
    required this.tags,
    required this.memo,
    required this.date,
    required this.isDeleted,
    this.deletedAt,
    required this.isFavorite,
    required this.timestamp,
    this.aspectRatioType = 'card6388', // ✨ 修正（デフォルトは'card6388'）
    this.displayIndex,
    this.uniqueKey,
  });

  /// ✨ 修正: UIの AspectRatio ウィジェット等でそのまま使える数値を取得するゲッター
  double get aspectRatio {
    switch (aspectRatioType) {
      case 'card6388':
        return 63 / 88; // 約 0.716（レギュラーカードサイズ）
      case 'card5486':
        return 54 / 86; // 約 0.628（チェキ・スモールサイズ）
      case 'square':
        return 1.0; // 1:1 正方形
      case 'original': // 既存データ互換用フォールバック
      default:
        return 63 / 88;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'refill': refill,
      'count': count,
      'deletedCount': deletedCount, // ✨ 追加
      'frontUrl': frontUrl,
      'thumbnailFrontUrl': thumbnailFrontUrl,
      'backUrl': backUrl,
      'tags': tags,
      'memo': memo,
      'date': date,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt,
      'isFavorite': isFavorite,
      'timestamp': timestamp,
      'aspectRatioType': aspectRatioType, // ✨ 追加
    };
  }

  factory CardModel.fromMap(Map<String, dynamic> map) {
    String parseId(dynamic val) {
      if (val == null) return '';
      return val.toString();
    }

    int parseCount(dynamic val) {
      if (val is int) return val;
      if (val is String) return int.tryParse(val) ?? 1;
      if (val is double) return val.toInt();
      return 1;
    }

    int parseTimestamp(dynamic val) {
      if (val is int) return val;
      if (val is String) return int.tryParse(val) ?? DateTime.now().millisecondsSinceEpoch;
      if (val is double) return val.toInt();
      return DateTime.now().millisecondsSinceEpoch;
    }

    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is String) return val.toLowerCase() == 'true';
      if (val is int) return val == 1;
      return false;
    }

    return CardModel(
      id: parseId(map['id']),
      refill: map['refill']?.toString() ?? '',
      count: parseCount(map['count']),
      deletedCount: map['deletedCount'] != null ? parseCount(map['deletedCount']) : 0, // ✨ 追加
      frontUrl: map['frontUrl']?.toString() ?? '',
      thumbnailFrontUrl: map['thumbnailFrontUrl']?.toString() ?? map['frontUrl']?.toString() ?? '',
      backUrl: map['backUrl']?.toString() ?? '',
      tags: map['tags'] is List 
          ? List<String>.from((map['tags'] as List).map((e) => e.toString())) 
          : [],
      memo: map['memo']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      isDeleted: parseBool(map['isDeleted']),
      deletedAt: map['deletedAt']?.toString(),
      isFavorite: parseBool(map['isFavorite']),
      timestamp: parseTimestamp(map['timestamp']),
      aspectRatioType: map['aspectRatioType']?.toString() ?? 'card6388', // ✨ 修正（デフォルトを'card6388'に）
    );
  }

  CardModel copyWith({
    int? displayIndex,
    String? uniqueKey,
    int? count,
    int? deletedCount, // ✨ 追加
    bool? isDeleted,
    String? deletedAt,
    String? refill,
    bool? isFavorite,
    String? memo,
    List<String>? tags,
    String? date,
    String? frontUrl,
    String? thumbnailFrontUrl,
    String? backUrl,
    String? aspectRatioType, // ✨ 追加
  }) {
    return CardModel(
      id: id,
      refill: refill ?? this.refill,
      count: count ?? this.count,
      deletedCount: deletedCount ?? this.deletedCount, // ✨ 追加
      frontUrl: frontUrl ?? this.frontUrl,
      thumbnailFrontUrl: thumbnailFrontUrl ?? this.thumbnailFrontUrl,
      backUrl: backUrl ?? this.backUrl,
      tags: tags ?? this.tags,
      memo: memo ?? this.memo,
      date: date ?? this.date,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      timestamp: timestamp,
      aspectRatioType: aspectRatioType ?? this.aspectRatioType, // ✨ 追加
      displayIndex: displayIndex ?? this.displayIndex,
      uniqueKey: uniqueKey ?? this.uniqueKey,
    );
  }

  /// ✨ 追加: リスト内の同一IDを持つカードを1つにまとめ、枚数(count / deletedCount)を合算するヘルパー関数
  static List<CardModel> groupById(List<CardModel> cards) {
    final Map<String, CardModel> grouped = {};
    for (var card in cards) {
      if (grouped.containsKey(card.id)) {
        final existing = grouped[card.id]!;
        grouped[card.id] = existing.copyWith(
          count: existing.count + card.count,
          deletedCount: existing.deletedCount + card.deletedCount,
        );
      } else {
        grouped[card.id] = card;
      }
    }
    return grouped.values.toList();
  }
}
