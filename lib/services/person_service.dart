import 'package:alamode_app/main.dart';
import 'package:alamode_app/services/auth_service.dart';
import 'package:alamode_app/widgets/person_icon.dart';

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
        .select('who_id, who_name')
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
        'event_count': counts[wid] ?? 0,
      };
    }).toList();
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
