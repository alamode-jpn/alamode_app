// Memo（贈った/貰った記録）から統計的な「発見」を計算する純粋ロジック。
// 外部通信を一切行わないため、記録データがサーバーやAIに送信されることはない。
// UI(`lib/view/insights.dart`)とは分離しており、単体テストで検証できる。

class CountEntry {
  final String label;
  final int count;
  const CountEntry(this.label, this.count);
}

class PersonStat {
  final String name;
  final int sent;
  final int received;
  const PersonStat(this.name, this.sent, this.received);
  int get total => sent + received;
}

class PriceBucket {
  final String label;
  final int count;
  const PriceBucket(this.label, this.count);
}

/// 次に解放される発見の案内（記録を増やす動機づけ）。
class NextUnlock {
  final int requiredCount;
  final String title;
  const NextUnlock(this.requiredCount, this.title);
}

class InsightResult {
  final int total;
  final int sentCount;
  final int receivedCount;
  final List<CountEntry> genres; // 件数の多い順
  final List<PriceBucket> priceBuckets;
  final double? avgPriceSent;
  final double? avgPriceReceived;
  final String? bestGenre; // 贈ったときの反応が最も良いジャンル
  final double? bestGenreAvg;
  final List<PersonStat> people; // 合計の多い順
  final List<int> monthly; // index0=1月 … index11=12月（全期間の合計）
  final List<int> weekday; // index0=月 … index6=日
  final double? repeatBrandRate; // 同じブランドを2回以上記録した割合(0..1)
  final String? topBrand;
  final double? avgReaction; // 贈った記録の平均反応
  final String? persona;
  final String? personaDescription;
  final List<String> trivia; // 「へぇ」と思える小さな発見の文章
  final NextUnlock? nextUnlock;

  const InsightResult({
    required this.total,
    required this.sentCount,
    required this.receivedCount,
    required this.genres,
    required this.priceBuckets,
    required this.avgPriceSent,
    required this.avgPriceReceived,
    required this.bestGenre,
    required this.bestGenreAvg,
    required this.people,
    required this.monthly,
    required this.weekday,
    required this.repeatBrandRate,
    required this.topBrand,
    required this.avgReaction,
    required this.persona,
    required this.personaDescription,
    required this.trivia,
    required this.nextUnlock,
  });
}

class InsightService {
  // 各発見が解放される記録件数。
  static const int unlockGenre = 3;
  static const int unlockPrice = 5;
  static const int unlockPeople = 5;
  static const int unlockSeason = 8;
  static const int unlockPersona = 10;

  static const List<NextUnlock> unlocks = [
    NextUnlock(unlockGenre, 'ジャンルの好み'),
    NextUnlock(unlockPrice, '価格帯の傾向'),
    NextUnlock(unlockPeople, '人とのお菓子の関係'),
    NextUnlock(unlockSeason, '季節・曜日のリズム'),
    NextUnlock(unlockPersona, 'あなたのお菓子タイプ'),
  ];

