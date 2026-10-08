import 'package:flutter/material.dart';

Color themeColor = const Color(0xFF5bc787);
Color textColor = Colors.white;

/// ลำดับระดับความรุนแรงจากมากไปน้อย ใช้ทั้งเรียงลำดับและแสดงสรุป
const List<String> severityLevels = ['รุนแรง', 'ปานกลาง', 'น้อย'];

/// สีประจำระดับความรุนแรงของความเสียหาย ใช้ร่วมกันทั้งหน้าหลักและหน้าประวัติ
Color severityColor(String severity) {
  switch (severity) {
    case 'รุนแรง':
      return Colors.red.shade600;
    case 'ปานกลาง':
      return Colors.orange.shade700;
    case 'น้อย':
      return Colors.green.shade600;
    default:
      return Colors.grey;
  }
}

/// ค่ายิ่งมากยิ่งรุนแรง ใช้หาจุดที่รุนแรงที่สุดในภาพ
int severityRank(String severity) {
  switch (severity) {
    case 'รุนแรง':
      return 3;
    case 'ปานกลาง':
      return 2;
    case 'น้อย':
      return 1;
    default:
      return 0;
  }
}

/// คำตอบของ AI ที่ไม่ใช่ความเสียหายจริง (ไม่นับในสถิติ)
bool isRealDamage(String damage) {
  return damage.isNotEmpty &&
      damage != 'ไม่พบความเสียหาย' &&
      damage != 'ไม่ใช่ภาพถนน' &&
      damage != 'ไม่ทราบ';
}
