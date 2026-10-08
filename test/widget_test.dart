import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gpt_vision_leaf_detect/main.dart';
import 'package:gpt_vision_leaf_detect/services/export_service.dart';
import 'package:gpt_vision_leaf_detect/services/history_storage.dart';

void main() {
  testWidgets('แอปเปิดได้และมีเมนูล่างครบ 4 แท็บ', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Road Damage AI'), findsOneWidget);
    for (final label in ['ตรวจ', 'ประวัติ', 'แผนที่', 'สรุป']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  test('รายการเก่าที่ไม่มี defects ยังอ่านได้เป็น 1 จุด', () {
    final record = DamageRecord.fromJson({
      'id': '1',
      'damageType': 'หลุมบ่อ',
      'severity': 'รุนแรง',
      'advice': '',
      'latitude': 16.47,
      'longitude': 102.82,
      'dateSaved': '2026-10-01T10:00:00.000',
    });

    expect(record.defects.length, 1);
    expect(record.defects.first.damage, 'หลุมบ่อ');
    expect(record.defects.first.severity, 'รุนแรง');
  });

  test('กรอบที่ได้ไม่ครบ 4 ค่าถูกทิ้ง และจุดรุนแรงสุดถูกเลือกเป็นหลัก', () {
    final defects = [
      Defect.fromJson({'damage': 'รอยแตกตามยาว', 'severity': 'น้อย', 'box': [0.1, 0.2]}),
      Defect.fromJson({'damage': 'หลุมบ่อ', 'severity': 'รุนแรง', 'box': [0.4, 0.2, 0.8, 1.4]}),
    ];

    expect(defects[0].box, isEmpty);
    expect(defects[1].box, [0.4, 0.2, 0.8, 1.0]); // ค่าเกิน 1 ถูกบีบให้อยู่ในภาพ
    expect(mostSevere(defects)!.damage, 'หลุมบ่อ');
  });

  test('CSV ครอบเครื่องหมายคำพูดและรวมทุกจุดในภาพ', () {
    final record = DamageRecord(
      id: '1',
      damageType: 'หลุมบ่อ',
      severity: 'รุนแรง',
      defects: const [
        Defect(damage: 'หลุมบ่อ', severity: 'รุนแรง'),
        Defect(damage: 'ร่องล้อ', severity: 'น้อย'),
      ],
      advice: 'ปะซ่อม "ด่วน"',
      latitude: 16.47,
      longitude: 102.82,
      dateSaved: DateTime(2026, 10, 1, 10),
    );

    final lines = ExportService.buildCsv([record]).split('\r\n');
    expect(lines.length, 2);
    expect(lines[1], contains('"หลุมบ่อ (รุนแรง); ร่องล้อ (น้อย)"'));
    expect(lines[1], contains('"ปะซ่อม ""ด่วน"""'));
  });
}