  static int _price(Map<String, dynamic> p) {
    final v = p['present_price'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _reaction(Map<String, dynamic> p) {
    final v = p['present_reaction'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static bool _isSent(Map<String, dynamic> p) => p['present_type'] != 'received';

  static List<String> _genresOf(Map<String, dynamic> p) {
    final raw = (p['present_genre'] as String?) ?? '';
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<CountEntry> _sortedCounts(Map<String, int> m) {
    final list = m.entries.map((e) => CountEntry(e.key, e.value)).toList()
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
    return list;
  }

  static const List<int> _priceEdges = [500, 1000, 2000, 3000, 5000];

  static List<PriceBucket> _buckets(List<int> prices) {
    final counts = List<int>.filled(_priceEdges.length + 1, 0);
    for (final price in prices) {
      var i = 0;
      while (i < _priceEdges.length && price >= _priceEdges[i]) {
        i++;
      }
      counts[i]++;
    }
    String label(int i) {
      if (i == 0) return '〜¥${_priceEdges[0] - 1}';
      if (i == _priceEdges.length) return '¥${_priceEdges.last}〜';
      return '¥${_priceEdges[i - 1]}〜';
    }

    return [for (var i = 0; i < counts.length; i++) PriceBucket(label(i), counts[i])];
  }

  static InsightResult analyze(List<Map<String, dynamic>> presents) {
    final total = presents.length;
    final sent = presents.where(_isSent).toList();
    final received = presents.where((p) => !_isSent(p)).toList();

    // ジャンル
    final genreCounts = <String, int>{};
    for (final p in presents) {
      for (final g in _genresOf(p)) {
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }
    final genres = _sortedCounts(genreCounts);

    // 価格（0円=未入力は除外）
    final pricedAll = presents.map(_price).where((v) => v > 0).toList();
    final pricedSent = sent.map(_price).where((v) => v > 0).toList();
    final pricedReceived = received.map(_price).where((v) => v > 0).toList();
    double? avg(List<int> l) =>
        l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;

    // 贈った時の反応が良いジャンル（2件以上のジャンルのみ対象）
    String? bestGenre;
    double? bestGenreAvg;
    final reactionByGenre = <String, List<int>>{};
    for (final p in sent) {
      final r = _reaction(p);
      if (r <= 0) continue;
      for (final g in _genresOf(p)) {
        reactionByGenre.putIfAbsent(g, () => []).add(r);
      }
    }
    reactionByGenre.forEach((g, rs) {
      if (rs.length < 2) return;
      final a = rs.reduce((x, y) => x + y) / rs.length;
      if (bestGenreAvg == null || a > bestGenreAvg!) {
        bestGenre = g;
        bestGenreAvg = a;
      }
    });
    final sentReactions = sent.map(_reaction).where((r) => r > 0).toList();
    final avgReaction =
        sentReactions.isEmpty ? null : sentReactions.reduce((a, b) => a + b) / sentReactions.length;

    // 人
    final sentBy = <String, int>{};
    final recvBy = <String, int>{};
    for (final p in presents) {
      final who = ((p['present_who'] as String?) ?? '').trim();
      if (who.isEmpty) continue;
      final m = _isSent(p) ? sentBy : recvBy;
      m[who] = (m[who] ?? 0) + 1;
    }
    final names = {...sentBy.keys, ...recvBy.keys};
    final people = names
        .map((n) => PersonStat(n, sentBy[n] ?? 0, recvBy[n] ?? 0))
        .toList()
      ..sort((a, b) {
        final c = b.total.compareTo(a.total);
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    // 月・曜日
    final monthly = List<int>.filled(12, 0);
    final weekday = List<int>.filled(7, 0);
    var dated = 0;
    for (final p in presents) {
      final d = DateTime.tryParse((p['present_date'] as String?) ?? '');
      if (d == null) continue;
      dated++;
      monthly[d.month - 1]++;
      weekday[d.weekday - 1]++;
    }

    // ブランドの繰り返し
    final brandCounts = <String, int>{};
    for (final p in presents) {
      final b = ((p['present_brand'] as String?) ?? '').trim();
      if (b.isEmpty) continue;
      brandCounts[b] = (brandCounts[b] ?? 0) + 1;
    }
    double? repeatRate;
    String? topBrand;
    if (brandCounts.isNotEmpty) {
      final totalBrand = brandCounts.values.reduce((a, b) => a + b);
      final repeated =
          brandCounts.values.where((c) => c >= 2).fold<int>(0, (a, c) => a + c);
      repeatRate = repeated / totalBrand;
      final top = _sortedCounts(brandCounts).first;
      if (top.count >= 2) topBrand = top.label;
    }

    // タイプ判定（10件以上）
    String? persona;
    String? personaDesc;
    if (total >= unlockPersona) {
      final sentRatio = sent.length / total;
      if (repeatRate != null && repeatRate >= 0.5) {
        persona = '定番を愛する安心派';
        personaDesc = '気に入ったブランドを何度も選ぶタイプ。外さない選択が得意です。';
      } else if (repeatRate != null && repeatRate <= 0.15 && brandCounts.length >= 6) {
        persona = '新作を追う開拓派';
        personaDesc = 'いつも違うブランドに挑戦するタイプ。お菓子の世界を広げています。';
      } else if (sentRatio >= 0.65) {
        persona = '贈り上手なギバー';
        personaDesc = '贈る機会が多めのタイプ。相手を思い浮かべて選ぶ時間を楽しんでいます。';
      } else if (sentRatio <= 0.35) {
        persona = '愛されレシーバー';
        personaDesc = 'もらう機会が多めのタイプ。周りの人から素敵なお菓子が集まっています。';
      } else {
        persona = '贈って貰ってバランス派';
        personaDesc = '贈る・貰うがちょうど良く循環している、素敵な関係づくりのタイプです。';
      }
    }

    // 豆知識（データから言える範囲のみ）
    final trivia = <String>[];
    if (genres.isNotEmpty && total >= unlockGenre) {
      final top = genres.first;
      trivia.add('一番多いジャンルは「${top.label}」。全体の${(top.count * 100 / total).round()}%を占めています。');
    }
    final a1 = avg(pricedSent);
    final a2 = avg(pricedReceived);
    if (a1 != null && a2 != null && total >= unlockPrice) {
      final diff = (a1 - a2).round();
      if (diff.abs() >= 100) {
        trivia.add(diff > 0
            ? '贈るお菓子は、貰うお菓子より平均¥${diff.abs()}ほど高めです。'
            : '貰うお菓子は、贈るお菓子より平均¥${diff.abs()}ほど高めです。');
      } else {
        trivia.add('贈るお菓子と貰うお菓子の価格帯はほぼ同じです。');
      }
    }
    if (bestGenre != null) {
      trivia.add('贈ったとき、相手の反応が一番良いのは「$bestGenre」（平均★${bestGenreAvg!.toStringAsFixed(1)}）。');
    }
    if (people.isNotEmpty && total >= unlockPeople) {
      final balanced = people.where((p) => p.sent > 0 && p.received > 0).toList();
      if (balanced.isNotEmpty) {
        trivia.add('「${balanced.first.name}」さんとは、お菓子をやり取りし合う関係です。');
      }
      final giveOnly = people.where((p) => p.sent >= 2 && p.received == 0).toList();
      if (giveOnly.isNotEmpty) {
        trivia.add('「${giveOnly.first.name}」さんには${giveOnly.first.sent}回贈っていますが、まだ貰ったことはありません。');
      }
    }
    if (dated >= unlockSeason) {
      final maxM = monthly.reduce((a, b) => a > b ? a : b);
      if (maxM >= 2) {
        trivia.add('${monthly.indexOf(maxM) + 1}月に一番お菓子が動いています。');
      }
      final maxW = weekday.reduce((a, b) => a > b ? a : b);
      if (maxW >= 2) {
        const w = ['月', '火', '水', '木', '金', '土', '日'];
        trivia.add('${w[weekday.indexOf(maxW)]}曜日の記録が一番多いです。');
      }
    }
    if (topBrand != null) {
      trivia.add('「$topBrand」は何度も登場するお気に入りのブランドです。');
    }

    NextUnlock? next;
    for (final u in unlocks) {
      if (total < u.requiredCount) {
        next = u;
        break;
      }
    }

    return InsightResult(
      total: total,
      sentCount: sent.length,
      receivedCount: received.length,
      genres: genres,
      priceBuckets: _buckets(pricedAll),
      avgPriceSent: a1,
      avgPriceReceived: a2,
      bestGenre: bestGenre,
      bestGenreAvg: bestGenreAvg,
      people: people,
      monthly: monthly,
      weekday: weekday,
      repeatBrandRate: repeatRate,
      topBrand: topBrand,
      avgReaction: avgReaction,
      persona: persona,
      personaDescription: personaDesc,
      trivia: trivia,
      nextUnlock: next,
    );
  }
}
