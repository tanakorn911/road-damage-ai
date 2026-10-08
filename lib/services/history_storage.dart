import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';

/// ความเสียหาย 1 จุดที่ AI ตรวจพบในภาพ
class Defect {
  final String damage;
  final String severity;

  /// กรอบตำแหน่ง [ymin, xmin, ymax, xmax] ค่า 0.0-1.0 (ว่างถ้าไม่มีกรอบ)
  final List<double> box;

  const Defect({
    required this.damage,
    this.severity = '',
    this.box = const [],
  });

  Map<String, dynamic> toJson() => {
        'damage': damage,
        'severity': severity,
        'box': box,
      };

  factory Defect.fromJson(Map<String, dynamic> json) {
    final rawBox = json['box'];
    final parsedBox = rawBox is List
        ? rawBox
            .map((e) => double.tryParse(e.toString()))
            .whereType<double>()
            .map((e) => e.clamp(0.0, 1.0).toDouble())
            .toList()
        : const <double>[];

    return Defect(
      damage: json['damage']?.toString() ?? 'ไม่ทราบ',
      severity: json['severity']?.toString() ?? '',
      // ต้องได้ครบ 4 ค่า ไม่งั้นวาดกรอบผิดตำแหน่ง
      box: parsedBox.length == 4 ? parsedBox : const <double>[],
    );
  }
}

/// จุดที่รุนแรงที่สุดในรายการ (null ถ้ารายการว่าง)
Defect? mostSevere(List<Defect> defects) {
  if (defects.isEmpty) return null;
  return defects.reduce(
    (a, b) => severityRank(b.severity) > severityRank(a.severity) ? b : a,
  );
}

/// ข้อมูลความเสียหายของถนน 1 รายการที่ผู้ใช้กด SAVE
class DamageRecord {
  final String id;

  /// ความเสียหายหลัก = จุดที่รุนแรงที่สุดในภาพ
  final String damageType;
  final String severity;

  /// ความเสียหายทั้งหมดที่พบในภาพเดียวกัน
  final List<Defect> defects;
  final String advice;
  final double latitude;
  final double longitude;
  final DateTime dateSaved;

  /// path ของรูปที่คัดลอกเก็บถาวรไว้ในเครื่อง (null ถ้าคัดลอกไม่สำเร็จ)
  final String? imagePath;

  DamageRecord({
    required this.id,
    required this.damageType,
    required this.severity,
    this.defects = const [],
    required this.advice,
    required this.latitude,
    required this.longitude,
    required this.dateSaved,
    this.imagePath,
  });

  bool get hasLocation => latitude != 0.0 || longitude != 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'damageType': damageType,
        'severity': severity,
        'defects': defects.map((d) => d.toJson()).toList(),
        'advice': advice,
        'latitude': latitude,
        'longitude': longitude,
        'dateSaved': dateSaved.toIso8601String(),
        'imagePath': imagePath,
      };

  factory DamageRecord.fromJson(Map<String, dynamic> json) {
    final damageType = json['damageType']?.toString() ?? '';
    final severity = json['severity']?.toString() ?? '';

    final rawDefects = json['defects'];
    var defects = rawDefects is List
        ? rawDefects
            .whereType<Map>()
            .map((e) => Defect.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Defect>[];
    // รายการเก่าที่บันทึกก่อนรองรับหลายจุด มีแค่ damageType/severity
    if (defects.isEmpty && damageType.isNotEmpty) {
      defects = [Defect(damage: damageType, severity: severity)];
    }

    return DamageRecord(
      id: json['id']?.toString() ?? '',
      damageType: damageType,
      severity: severity,
      defects: defects,
      advice: json['advice']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      dateSaved: DateTime.tryParse(json['dateSaved']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      imagePath: json['imagePath']?.toString(),
    );
  }
}

/// เก็บประวัติการตรวจลง SharedPreferences (เป็น JSON) และคัดลอกรูปไปไว้ใน
/// โฟลเดอร์ของแอปเอง เพราะ path ที่ได้จาก image_picker เป็นไฟล์ชั่วคราว
/// ระบบอาจลบทิ้งเมื่อไหร่ก็ได้
class HistoryStorage {
  static const _key = 'road_damage_history_v1';

  static Future<List<DamageRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];

    final records = <DamageRecord>[];
    for (final item in raw) {
      try {
        records.add(
          DamageRecord.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } catch (_) {
        // ข้ามรายการที่ข้อมูลเสีย แทนที่จะทำให้ทั้งหน้าพัง
      }
    }

    records.sort((a, b) => b.dateSaved.compareTo(a.dateSaved)); // ใหม่สุดขึ้นก่อน
    return records;
  }

  static Future<void> _write(List<DamageRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      records.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  /// เพิ่ม 1 รายการ พร้อมคัดลอกรูป (ถ้ามี) ไปเก็บถาวร
  static Future<DamageRecord> add({
    required List<Defect> defects,
    required String advice,
    required double latitude,
    required double longitude,
    File? image,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();

    String? savedImagePath;
    if (image != null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${dir.path}/history_images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        final ext = image.path.contains('.') ? image.path.split('.').last : 'jpg';
        savedImagePath = '${imagesDir.path}/$id.$ext';
        await image.copy(savedImagePath);
      } catch (_) {
        // คัดลอกรูปไม่สำเร็จก็ยังบันทึกข้อมูลอื่นต่อได้
        savedImagePath = null;
      }
    }

    final primary = mostSevere(defects);
    final record = DamageRecord(
      id: id,
      damageType: primary?.damage ?? 'ไม่ทราบ',
      severity: primary?.severity ?? '',
      defects: defects,
      advice: advice,
      latitude: latitude,
      longitude: longitude,
      dateSaved: now,
      imagePath: savedImagePath,
    );

    final records = await load();
    records.insert(0, record);
    await _write(records);
    return record;
  }

  static Future<void> updateLocation({
    required String id,
    required double latitude,
    required double longitude,
  }) async {
    final records = await load();
    final index = records.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final old = records[index];
    records[index] = DamageRecord(
      id: old.id,
      damageType: old.damageType,
      severity: old.severity,
      defects: old.defects,
      advice: old.advice,
      latitude: latitude,
      longitude: longitude,
      dateSaved: old.dateSaved,
      imagePath: old.imagePath,
    );
    await _write(records);
  }

  static Future<void> delete(String id) async {
    final records = await load();
    final index = records.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final removed = records.removeAt(index);
    if (removed.imagePath != null) {
      try {
        final file = File(removed.imagePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // ลบไฟล์ไม่ได้ก็ไม่เป็นไร ข้อมูลใน list ถูกลบไปแล้ว
      }
    }
    await _write(records);
  }

  static Future<void> clear() async {
    final records = await load();
    for (final r in records) {
      if (r.imagePath == null) continue;
      try {
        final file = File(r.imagePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _write(const []);
  }
}
