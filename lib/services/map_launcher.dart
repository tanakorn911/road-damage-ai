import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// เปิดแอปแผนที่ภายนอก (Google Maps) ที่พิกัดที่กำหนด เพื่อใช้นำทางไปยังจุดเสียหาย
Future<void> openExternalMap(
    BuildContext context, double lat, double lng) async {
  final messenger = ScaffoldMessenger.of(context);

  // ตรวจสอบพิกัดเบื้องต้น
  if (lat == 0.0 && lng == 0.0) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('รายการนี้ยังไม่มีพิกัด กรุณากด "ปักพิกัดจริงปัจจุบัน" ก่อน'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // ลิงก์มาตรฐานของ Google Maps
  final Uri googleMapsUrl =
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

  try {
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('ไม่สามารถเปิดแผนที่ได้: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
