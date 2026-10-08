import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:gpt_vision_leaf_detect/constants/constants.dart';

import '../services/history_storage.dart';
import '../services/map_launcher.dart';

// ---------------------------------------------------
// หน้าแผนที่ — ปักหมุดทุกจุดที่บันทึกไว้ สีหมุดตามระดับความรุนแรง
// ---------------------------------------------------
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
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
      // ข้ามรายการที่ยังไม่มีพิกัด
      _records = records.where((r) => r.hasLocation).toList();
      _loading = false;
    });
  }

  void _showRecord(DamageRecord record) {
    final path = record.imagePath;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!kIsWeb && path != null && File(path).existsSync())
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(path),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final defect in record.defects)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 10,
                                  color: severityColor(defect.severity)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  defect.severity.isEmpty
                                      ? defect.damage
                                      : '${defect.damage} (${defect.severity})',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMM yyyy, HH:mm').format(record.dateSaved),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        '${record.latitude.toStringAsFixed(5)}, ${record.longitude.toStringAsFixed(5)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  openExternalMap(context, record.latitude, record.longitude);
                },
                icon: Icon(Icons.navigation, color: textColor),
                label: Text('นำทางด้วย Google Maps',
                    style: TextStyle(color: textColor)),
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        title: const Text(
          'แผนที่จุดเสียหาย',
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

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีจุดที่บันทึกพร้อมพิกัด',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final points =
        _records.map((r) => LatLng(r.latitude, r.longitude)).toList();
    // ถ้าทุกจุดอยู่ที่เดียวกัน จะคำนวณขอบเขตไม่ได้ ให้ซูมไปที่จุดนั้นแทน
    final samePlace = points.every((p) => p == points.first);

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 16,
            initialCameraFit: samePlace
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(60),
                    maxZoom: 17,
                  ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.gpt_vision_leaf_detect',
            ),
            MarkerLayer(
              markers: [
                for (final record in _records)
                  Marker(
                    point: LatLng(record.latitude, record.longitude),
                    width: 44,
                    height: 44,
                    // ให้ปลายหมุดชี้ตรงพิกัด
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => _showRecord(record),
                      child: Icon(
                        Icons.location_on,
                        size: 44,
                        color: severityColor(record.severity),
                      ),
                    ),
                  ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors'),
            ),
          ],
        ),

        // คำอธิบายสีหมุด
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final level in severityLevels)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on,
                          size: 16, color: severityColor(level)),
                      const SizedBox(width: 4),
                      Text(level, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
