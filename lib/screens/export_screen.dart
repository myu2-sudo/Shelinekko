import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/card_model.dart'; // 既存のモデルファイルへのパス（必要に応じて修正してください）

// スタンプの定義クラス
class StampInfo {
  final String label;
  final Color color;
  const StampInfo(this.label, this.color);
}

// 交換画像でよく使われるスタンプの一覧
const List<StampInfo> availableStamps = [
  StampInfo('譲', Color(0xFFE53935)),   // 赤
  StampInfo('求', Color(0xFF1E88E5)),   // 青
  StampInfo('激求', Color(0xFFD81B60)),  // 濃いピンク
  StampInfo('緩募', Color(0xFFF4511E)),  // オレンジ
  StampInfo('♡', Color(0xFF8E24AA)),  // 紫
  StampInfo('★', Color(0xFF43A047)),    // 緑
];

// 背景パレット用の色定義
class BackgroundColorOption {
  final String name;
  final Color color;
  const BackgroundColorOption(this.name, this.color);
}

const List<BackgroundColorOption> backgroundOptions = [
  BackgroundColorOption('ホワイト', Colors.white),
  BackgroundColorOption('さくら', Color(0xFFFFF0F5)),
  BackgroundColorOption('そら', Color(0xFFE0F7FA)),
  BackgroundColorOption('グレー', Color(0xFFF5F5F5)),
  BackgroundColorOption('ブラック', Color(0xFF121212)),
];

class ExportScreen extends StatefulWidget {
  final List<CardModel> selectedCards;

  const ExportScreen({super.key, required this.selectedCards});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // 並べ替え可能なカードリスト
  late List<CardModel> _cards;

  // 各カードIDに対して、どのスタンプが貼られているかを管理するマップ
  final Map<String, StampInfo?> _cardStamps = {};
  
  // 現在選択中のスタンプ（nullの場合は「消しゴム」として機能）
  StampInfo? _selectedStamp = availableStamps[0]; // デフォルトは「譲」
  
  // カスタマイズ設定
  int _crossAxisCount = 2; // デフォルト2列
  Color _backgroundColor = Colors.white; // 背景色
  
  // 画像エクスポート用のキー
  final GlobalKey _globalKey = GlobalKey();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    // 順序変更が可能なようにリストをコピー
    _cards = List.from(widget.selectedCards);

