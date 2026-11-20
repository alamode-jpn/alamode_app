import 'package:alamode_app/main.dart';
import 'package:alamode_app/services/auth_service.dart';
import 'package:alamode_app/widgets/person_icon.dart';

/// 誕生日（月日のみ使用、年は無視）から「次の誕生日まであと何日か」を計算する。
/// 今日が誕生日の場合は0を返す。
int? daysUntilNextBirthday(DateTime? birthday) {
  if (birthday == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var next = _safeAnniversary(today.year, birthday.month, birthday.day);
  if (next.isBefore(today)) {
    next = _safeAnniversary(today.year + 1, birthday.month, birthday.day);
  }
  return next.difference(today).inDays;
}

/// 2/29生まれの誕生日を非うるう年の年に当てはめる場合など、
/// 指定した年にその月日が存在しない場合は月末日にクランプする。
DateTime _safeAnniversary(int year, int month, int day) {
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDayOfMonth ? lastDayOfMonth : day);
}

/// 「贈った相手」（whoテーブル）の管理をまとめるサービス。
/// whoテーブルはログインユーザーのみが持つため、全メソッドはログイン中にのみ呼び出すこと。
class PersonService {
  static final PersonService instance = PersonService._();
  PersonService._();

  /// 人物一覧を、それぞれに紐づくevent（贈った・もらった記録）件数つきで取得する。
  Future<List<Map<String, dynamic>>> getAllWithEventCounts() async {
    final uid = AuthService.instance.userId!;
    final whoRows = await supabase
        .from('who')
        .select('who_id, who_name, who_birthday')
        .eq('user_id', uid)
        .order('who_name');
    final eventRows =
        await supabase.from('event').select('who_id').eq('user_id', uid);

    final counts = <String, int>{};
    for (final e in (eventRows as List)) {
      final wid = e['who_id']?.toString();
      if (wid != null) counts[wid] = (counts[wid] ?? 0) + 1;
    }

    return (whoRows as List).map((w) {
      final wid = w['who_id'].toString();
      return {
        'who_id': wid,
        'who_name': w['who_name'] as String,
        'who_birthday': w['who_birthday'] as String?,
        'event_count': counts[wid] ?? 0,
      };
    }).toList();
  }

  /// 1人物の情報（アイコン選択・誕生日編集時の最新状態取得用）。
  Future<Map<String, dynamic>?> getPerson(String whoId) async {
    final uid = AuthService.instance.userId!;
    return await supabase
        .from('who')
        .select('who_id, who_name, who_birthday')
        .eq('who_id', whoId)
        .eq('user_id', uid)
        .maybeSingle();
  }

  /// 誕生日を更新する（null指定で未設定に戻す）。
  Future<void> updateBirthday(String whoId, DateTime? birthday) async {
    final uid = AuthService.instance.userId!;
    await supabase.from('who').update({
      'who_birthday': birthday?.toIso8601String().substring(0, 10),
      'who_update': DateTime.now().toIso8601String(),
    }).eq('who_id', whoId).eq('user_id', uid);
  }

  /// 指定日数以内に誕生日を迎える人物を、誕生日が近い順に返す
  /// （年は無視し、月日だけで「次の誕生日まで何日か」を計算する）。
  Future<List<Map<String, dynamic>>> getUpcomingBirthdays(
      {int withinDays = 14}) async {
    final uid = AuthService.instance.userId!;
    final rows = await supabase
        .from('who')
        .select('who_id, who_name, who_birthday')
        .eq('user_id', uid);

    final result = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final bdayStr = r['who_birthday'] as String?;
      if (bdayStr == null) continue;
      final bday = DateTime.tryParse(bdayStr);
      if (bday == null) continue;
      final days = daysUntilNextBirthday(bday);
      if (days != null && days <= withinDays) {
        result.add({
          'who_id': r['who_id'].toString(),
          'who_name': r['who_name'] as String,
          'who_birthday': bdayStr,
          'days_until': days,
        });
      }
    }
    result.sort(
        (a, b) => (a['days_until'] as int).compareTo(b['days_until'] as int));
    return result;
  }

  /// 人物名を変更する。本人以外に同名の人物が既にいる場合はエラーメッセージを返す
  /// （同名のまま2行残ると、以後の自動名寄せ(getOrCreateWho)が壊れるため）。
  /// 成功時はnullを返す。
  Future<String?> rename(String whoId, String newName) async {
    final uid = AuthService.instance.userId!;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return '名前を入力してください';

    final duplicate = await supabase
        .from('who')
        .select('who_id')
        .eq('user_id', uid)
        .eq('who_name', trimmed)
        .maybeSingle();
    if (duplicate != null && duplicate['who_id'].toString() != whoId) {
      return 'すでに同じ名前の人物が登録されています。「統合」を使ってください。';
    }

    final current = await supabase
        .from('who')
        .select('who_name')
        .eq('who_id', whoId)
        .eq('user_id', uid)
        .maybeSingle();
    final oldName = current?['who_name'] as String?;

    await supabase.from('who').update({
      'who_name': trimmed,
      'who_update': DateTime.now().toIso8601String(),
    }).eq('who_id', whoId).eq('user_id', uid);

    if (oldName != null && oldName != trimmed) {
      await PersonIconService.renameKey(oldName, trimmed);
    }
    return null;
  }

  /// 人物を削除する。紐づくevent（贈った・もらった記録）も全て削除する。
  /// それぞれのeventに紐づくuseritemも、他のeventから参照されていなければあわせて削除する
  /// （memo.dartの単体削除処理と同じルール）。
  Future<void> deletePerson(String whoId, String whoName) async {
    final uid = AuthService.instance.userId!;
    final events = await supabase
        .from('event')
        .select('event_id, useritem_id')
        .eq('who_id', whoId)
        .eq('user_id', uid);

    for (final e in (events as List)) {
      final eventId = e['event_id'].toString();
      await supabase
          .from('event')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', uid);
      final useritemId = e['useritem_id'];
      if (useritemId != null) {
        final others = await supabase
            .from('event')
            .select('event_id')
            .eq('useritem_id', useritemId);
        if ((others as List).isEmpty) {
          await supabase
              .from('useritem')
              .delete()
              .eq('useritem_id', useritemId)
              .eq('user_id', uid);
        }
      }
    }

    await supabase.from('who').delete().eq('who_id', whoId).eq('user_id', uid);
    await PersonIconService.removeKey(whoName);
  }

  /// fromWhoIdの人物の記録を全てtoWhoIdへ付け替えたうえで、fromWhoIdを削除する（重複統合）。
  Future<void> merge({
    required String fromWhoId,
    required String fromWhoName,
    required String toWhoId,
  }) async {
    final uid = AuthService.instance.userId!;
    await supabase
        .from('event')
        .update({'who_id': toWhoId})
        .eq('who_id', fromWhoId)
        .eq('user_id', uid);
    await supabase
        .from('who')
        .delete()
        .eq('who_id', fromWhoId)
        .eq('user_id', uid);
    await PersonIconService.removeKey(fromWhoName);
  }
}
