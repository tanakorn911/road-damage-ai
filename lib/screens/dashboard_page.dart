import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gpt_vision_leaf_detect/constants/constants.dart';

import '../services/history_storage.dart';

// ---------------------------------------------------
// หน้าสรุปสถิติ — นับจากความเสียหายทุกจุดในประวัติที่บันทึกไว้
// ---------------------------------------------------
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<DamageRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() { _loading = true; });
    final records = await HistoryStorage.load();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        title: const Text(
          'สรุปผลการสำรวจ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'โหลดใหม่',
            onPressed: _loadRecords,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // นับเฉพาะความเสียหายจริง ไม่รวม "ไม่พบความเสียหาย" / "ไม่ใช่ภาพถนน"
    final defects = _records
        .expand((r) => r.defects)
        .where((d) => isRealDamage(d.damage))
        .toList();

    if (defects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีข้อมูลความเสียหายให้สรุป',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final bySeverity = <String, int>{
      for (final level in severityLevels)
        level: defects.where((d) => d.severity == level).length,
    };

    final byType = <String, int>{};
    for (final defect in defects) {
      byType[defect.damage] = (byType[defect.damage] ?? 0) + 1;
    }
    final typeEntries = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _statCard('ภาพที่บันทึก', _records.length, Icons.photo_library,
                  themeColor),
              const SizedBox(width: 12),
              _statCard('จุดเสียหาย', defects.length,
                  Icons.report_problem_outlined, Colors.blue),
              const SizedBox(width: 12),
              _statCard('จุดรุนแรง', bySeverity['รุนแรง'] ?? 0,
                  Icons.warning_amber, severityColor('รุนแรง')),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            'สัดส่วนตามระดับความรุนแรง',
            Row(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: [
                        for (final entry in bySeverity.entries)
                          if (entry.value > 0)
                            PieChartSectionData(
                              value: entry.value.toDouble(),
                              color: severityColor(entry.key),
                              title: '${entry.value}',
                              radius: 42,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in bySeverity.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 12, color: severityColor(entry.key)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(entry.key)),
                              Text(
                                '${entry.value} จุด',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            'จำนวนตามประเภทความเสียหาย',
            Column(
              children: [
                for (final entry in typeEntries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(entry.key)),
                            Text(
                              '${entry.value}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            // เทียบกับประเภทที่พบมากที่สุด
                            value: entry.value / typeEntries.first.value,
                            minHeight: 10,
                            color: themeColor,
                            backgroundColor: Colors.grey[200],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
