import 'package:flutter_test/flutter_test.dart';
import 'package:alamode_app/services/insight_service.dart';

Map<String, dynamic> p({
  String type = 'sent',
  String genre = 'クッキー',
  int price = 1000,
  String who = '',
  String brand = '',
  int reaction = 0,
  String date = '2026-03-01',
}) =>
    {
      'present_type': type,
      'present_genre': genre,
      'present_price': price,
      'present_who': who,
      'present_brand': brand,
      'present_reaction': reaction,
      'present_date': date,
    };

void main() {
  test('空データでも落ちず、次の解放が案内される', () {
    final r = InsightService.analyze([]);
    expect(r.total, 0);
    expect(r.nextUnlock?.requiredCount, InsightService.unlockGenre);
    expect(r.persona, isNull);
  });

  test('ジャンルはカンマ区切りで複数カウントされる', () {
    final r = InsightService.analyze([p(genre: 'クッキー, 和菓子'), p(genre: '和菓子')]);
    expect(r.genres.first.label, '和菓子');
    expect(r.genres.first.count, 2);
  });

  test('反応が最も良いジャンルは2件以上のジャンルから選ばれる', () {
    final r = InsightService.analyze([
      p(genre: 'ショコラ', reaction: 5),
      p(genre: 'クッキー', reaction: 4),
      p(genre: 'クッキー', reaction: 4),
    ]);
    expect(r.bestGenre, 'クッキー');
    expect(r.bestGenreAvg, 4.0);
  });

  test('価格帯の境界値と未入力(0円)の除外', () {
    final r = InsightService.analyze([p(price: 0), p(price: 499), p(price: 500), p(price: 5000)]);
    expect(r.priceBuckets.map((b) => b.count).toList(), [1, 1, 0, 0, 0, 1]);
  });

  test('人別の贈った/貰った集計', () {
    final r = InsightService.analyze([
      p(who: 'A'), p(who: 'A'), p(who: 'A', type: 'received'), p(who: 'B'),
    ]);
    expect(r.people.first.name, 'A');
    expect(r.people.first.sent, 2);
    expect(r.people.first.received, 1);
  });

  test('10件以上でタイプが判定される', () {
    final r = InsightService.analyze(
        List.generate(10, (i) => p(brand: 'X', who: 'A$i')));
    expect(r.persona, '定番を愛する安心派');
    expect(r.nextUnlock, isNull);
  });
}
