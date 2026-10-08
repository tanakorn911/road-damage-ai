import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:cross_file/cross_file.dart';

import '../constants/api_constants.dart';
import 'history_storage.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: BASE_URL,
        connectTimeout: const Duration(seconds: 30), // เผื่อเวลาให้ AI วิเคราะห์ภาพ
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $API_KEY',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
      ),
    );
  }

  Future<String> encodeImage(XFile image) async {
    final bytes = await image.readAsBytes();
    return base64Encode(bytes);
  }

  Future<String> _postToAPI(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post("/chat/completions", data: data);
      final jsonResponse = response.data;
      print(jsonResponse);
      if (jsonResponse == null) {
        throw const HttpException('Empty response from API');
      }

      if (jsonResponse['error'] != null) {
        throw HttpException(
          jsonResponse['error']['message']?.toString() ?? 'Unknown API error',
        );
      }

      final choices = jsonResponse['choices'];
      if (choices == null || choices.isEmpty) {
        throw const HttpException('No response choices returned');
      }

      final content = choices[0]['message']?['content']?.toString();
      if (content == null || content.trim().isEmpty) {
        throw const HttpException('Empty AI response');
      }

      // ถ้า finish_reason เป็น 'length' แปลว่าคำตอบถูกตัดกลางคันเพราะ max_tokens ไม่พอ
      if (choices[0]['finish_reason'] == 'length') {
        print('WARNING: คำตอบถูกตัดเพราะ max_tokens ไม่พอ -> $content');
      }

      return content.trim();
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error']?['message'] ?? e.message;
      print("DioException: $errorMsg");
      throw Exception('API request failed: $errorMsg');
    } catch (e) {
      print("General Exception: $e");
      throw Exception('Error: $e');
    }
  }

  /// ขอคำแนะนำการซ่อมบำรุงสำหรับความเสียหายทั้งหมดที่ตรวจพบในภาพ
  Future<String> sendRepairAdvice({
    required List<Defect> defects,
    String model = "gpt-5.6-terra-pro",
  }) async {
    final damageText = defects
        .map((d) => d.severity.isEmpty
            ? "'${d.damage}'"
            : "'${d.damage}' (ระดับความรุนแรง: ${d.severity})")
        .join(', ');

    final data = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': "ถนนมีความเสียหายดังนี้: $damageText "
              "ให้คำแนะนำสั้น ๆ 3 ข้อ เป็นภาษาไทย ครอบคลุม: "
              "วิธีซ่อมที่เหมาะสม, ความเร่งด่วนในการซ่อม, และข้อควรระวังด้านความปลอดภัยของผู้ใช้ถนน "
              "ตอบเป็น bullet point 3 ข้อเท่านั้น ข้อละ 1 ประโยคสั้น ๆ ห้ามมีคำอธิบายอื่นเพิ่ม",
        }
      ],
      'max_tokens': 400,
    };

    return _postToAPI(data);
  }

  /// แปลงข้อความที่ AI ตอบกลับมาเป็นรายการความเสียหาย
  /// รองรับกรณีที่มี ```json ครอบ, มีข้อความอธิบายนำหน้า/ต่อท้าย,
  /// ตอบแบบเดิม (ก้อนเดียว) และ JSON ที่ถูกตัดกลางคัน
  List<Defect> _parseDefects(String raw) {
    var text = raw.replaceAll('```json', '').replaceAll('```', '').trim();

    // ตัดเอาเฉพาะช่วงตั้งแต่ { ตัวแรก ถึง } ตัวสุดท้าย
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end > start) {
      text = text.substring(start, end + 1);
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['defects'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Defect.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        // รูปแบบเดิม: {"damage": ..., "severity": ..., "box": [...]}
        if (decoded['damage'] != null) return [Defect.fromJson(decoded)];
      }
    } catch (_) {
      // ตกลงมาลองกู้ทีละก้อนด้านล่าง
    }

    // กู้ข้อมูลจาก JSON ที่ถูกตัดกลางคัน (เช่น max_tokens ไม่พอ)
    // ก้อนที่ปิดวงเล็บครบแล้วยังใช้ได้ ก้อนสุดท้ายที่ขาดจะถูกข้ามไป
    final defects = <Defect>[];
    for (final match in RegExp(r'\{[^{}]*"damage"[^{}]*\}').allMatches(raw)) {
      try {
        final decoded = jsonDecode(match.group(0)!);
        if (decoded is Map<String, dynamic>) {
          defects.add(Defect.fromJson(decoded));
        }
      } catch (_) {}
    }
    return defects;
  }

  /// วิเคราะห์ภาพผิวถนน คืนรายการความเสียหายทุกจุดที่พบ (สูงสุด 5 จุด)
  Future<List<Defect>> sendImageToAPI({
    required XFile image,
    int maxTokens = 800,
    String model = "gpt-5.6-terra-pro",
  }) async {
    final String base64Image = await encodeImage(image);

    final data = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a road surface inspection assistant for a municipal '
              'road maintenance survey. You analyze photos of roads and report '
              'pavement defects. Answer only with the requested JSON.',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'Analyze this photo of a road surface and identify every '
                  'distinct pavement defect you can see, up to 5 defects, ordered '
                  'from most severe to least severe. '
                  'For each defect choose the name from exactly this Thai list: '
                  '"หลุมบ่อ", "รอยแตกลายจระเข้", "รอยแตกตามยาว", "รอยแตกตามขวาง", '
                  '"ผิวทางหลุดร่อน", "ร่องล้อ", "ผิวทางทรุดตัว", "ฝาท่อ/ฝาบ่อชำรุด", '
                  '"เส้นจราจรเลือนราง", "ไหล่ทางชำรุด". '
                  'Rate each severity as exactly one of "น้อย", "ปานกลาง", "รุนแรง". '
                  'Also give the bounding box of each defect as normalized coordinates '
                  'between 0.0 and 1.0 in the order [ymin, xmin, ymax, xmax]. '
                  'Respond STRICTLY in valid JSON like this: '
                  '{"defects": [{"damage": "หลุมบ่อ", "severity": "รุนแรง", "box": [0.4, 0.2, 0.8, 0.7]}, '
                  '{"damage": "รอยแตกตามยาว", "severity": "น้อย", "box": [0.1, 0.5, 0.9, 0.6]}]}. '
                  'If the road looks intact, respond with '
                  '{"defects": [{"damage": "ไม่พบความเสียหาย", "severity": "น้อย", "box": []}]}. '
                  'If the photo is not a road surface, respond with '
                  '{"defects": [{"damage": "ไม่ใช่ภาพถนน", "severity": "", "box": []}]}. '
                  'Do not use markdown blocks like ```json.',
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            },
          ],
        },
      ],
      'max_tokens': maxTokens,
    };

    final responseText = await _postToAPI(data);

    final defects = _parseDefects(responseText);
    if (defects.isNotEmpty) return defects;

    // แปลงไม่สำเร็จจริง ๆ — อย่าโยนข้อความดิบไปโชว์บนหน้าจอ
    print('ไม่สามารถแปลงคำตอบเป็น JSON ได้: $responseText');
    return const [Defect(damage: 'ไม่ทราบ')];
  }
}
