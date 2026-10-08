import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:gpt_vision_leaf_detect/constants/constants.dart';

import '../services/export_service.dart';
import '../services/history_storage.dart';
import '../services/map_launcher.dart';

// ---------------------------------------------------
// หน้า History Page — อ่านข้อมูลจริงจาก HistoryStorage
// (Model DamageRecord ย้ายไปอยู่ใน services/history_storage.dart)
// ---------------------------------------------------
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<DamageRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await HistoryStorage.load();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteRecord(DamageRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรายการนี้?'),
        content: Text(record.damageType),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await HistoryStorage.delete(record.id);
    await _loadRecords();
  }

  Future<void> _export(String format) async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรายการประวัติสำหรับส่งออก')),
      );
      return;
    }

    try {
      if (format == 'pdf') {
        await ExportService.sharePdf(_records);
      } else {
        await ExportService.shareCsv(_records);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ส่งออกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        title: const Text(
          'ประวัติการสำรวจถนน',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white), // สีปุ่มย้อนกลับ
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share, color: Colors.white),
            tooltip: 'ส่งออกรายงาน',
            onSelected: _export,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart, color: Colors.green),
                  title: Text('ส่งออก CSV (Excel)'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text('ส่งออก PDF'),
                  dense: true,
                ),
              ),
            ],
          ),
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'โหลดประวัติไม่สำเร็จ\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRecords,
                child: const Text('ลองอีกครั้ง'),
              ),
            ],
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีประวัติการบันทึกข้อมูล',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];

          // แปลงรูปแบบวันที่ให้อ่านง่าย
          final formattedDate =
              DateFormat('dd MMM yyyy, HH:mm').format(record.dateSaved);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  // รูปที่บันทึกไว้ (ถ้าไม่มีให้แสดงไอคอนแทน)
                  _buildThumbnail(record),
                  const SizedBox(width: 16),

                  // ข้อมูลตรงกลาง
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                // ถ้าภาพเดียวพบหลายจุด บอกจำนวนที่เหลือไว้ท้ายชื่อ
                                record.defects.length > 1
                                    ? '${record.damageType} +${record.defects.length - 1} จุด'
                                    : record.damageType,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (record.severity.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: severityColor(record.severity)
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  record.severity,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: severityColor(
                                        record.severity),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => openExternalMap(context, record.latitude, record.longitude),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 14, color: Colors.red[400]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${record.latitude.toStringAsFixed(4)}, ${record.longitude.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                      decoration: TextDecoration.underline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // เมนูด้านขวา
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.map, color: Colors.blue),
                        tooltip: 'ไปยังแผนที่',
                        onPressed: () => openExternalMap(context, record.latitude, record.longitude),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        onSelected: (value) {
                          switch (value) {
                            case 'update_location':
                              _updateLocationWithGPS(record);
                              break;
                            case 'map':
                              openExternalMap(context, record.latitude, record.longitude);
                              break;
                            case 'detail':
                              _showDetail(record);
                              break;
                            case 'delete':
                              _deleteRecord(record);
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'map',
                            child: ListTile(
                              leading: Icon(Icons.map, color: Colors.blue),
                              title: Text('ไปยังแผนที่'),
                              dense: true,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'update_location',
                            child: ListTile(
                              leading: Icon(Icons.my_location, color: Colors.teal),
                              title: Text('ปักพิกัดจริงปัจจุบัน'),
                              dense: true,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'detail',
                            child: ListTile(
                              leading: Icon(Icons.info_outline),
                              title: Text('รายละเอียด'),
                              dense: true,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('ลบ'),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbnail(DamageRecord record) {
    final path = record.imagePath;
    if (!kIsWeb && path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.report_problem_outlined, // ใช้ไอคอนแจ้งความเสียหาย
        color: themeColor,
        size: 30,
      ),
    );
  }

  void _showDetail(DamageRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.damageType),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final defect in record.defects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 10, color: severityColor(defect.severity)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          defect.severity.isEmpty
                              ? defect.damage
                              : '${defect.damage} (${defect.severity})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Text(
                record.advice.isEmpty
                    ? 'ไม่ได้บันทึกแนวทางซ่อมไว้สำหรับรายการนี้\n'
                        '(กด "แนวทางซ่อม" ก่อนกดบันทึก ระบบจะเก็บให้ด้วย)'
                    : record.advice,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLocationWithGPS(DamageRecord record) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('กรุณาเปิด GPS (Location Services) บนอุปกรณ์ของคุณ');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('สิทธิ์ถูกปฏิเสธอย่างถาวร กรุณาไปตั้งค่าในเครื่อง');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('กำลังดึงพิกัดปัจจุบัน...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await HistoryStorage.updateLocation(
        id: record.id,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _loadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'อัปเดตพิกัดจริงสำเร็จ: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
