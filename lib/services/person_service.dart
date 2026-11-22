import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
/// ログイン中はSupabaseのwhoテーブルを使う。未ログイン(ゲスト)時は、
/// 端末内のpresent_list（Memoの記録）に埋め込まれたpresent_who文字列の
/// 集合を「人物一覧」とみなし、名前そのものをwho_id代わりに使う簡易実装で
/// 同等の機能（一覧・名前変更・統合・削除・誕生日）を提供する。
class PersonService {
  static final PersonService instance = PersonService._();
  PersonService._();

  // memo.dartのConstants.presentListKeyと同じキー（循環import回避のため文字列を直接保持）。
  static const String _presentListKey = 'present_list';
  static const String _guestBirthdaysKey = 'guest_person_birthdays';

  Future<List<Map<String, dynamic>>> _loadGuestPresents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_presentListKey) ?? [];
    return list
        .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
        .toList();
  }

  Future<void> _saveGuestPresents(List<Map<String, dynamic>> presents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _presentListKey, presents.map((p) => jsonEncode(p)).toList());
  }

  Future<Map<String, String>> _loadGuestBirthdays() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestBirthdaysKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> _saveGuestBirthdays(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guestBirthdaysKey, jsonEncode(map));
  }

  /// 人物一覧を、それぞれに紐づくevent（贈った・もらった記録）件数つきで取得する。
  Future<List<Map<String, dynamic>>> getAllWithEventCounts() async {
    if (!AuthService.instance.isLoggedIn) {
      final presents = await _loadGuestPresents();
      final birthdays = await _loadGuestBirthdays();
      final counts = <String, int>{};
      for (final p in presents) {
        final who = (p['present_who'] as String?)?.trim();
        if (who == null || who.isEmpty) continue;
        counts[who] = (counts[who] ?? 0) + 1;
      }
      final names = counts.keys.toList()..sort();
      return names
          .map((name) => {
                'who_id': name,
                'who_name': name,
                'who_birthday': birthdays[name],
                'event_count': counts[name] ?? 0,
              })
          .toList();
    }
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
    if (!AuthService.instance.isLoggedIn) {
      final all = await getAllWithEventCounts();
      for (final p in all) {
        if (p['who_id'] == whoId) return p;
      }
      return null;
    }
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
    if (!AuthService.instance.isLoggedIn) {
      final birthdays = await _loadGuestBirthdays();
      if (birthday == null) {
        birthdays.remove(whoId);
      } else {
        birthdays[whoId] = birthday.toIso8601String().substring(0, 10);
      }
      await _saveGuestBirthdays(birthdays);
      return;
    }
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
    if (!AuthService.instance.isLoggedIn) {
      final birthdays = await _loadGuestBirthdays();
      final result = <Map<String, dynamic>>[];
      birthdays.forEach((name, bdayStr) {
        final bday = DateTime.tryParse(bdayStr);
        if (bday == null) return;
        final days = daysUntilNextBirthday(bday);
        if (days != null && days <= withinDays) {
          result.add({
            'who_id': name,
            'who_name': name,
            'who_birthday': bdayStr,
            'days_until': days,
          });
        }
      });
      result.sort((a, b) =>
          (a['days_until'] as int).compareTo(b['days_until'] as int));
      return result;
    }
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
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return '名前を入力してください';

    if (!AuthService.instance.isLoggedIn) {
      if (trimmed == whoId) return null;
      final presents = await _loadGuestPresents();
      final existingNames = presents
          .map((p) => (p['present_who'] as String?)?.trim())
          .whereType<String>()
          .toSet();
      if (existingNames.contains(trimmed)) {
        return 'すでに同じ名前の人物が登録されています。「統合」を使ってください。';
      }
      for (final p in presents) {
        if ((p['present_who'] as String?)?.trim() == whoId) {
          p['present_who'] = trimmed;
        }
      }
      await _saveGuestPresents(presents);
      final birthdays = await _loadGuestBirthdays();
      final existingBirthday = birthdays.remove(whoId);
      if (existingBirthday != null) {
        birthdays[trimmed] = existingBirthday;
        await _saveGuestBirthdays(birthdays);
      }
      await PersonIconService.renameKey(whoId, trimmed);
      return null;
    }

    final uid = AuthService.instance.userId!;

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
    if (!AuthService.instance.isLoggedIn) {
      final presents = await _loadGuestPresents();
      presents.removeWhere(
          (p) => (p['present_who'] as String?)?.trim() == whoId);
      await _saveGuestPresents(presents);
      final birthdays = await _loadGuestBirthdays();
      if (birthdays.remove(whoId) != null) {
        await _saveGuestBirthdays(birthdays);
      }
      await PersonIconService.removeKey(whoName);
      return;
    }
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
    if (!AuthService.instance.isLoggedIn) {
      final presents = await _loadGuestPresents();
      for (final p in presents) {
        if ((p['present_who'] as String?)?.trim() == fromWhoId) {
          p['present_who'] = toWhoId;
        }
      }
      await _saveGuestPresents(presents);
      final birthdays = await _loadGuestBirthdays();
      if (birthdays.remove(fromWhoId) != null) {
        await _saveGuestBirthdays(birthdays);
      }
      await PersonIconService.removeKey(fromWhoName);
      return;
    }
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
