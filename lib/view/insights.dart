import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:alamode_app/main.dart';
import 'package:alamode_app/services/insight_service.dart';
import 'package:alamode_app/view/memo.dart';

/// マイページから開く「あなたのお菓子レポート」。
/// 記録（Memo）が増えるほど新しい発見が解放されていく。集計は端末内だけで完結する。
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late Future<InsightResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<InsightResult> _load() async {
    final presents = await PresentManagementService().getAllPresents();
    return InsightService.analyze(presents);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('あなたのお菓子レポート', style: TextStyle(fontSize: 18))),
      body: SafeArea(
        child: FutureBuilder<InsightResult>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return const Center(child: Text('レポートの作成に失敗しました。'));
            }
            return _body(context, snap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, InsightResult r) {
    final primary = Theme.of(context).primaryColor;
    if (r.total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Memoに贈った・貰ったお菓子を記録すると、\nここにあなただけのレポートが育っていきます。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.blackLight, height: 1.6),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _summaryCard(r, primary),
        if (r.nextUnlock != null) ...[
          const SizedBox(height: 16),
          _nextUnlockCard(r, primary),
        ],
        if (r.trivia.isNotEmpty) ...[
          const SizedBox(height: 16),
          _triviaCard(r, primary),
        ],
        const SizedBox(height: 16),
        _section(
          title: 'お菓子タイプ',
          unlockAt: InsightService.unlockPersona,
          total: r.total,
          child: r.persona == null ? const SizedBox() : _personaBody(r, primary),
        ),
        _section(
          title: 'ジャンルの好み',
          unlockAt: InsightService.unlockGenre,
          total: r.total,
          child: _genreBody(r, primary),
        ),
        _section(
          title: '価格帯の傾向',
          unlockAt: InsightService.unlockPrice,
          total: r.total,
          child: _priceBody(r, primary),
        ),
        _section(
          title: '人とのお菓子の関係',
          unlockAt: InsightService.unlockPeople,
          total: r.total,
          child: _peopleBody(r, primary),
        ),
        _section(
          title: '季節・曜日のリズム',
          unlockAt: InsightService.unlockSeason,
          total: r.total,
          child: _seasonBody(r, primary),
        ),
        const SizedBox(height: 8),
        const Text(
          '※ この集計はあなたの記録をもとに端末内で計算しています。',
          style: TextStyle(fontSize: 11, color: AppColors.blackLight),
        ),
      ],
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: AppColors.shadowColor, blurRadius: 12, offset: Offset(0, 4)),
        ],
      );

  Widget _summaryCard(InsightResult r, Color primary) {
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.blackLight)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: _cardDecoration,
      child: Row(children: [
        stat('記録', '${r.total}'),
        stat('贈った', '${r.sentCount}'),
        stat('貰った', '${r.receivedCount}'),
        stat('平均★(贈)', r.avgReaction == null ? '-' : r.avgReaction!.toStringAsFixed(1)),
      ]),
    );
  }

  Widget _nextUnlockCard(InsightResult r, Color primary) {
    final next = r.nextUnlock!;
    final remain = next.requiredCount - r.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.lock_open_rounded, color: primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'あと$remain件記録すると「${next.title}」が見えてきます',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _triviaCard(InsightResult r, Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lightbulb_outline, color: primary, size: 20),
            const SizedBox(width: 8),
            const Text('ここまでの発見',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          for (final t in r.trivia)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('・'),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.5))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required int unlockAt,
    required int total,
    required Widget child,
  }) {
    final locked = total < unlockAt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            if (locked) const Icon(Icons.lock_outline, size: 18, color: AppColors.blackLight),
          ]),
          const SizedBox(height: 12),
          if (locked)
            Text('あと${unlockAt - total}件の記録で解放されます（$unlockAt件〜）',
                style: const TextStyle(fontSize: 12, color: AppColors.blackLight))
          else
            child,
        ],
      ),
    );
  }

  // ---- 各セクション ----

  Widget _personaBody(InsightResult r, Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.persona!,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
      const SizedBox(height: 6),
      Text(r.personaDescription ?? '', style: const TextStyle(fontSize: 13, height: 1.5)),
    ]);
  }

  static const List<Color> _palette = [
    Color(0xFF1C6ECD),
    Color(0xFFB9727C),
    Color(0xFF6BA58F),
    Color(0xFFE0A458),
    Color(0xFF8E7CC3),
    Color(0xFF999999),
  ];

  Widget _genreBody(InsightResult r, Color primary) {
    if (r.genres.isEmpty) {
      return const Text('ジャンルが入力された記録がまだありません。',
          style: TextStyle(fontSize: 12, color: AppColors.blackLight));
    }
    final totalCount = r.genres.fold<int>(0, (a, e) => a + e.count);
    return Row(children: [
      SizedBox(
        width: 120,
        height: 120,
        child: CustomPaint(
          painter: _DonutPainter(
            values: r.genres.map((e) => e.count.toDouble()).toList(),
            colors: List.generate(r.genres.length, (i) => _palette[i % _palette.length]),
          ),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(children: [
          for (var i = 0; i < r.genres.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _palette[i % _palette.length], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(r.genres[i].label,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                Text('${(r.genres[i].count * 100 / totalCount).round()}%',
                    style: const TextStyle(fontSize: 12, color: AppColors.blackLight)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _barRow(String label, int value, int maxValue, Color color, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: Stack(children: [
            Container(
                height: 14,
                decoration: BoxDecoration(
                    color: AppColors.greyLight, borderRadius: BorderRadius.circular(7))),
            FractionallySizedBox(
              widthFactor: maxValue == 0 ? 0 : value / maxValue,
              child: Container(
                  height: 14,
                  decoration:
                      BoxDecoration(color: color, borderRadius: BorderRadius.circular(7))),
            ),
          ]),
        ),
        SizedBox(
            width: 36,
            child: Text(suffix ?? '$value',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
      ]),
    );
  }

  Widget _priceBody(InsightResult r, Color primary) {
    final maxCount = r.priceBuckets.fold<int>(0, (a, b) => math.max(a, b.count));
    if (maxCount == 0) {
      return const Text('価格が入力された記録がまだありません。',
          style: TextStyle(fontSize: 12, color: AppColors.blackLight));
    }
    String yen(double? v) => v == null ? '-' : '¥${Utils.formatCurrency(v.round())}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final b in r.priceBuckets) _barRow(b.label, b.count, maxCount, primary),
      const SizedBox(height: 10),
      Text('平均価格　贈った: ${yen(r.avgPriceSent)}　貰った: ${yen(r.avgPriceReceived)}',
          style: const TextStyle(fontSize: 12, color: AppColors.blackLight)),
    ]);
  }

  Widget _peopleBody(InsightResult r, Color primary) {
    if (r.people.isEmpty) {
      return const Text('相手が入力された記録がまだありません。',
          style: TextStyle(fontSize: 12, color: AppColors.blackLight));
    }
    final top = r.people.take(5).toList();
    return Column(children: [
      Row(children: [
        _legend(primary, '贈った'),
        const SizedBox(width: 12),
        _legend(AppColors.favoriteColor, '貰った'),
      ]),
      const SizedBox(height: 6),
      for (final p in top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
                width: 72,
                child: Text(p.name,
                    style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Row(children: [
                if (p.sent > 0)
                  Expanded(
                      flex: p.sent,
                      child: Container(height: 14, color: primary)),
                if (p.received > 0)
                  Expanded(
                      flex: p.received,
                      child: Container(height: 14, color: AppColors.favoriteColor)),
              ]),
            ),
            const SizedBox(width: 8),
            Text('${p.sent}/${p.received}', style: const TextStyle(fontSize: 11)),
          ]),
        ),
    ]);
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 11, color: AppColors.blackLight)),
      ]);

  Widget _seasonBody(InsightResult r, Color primary) {
    final maxM = r.monthly.reduce(math.max);
    final maxW = r.weekday.reduce(math.max);
    const w = ['月', '火', '水', '木', '金', '土', '日'];
    Widget columns(List<int> values, int maxV, List<String> labels) {
      return SizedBox(
        height: 90,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: maxV == 0 ? 0 : 60 * values[i] / maxV,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                      color: primary.withValues(alpha: values[i] == maxV && maxV > 0 ? 1 : 0.4),
                      borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: const TextStyle(fontSize: 10)),
              ]),
            ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('月ごと', style: TextStyle(fontSize: 12, color: AppColors.blackLight)),
      const SizedBox(height: 6),
      columns(r.monthly, maxM, [for (var i = 1; i <= 12; i++) '$i']),
      const SizedBox(height: 14),
      const Text('曜日ごと', style: TextStyle(fontSize: 12, color: AppColors.blackLight)),
      const SizedBox(height: 6),
      columns(r.weekday, maxW, w),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    const stroke = 22.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors;
}