    // 初期状態はすべてのカードにスタンプがない状態にする
    for (var card in _cards) {
      _cardStamps[card.id] = null;
    }
  }

  // カードタップ時のスタンプ貼り付けロジック
  void _onCardTap(String cardId) {
    setState(() {
      if (_selectedStamp == null) {
        // 消しゴムモード
        _cardStamps[cardId] = null;
      } else {
        // 現在選択中のスタンプと同じものが貼られている場合は剥がす、違う場合は上書きする
        if (_cardStamps[cardId] == _selectedStamp) {
          _cardStamps[cardId] = null;
        } else {
          _cardStamps[cardId] = _selectedStamp;
        }
      }
    });
  }

  // カードの位置を入れ替える処理
  void _reorderCards(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    setState(() {
      final card = _cards.removeAt(oldIndex);
      _cards.insert(newIndex, card);
    });
  }

  // 画像を生成してシェアする
  Future<void> _exportImage() async {
    if (_isExporting) return;
    
    setState(() {
      _isExporting = true;
    });

    // ユーザーに処理中であることを知らせるダイアログを表示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('高画質画像を生成中...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // ネットワーク画像などが完全に描画される時間を少し待つための微調整
      await Future.delayed(const Duration(milliseconds: 500));

      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // pixelRatioを「3.0」に設定することで高画質な画像を出力
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();

        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/trade_cards_${DateTime.now().millisecondsSinceEpoch}.png').create();
        await imagePath.writeAsBytes(pngBytes);

        // ロードダイアログを閉じる
        if (mounted) Navigator.pop(context);

        // シェア画面を起動
        await Share.shareXFiles(
          [XFile(imagePath.path)], 
          text: 'トレカ交換用画像をアプリで作成しました！ #トレカ交換 #アイドルトレカ'
        );
      } else {
        throw Exception('画像データの変換に失敗しました');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像の生成に失敗しました。時間をおいて再度お試しください。: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // 単一カード描画用ウィジェット
  Widget _buildCardWidget(CardModel card, StampInfo? stamp) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // カード画像コンテナ
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              card.frontUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              },
            ),
          ),
        ),

        // スタンプレイヤー
        if (stamp != null)
          Positioned(
            top: 6,
            left: 6,
            child: Transform.rotate(
              angle: -0.15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: stamp.color.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.9), 
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(1, 2),
                    )
                  ],
                ),
                child: Text(
                  stamp.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交換用画像の編集'),
        actions: [
          ElevatedButton.icon(
            onPressed: _exportImage,
            icon: const Icon(Icons.share, size: 18),
            label: const Text('出力する'),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. 操作説明とグリッド設定のヘッダー
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'タップでスタンプ／長押しドラッグで位置変更',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                  ),
                ),
                // 列数の切り替え
                Row(
                  children: [
                    const Text('列数: ', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                        ButtonSegment(value: 4, label: Text('4')),
                      ],
                      selected: {_crossAxisCount},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          _crossAxisCount = newSelection.first;
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. カードのプレビュー領域（台紙サイズがカード群にジャストフィット）
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RepaintBoundary(
                        key: _globalKey,
                        child: Container(
                          color: _backgroundColor,
                          padding: const EdgeInsets.all(16.0), // ★上下左右16pxで完全均等に固定！
                          child: SizedBox(
                            width: 360, // 基準幅
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _crossAxisCount,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 54 / 86, // カード単体の比率は 54:86 を維持
                              ),
                              itemCount: _cards.length,
                              itemBuilder: (context, index) {
                                final card = _cards[index];
                                final stamp = _cardStamps[card.id];

                                return DragTarget<int>(
                                  onAcceptWithDetails: (details) {
                                    _reorderCards(details.data, index);
                                  },
                                  builder: (context, candidateData, rejectedData) {
                                    final isHovered = candidateData.isNotEmpty;

                                    return LongPressDraggable<int>(
                                      data: index,
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: SizedBox(
                                          width: (360 - (_crossAxisCount - 1) * 8) / _crossAxisCount,
                                          height: ((360 - (_crossAxisCount - 1) * 8) / _crossAxisCount) * (86 / 54),
                                          child: Opacity(
                                            opacity: 0.85,
                                            child: _buildCardWidget(card, stamp),
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child: _buildCardWidget(card, stamp),
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: isHovered
                                              ? Border.all(color: Theme.of(context).primaryColor, width: 3)
                                              : null,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => _onCardTap(card.id),
                                          child: _buildCardWidget(card, stamp),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. ボトムコントローラー（スタンプパレット ＆ 背景色設定）
          Container(
            padding: const EdgeInsets.only(top: 16, bottom: 24, left: 16, right: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // スタンプセレクター
                const Text(
                  'スタンプを選択:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // 消しゴムボタン
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: const Icon(Icons.cleaning_services, size: 16),
                          label: const Text('消しゴム'),
                          selected: _selectedStamp == null,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedStamp = null;
                              });
                            }
                          },
                        ),
                      ),
                      // 各スタンプのチップ
                      ...availableStamps.map((stamp) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: stamp.color,
                              radius: 8,
                            ),
                            label: Text(stamp.label),
                            selected: _selectedStamp == stamp,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedStamp = stamp;
                                });
                              }
                            },
                            selectedColor: stamp.color.withOpacity(0.2),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // 背景色の切り替え
                const Text(
                  '台紙（背景色）を選択:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: backgroundOptions.length,
                    itemBuilder: (context, index) {
                      final option = backgroundOptions[index];
                      final isSelected = _backgroundColor == option.color;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _backgroundColor = option.color;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: option.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade400,
                                width: isSelected ? 3.0 : 1.0,
                              ),
                            ),
                            child: isSelected 
                              ? Icon(
                                  Icons.check, 
                                  size: 16, 
                                  color: option.color == Colors.white ? Colors.black : Colors.white,
                                ) 
                              : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
