import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/constants.dart';
import 'history_storage.dart';

/// ส่งออกประวัติการสำรวจเป็นไฟล์ เพื่อส่งต่อให้หน่วยงานที่ดูแลถนน
class ExportService {
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  static String _fileStamp() =>
      DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  static String _defectsText(DamageRecord record) => record.defects
      .map((d) => d.severity.isEmpty ? d.damage : '${d.damage} (${d.severity})')
      .join('; ');

  static String _mapLink(DamageRecord record) => record.hasLocation
      ? 'https://www.google.com/maps/search/?api=1&query=${record.latitude},${record.longitude}'
      : '';

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  static String buildCsv(List<DamageRecord> records) {
    final rows = <List<Object?>>[
      [
        'ลำดับ',
        'วันที่บันทึก',
        'ความเสียหายหลัก',
        'ระดับความรุนแรง',
        'ความเสียหายทั้งหมดในภาพ',
        'ละติจูด',
        'ลองจิจูด',
        'ลิงก์แผนที่',
        'แนวทางซ่อม',
      ],
      for (var i = 0; i < records.length; i++)
        [
          i + 1,
          _dateFormat.format(records[i].dateSaved),
          records[i].damageType,
          records[i].severity,
          _defectsText(records[i]),
          records[i].latitude,
          records[i].longitude,
          _mapLink(records[i]),
          records[i].advice,
        ],
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  static Future<void> shareCsv(List<DamageRecord> records) async {
    // ใส่ BOM นำหน้า เพื่อให้ Excel เปิดแล้วอ่านภาษาไทยได้ถูกต้อง
    final bytes = Uint8List.fromList([
      0xEF, 0xBB, 0xBF,
      ...utf8.encode(buildCsv(records)),
    ]);
    final name = 'road_damage_${_fileStamp()}.csv';

    // บนมือถือเขียนเป็นไฟล์จริงก่อน ชื่อไฟล์และนามสกุลจะได้ถูกต้องเมื่อแชร์
    // บนเว็บไม่มีระบบไฟล์ จึงส่งเป็นข้อมูลในหน่วยความจำแทน
    final XFile file;
    if (kIsWeb) {
      file = XFile.fromData(bytes, mimeType: 'text/csv', name: name);
    } else {
      final dir = await getTemporaryDirectory();
      final saved = await File('${dir.path}/$name').writeAsBytes(bytes);
      file = XFile(saved.path, mimeType: 'text/csv');
    }

    await Share.shareXFiles([file], subject: 'รายงานสำรวจความเสียหายถนน');
  }

  static Future<void> sharePdf(List<DamageRecord> records) async {
    // ฟอนต์ Sarabun รองรับภาษาไทย (ดาวน์โหลดครั้งแรกแล้วเก็บ cache ไว้)
    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.sarabunRegular(),
      bold: await PdfGoogleFonts.sarabunBold(),
    );

    final allDefects = records
        .expand((r) => r.defects)
        .where((d) => isRealDamage(d.damage))
        .toList();

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'รายงานสำรวจความเสียหายผิวถนน',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'ออกรายงานเมื่อ ${_dateFormat.format(DateTime.now())}  |  '
            'จำนวนภาพที่บันทึก ${records.length}  |  '
            'จำนวนจุดเสียหาย ${allDefects.length}',
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            severityLevels
                .map((level) =>
                    '$level ${allDefects.where((d) => d.severity == level).length} จุด')
                .join('   '),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: const {
              0: pw.FixedColumnWidth(28),
              1: pw.FixedColumnWidth(80),
              2: pw.FlexColumnWidth(3),
              3: pw.FixedColumnWidth(110),
              4: pw.FlexColumnWidth(4),
            },
            headers: ['#', 'วันที่', 'ความเสียหายที่พบ', 'พิกัด', 'แนวทางซ่อม'],
            data: [
              for (var i = 0; i < records.length; i++)
                [
                  '${i + 1}',
                  _dateFormat.format(records[i].dateSaved),
                  _defectsText(records[i]),
                  records[i].hasLocation
                      ? '${records[i].latitude.toStringAsFixed(5)}, ${records[i].longitude.toStringAsFixed(5)}'
                      : '-',
                  records[i].advice.isEmpty ? '-' : records[i].advice,
                ],
            ],
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'road_damage_${_fileStamp()}.pdf',
    );
  }
}
