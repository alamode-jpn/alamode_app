import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alamode_app/main.dart';
import 'package:alamode_app/services/auth_service.dart';
import 'package:alamode_app/services/person_service.dart';
import 'package:alamode_app/view/auth.dart';
import 'package:alamode_app/view/memo.dart' show Constants;
import 'package:alamode_app/view/person_detail.dart';
import 'package:alamode_app/widgets/person_icon.dart';

class PersonManagementScreen extends StatefulWidget {
  const PersonManagementScreen({super.key});

  @override
  State<PersonManagementScreen> createState() =>
      _PersonManagementScreenState();
}

class _PersonManagementScreenState extends State<PersonManagementScreen> {
  List<Map<String, dynamic>> _people = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.isLoggedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final people = await PersonService.instance.getAllWithEventCounts();
      if (!mounted) return;
      setState(() {
        _people = people;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateToLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (loggedIn == true) _load();
  }

  Future<void> _rename(Map<String, dynamic> person) async {
    final ctrl = TextEditingController(text: person['who_name'] as String);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('名前を編集'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: Constants.brandMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          decoration: const InputDecoration(labelText: '名前'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == person['who_name']) {
      return;
    }
    final error = await PersonService.instance
        .rename(person['who_id'] as String, newName);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.errorColor,
      ));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('名前を変更しました')));
    _load();
  }

  Future<void> _changeIcon(Map<String, dynamic> person) async {
    final name = person['who_name'] as String;
    final currentIndex = await PersonIconService.getIconIndex(name);
    if (!mounted) return;
    final result = await showDialog<int>(
      context: context,
      builder: (_) =>
          PersonIconPickerDialog(personName: name, currentIndex: currentIndex),
    );
    if (result != null) {
      await PersonIconService.saveIconIndex(name, result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(Map<String, dynamic> person) async {
    final count = person['event_count'] as int;
    final name = person['who_name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$nameを削除しますか？'),
        content: Text(
          count > 0
              ? 'この人物に紐づく贈った・もらった記録が$count件あります。削除すると、それらの記録も一緒に削除されます。\n\nこの操作は元に戻せません。'
              : 'この操作は元に戻せません。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PersonService.instance
          .deletePerson(person['who_id'] as String, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('削除しました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('削除に失敗しました: $e'),
        backgroundColor: AppColors.errorColor,
      ));
    }
  }

  Future<void> _merge(Map<String, dynamic> fromPerson) async {
    final candidates =
        _people.where((p) => p['who_id'] != fromPerson['who_id']).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('統合できる他の人物がいません')));
      return;
    }
    final target = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${fromPerson['who_name']}をどの人物に統合しますか？'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, i) {
              final c = candidates[i];
              return ListTile(
                leading:
                    PersonAvatar(personName: c['who_name'] as String, radius: 16),
                title: Text(c['who_name'] as String),
                subtitle: Text('記録 ${c['event_count']}件'),
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        ],
      ),
    );
    if (target == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('統合しますか？'),
        content: Text(
          '${fromPerson['who_name']}（記録${fromPerson['event_count']}件）を'
          '${target['who_name']}に統合します。\n\n'
          '${fromPerson['who_name']}の記録は全て${target['who_name']}の記録になり、'
          '${fromPerson['who_name']}は削除されます。この操作は元に戻せません。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('統合する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PersonService.instance.merge(
        fromWhoId: fromPerson['who_id'] as String,
        fromWhoName: fromPerson['who_name'] as String,
        toWhoId: target['who_id'] as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('統合しました')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('統合に失敗しました: $e'),
        backgroundColor: AppColors.errorColor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('人物管理')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '人物管理はログインすると使えます。\n'
                  'ログインしていない間に登録した「贈った相手」は、\n'
                  '端末内のみで管理されています。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.blackLight, height: 1.6),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _navigateToLogin,
                  child: const Text('ログイン / 新規登録'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('人物管理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _people.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(top: 80),
                              child: Text(
                                'まだ人物が登録されていません。\n'
                                'Memoで「贈った相手」を入力すると、ここに表示されます。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.blackLight),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _people.length,
                          itemBuilder: (context, index) {
                            final person = _people[index];
                            final birthdayStr =
                                person['who_birthday'] as String?;
                            final birthday = birthdayStr == null
                                ? null
                                : DateTime.tryParse(birthdayStr);
                            final daysUntil = daysUntilNextBirthday(birthday);
                            return ListTile(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PersonDetailScreen(
                                    whoId: person['who_id'] as String,
                                    whoName: person['who_name'] as String,
                                  ),
                                ),
                              ),
                              leading: PersonAvatar(
                                personName: person['who_name'] as String,
                                radius: 20,
                              ),
                              title: Text(person['who_name'] as String),
                              subtitle: Text(
                                daysUntil != null && daysUntil <= 14
                                    ? '記録 ${person['event_count']}件 ・ 🎂 あと$daysUntil日'
                                    : '記録 ${person['event_count']}件',
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: '操作',
                                onSelected: (action) {
                                  switch (action) {
                                    case 'rename':
                                      _rename(person);
                                      break;
                                    case 'icon':
                                      _changeIcon(person);
                                      break;
                                    case 'merge':
                                      _merge(person);
                                      break;
                                    case 'delete':
                                      _delete(person);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'rename', child: Text('名前を編集')),
                                  PopupMenuItem(
                                      value: 'icon', child: Text('アイコンを変更')),
                                  PopupMenuItem(
                                      value: 'merge', child: Text('他の人物に統合')),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('削除',
                                        style: TextStyle(
                                            color: AppColors.errorColor)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
