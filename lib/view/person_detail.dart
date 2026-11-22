import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:alamode_app/main.dart';
import 'package:alamode_app/services/person_service.dart';
import 'package:alamode_app/view/memo.dart';
import 'package:alamode_app/widgets/category_placeholder.dart';
import 'package:alamode_app/widgets/person_icon.dart';

class PersonDetailScreen extends StatefulWidget {
  final String whoId;
  final String whoName;

  const PersonDetailScreen(
      {super.key, required this.whoId, required this.whoName});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _presentService = PresentManagementService();
  final currencyFormat = NumberFormat('#,###');

  List<Map<String, dynamic>> _presents = [];
  DateTime? _birthday;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final presents =
          await _presentService.getPresentsForWho(widget.whoId);
      final person = await PersonService.instance.getPerson(widget.whoId);
      final bdayStr = person?['who_birthday'] as String?;
      if (!mounted) return;
      setState(() {
        _presents = presents;
        _birthday = bdayStr == null ? null : DateTime.tryParse(bdayStr);
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

  Future<void> _pickBirthday() async {
    final primary = Theme.of(context).primaryColor;
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: ColorScheme.light(primary: primary)),
        child: child!,
      ),
    );
    if (picked == null) return;
    try {
      await PersonService.instance.updateBirthday(widget.whoId, picked);
      if (!mounted) return;
      setState(() => _birthday = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('保存に失敗しました: $e'),
        backgroundColor: AppColors.errorColor,
      ));
    }
  }

  Future<void> _clearBirthday() async {
    try {
      await PersonService.instance.updateBirthday(widget.whoId, null);
      if (!mounted) return;
      setState(() => _birthday = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('更新に失敗しました: $e'),
        backgroundColor: AppColors.errorColor,
      ));
    }
  }

  Future<void> _navigateToEdit(Map<String, dynamic> present) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PresentFormWidget(
          initialPresent: present,
          presentService: _presentService,
        ),
      ),
    );
    if (result == true) await _load();
  }

  Map<String, dynamic> _buildStats() {
    int sentCount = 0;
    int receivedCount = 0;
    int sentTotal = 0;
    int receivedTotal = 0;
    int reactionSum = 0;
    int reactionCount = 0;
    final genreCounts = <String, int>{};

    for (final p in _presents) {
      final price = (p['present_price'] as num?)?.toInt() ?? 0;
      final reaction = (p['present_reaction'] as num?)?.toInt() ?? 0;
      if (p['present_type'] == 'sent') {
        sentCount++;
        sentTotal += price;
      } else {
        receivedCount++;
        receivedTotal += price;
      }
      if (reaction > 0) {
        reactionSum += reaction;
        reactionCount++;
      }
      final genre = p['present_genre'] as String? ?? '';
      for (final g in genre.split(',').map((s) => s.trim())) {
        if (g.isEmpty) continue;
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }

    String? topGenre;
    int topGenreCount = 0;
    genreCounts.forEach((g, c) {
      if (c > topGenreCount) {
        topGenre = g;
        topGenreCount = c;
      }
    });

    return {
      'sentCount': sentCount,
      'receivedCount': receivedCount,
      'sentTotal': sentTotal,
      'receivedTotal': receivedTotal,
      'avgReaction': reactionCount == 0 ? null : reactionSum / reactionCount,
      'topGenre': topGenre,
    };
  }

  Widget _buildStatsCard() {
    final stats = _buildStats();
    final avgReaction = stats['avgReaction'] as double?;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowColor, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  '贈った',
                  '${stats['sentCount']}件 / ¥${currencyFormat.format(stats['sentTotal'])}',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'もらった',
                  '${stats['receivedCount']}件 / ¥${currencyFormat.format(stats['receivedTotal'])}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'よく選ぶジャンル',
                  stats['topGenre'] as String? ?? '-',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  '平均反応',
                  avgReaction == null
                      ? '-'
                      : '★${avgReaction.toStringAsFixed(1)}',
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.cake_outlined, size: 18, color: AppColors.blackLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _birthday == null
                      ? '誕生日が未設定です'
                      : '誕生日: ${_birthday!.month}月${_birthday!.day}日',
                  style: const TextStyle(fontSize: 13, color: AppColors.blackDark),
                ),
              ),
              TextButton(
                onPressed: _pickBirthday,
                child: Text(_birthday == null ? '登録する' : '変更'),
              ),
              if (_birthday != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '誕生日を削除',
                  onPressed: _clearBirthday,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.blackLight)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPresentCard(Map<String, dynamic> present) {
    final isSent = present['present_type'] == 'sent';
    final imageUrl = present['present_imageurl'] as String?;
    final price = (present['present_price'] as num?)?.toInt() ?? 0;
    final reaction = (present['present_reaction'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => _navigateToEdit(present),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadowColor, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imageUrl != null
                    ? CommonWidgets.buildImage(imageUrl, _presentService)
                    : CategoryPlaceholder(
                        category: present['present_genre'] as String?,
                        height: 56),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isSent ? Icons.card_giftcard : Icons.restaurant,
                        size: 12,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isSent ? '贈った' : '貰った',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                          (present['present_date'] as String? ?? '')
                              .replaceAll('-', '/'),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.blackLight)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    present['present_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('¥${currencyFormat.format(price)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.blackLight)),
                      if (reaction > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.star, size: 12, color: AppColors.starColor),
                        Text(' $reaction',
                            style: const TextStyle(fontSize: 12, color: AppColors.blackLight)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            PersonAvatar(personName: widget.whoName, radius: 16),
            const SizedBox(width: 10),
            Text(widget.whoName),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      _buildStatsCard(),
                      const SizedBox(height: 8),
                      if (_presents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('まだ記録がありません',
                                style: TextStyle(color: AppColors.blackLight)),
                          ),
                        )
                      else
                        ..._presents.map(_buildPresentCard),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}
