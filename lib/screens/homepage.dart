import 'dart:io';

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gpt_vision_leaf_detect/constants/constants.dart';
import '../services/api_service.dart';
import '../services/history_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cross_file/cross_file.dart';

// ----------------------------------------------------------------------
// Class สำหรับวาดสี่เหลี่ยม (Bounding Box) ของทุกจุดเสียหายบนรูปภาพ
// ----------------------------------------------------------------------
class BoundingBoxPainter extends CustomPainter {
  final List<Defect> defects;

  BoundingBoxPainter(this.defects);

  @override
  void paint(Canvas canvas, Size size) {
    // ตำแหน่งป้ายที่วาดไปแล้ว ใช้เลื่อนป้ายถัดไปไม่ให้ทับกัน
    final labelRects = <Rect>[];

    for (var i = 0; i < defects.length; i++) {
      final box = defects[i].box;
      if (box.length < 4) continue;

      final color = severityColor(defects[i].severity);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;

      // AI ส่งมาเป็น [ymin, xmin, ymax, xmax]
      final double yMin = box[0] * size.height;
      final double xMin = box[1] * size.width;
      final double yMax = box[2] * size.height;
      final double xMax = box[3] * size.width;

      canvas.drawRect(Rect.fromLTRB(xMin, yMin, xMax, yMax), paint);

      // ป้ายเลขลำดับที่มุมบนซ้ายของกรอบ ให้ตรงกับรายการใต้ภาพ
      final label = TextPainter(
        text: TextSpan(
          text: ' ${i + 1} ',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // กรอบที่เริ่มมุมเดียวกันจะมีป้ายทับกัน ให้เลื่อนป้ายไปทางขวาจนว่าง
      var labelRect = Rect.fromLTWH(xMin, yMin, label.width, label.height);
      while (labelRects.any((r) => r.overlaps(labelRect))) {
        labelRect = labelRect.translate(label.width + 2, 0);
      }
      labelRects.add(labelRect);

      canvas.drawRect(labelRect, Paint()..color = color);
      label.paint(canvas, labelRect.topLeft);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ----------------------------------------------------------------------
// HomePage
// ----------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<HomePage> {
  final apiService = ApiService();
  XFile? _selectedImage;
  double _imageAspectRatio = 1; // กว้าง/สูง ของภาพจริง ใช้วางกรอบให้ตรงตำแหน่ง
  List<Defect> defects = []; // ความเสียหายทุกจุดที่ AI พบ
  String repairAdvice = '';

  bool detecting = false;
  bool adviceLoading = false;
  bool isSaving = false;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024, // จำกัดขนาดไม่เกิน 1024 พิกเซล ให้ AI ยังเห็นรอยเล็ก ๆ ได้
      maxHeight: 1024,
    );
    if (pickedFile != null) {
      final decoded = await decodeImageFromList(await pickedFile.readAsBytes());
      if (!mounted) return;
      setState(() {
        _selectedImage = pickedFile;
        _imageAspectRatio = decoded.width / decoded.height;
        // รีเซ็ตค่าทั้งหมดเมื่อเลือกภาพใหม่
        defects = [];
        repairAdvice = '';
      });
    }
  }

  detectDamage() async {
    setState(() { detecting = true; });
    try {
      // เรียกฟังก์ชันเพื่อขอรายการความเสียหาย (ประเภท + ระดับ + พิกัดสี่เหลี่ยม)
      final result = await apiService.sendImageToAPI(image: _selectedImage!);

      setState(() { defects = result; });
    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      setState(() { detecting = false; });
    }
  }

  showRepairAdvice() async {
    setState(() { adviceLoading = true; });
    try {
      if (repairAdvice == '') {
        repairAdvice = await apiService.sendRepairAdvice(defects: defects);
      }
      _showSuccessDialog("แนวทางซ่อมบำรุง", repairAdvice);
    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      if (mounted) setState(() { adviceLoading = false; });
    }
  }

  Future<void> _saveDataWithLocation() async {
    setState(() { isSaving = true; });

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

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // บันทึกลงเครื่อง (SharedPreferences + คัดลอกรูปเก็บถาวร)
      // บนเว็บไม่มี dart:io File จึงบันทึกเฉพาะข้อมูล ไม่เก็บรูป
      final record = await HistoryStorage.add(
        defects: defects,
        advice: repairAdvice,
        latitude: position.latitude,
        longitude: position.longitude,
        image: (!kIsWeb && _selectedImage != null)
            ? File(_selectedImage!.path)
            : null,
      );

      if (!mounted) return;
      _showSuccessDialog(
        "บันทึกข้อมูลสำเร็จ",
        "ความเสียหายหลัก: ${record.damageType}\n"
        "ระดับ: ${record.severity.isEmpty ? '-' : record.severity}\n"
        "จำนวนจุดที่พบ: ${defects.length}\n"
        "พิกัด: ${position.latitude}, ${position.longitude}",
      );

    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      if (mounted) setState(() { isSaving = false; });
    }
  }

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString()),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showSuccessDialog(String title, String content) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.success,
      animType: AnimType.rightSlide,
      title: title,
      desc: content,
      btnOkText: 'ตกลง',
      btnOkColor: themeColor,
      btnOkOnPress: () {},
    ).show();
  }

  /// รายการความเสียหายใต้ภาพ เลขลำดับตรงกับป้ายบนกรอบ
  Widget _buildDefectList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: defects.length,
        itemBuilder: (context, index) {
          final defect = defects[index];
          final color = severityColor(defect.severity);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    defect.damage.trim(),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                // ป้ายระดับความรุนแรง
                if (defect.severity.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color),
                    ),
                    child: Text(
                      defect.severity,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        title: const Text('Road Damage AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: <Widget>[
          Stack(
            children: [
              Container(
                height: 92,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(50.0),
                  ),
                ),
              ),
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(50.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
                // ปุ่มวางเคียงกันแถวเดียว เหลือพื้นที่ให้ภาพและรายการผลตรวจมากขึ้น
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('GALLERY', style: TextStyle(color: textColor)),
                          const SizedBox(width: 8),
                          Icon(Icons.image, color: textColor)
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _pickImage(ImageSource.camera),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('CAMERA', style: TextStyle(color: textColor)),
                          const SizedBox(width: 8),
                          Icon(Icons.camera_alt, color: textColor)
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // -------------------------------------------------------------
          // พื้นที่แสดงภาพและวาดกรอบ
          // -------------------------------------------------------------
          _selectedImage == null
              ? Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_road,
                            size: 110,
                            color: themeColor.withOpacity(0.35),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'เลือกรูปผิวถนนจากคลังภาพ\nหรือถ่ายภาพใหม่เพื่อเริ่มตรวจ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      // ให้กล่องมีสัดส่วนเท่าภาพจริง กรอบจะได้ตรงกับตำแหน่งในภาพ
                      child: AspectRatio(
                        aspectRatio: _imageAspectRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              )
                            ]
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand, // วาง Stack เพื่อซ้อนรูปและเส้น
                              children: [
                                kIsWeb
                                ? Image.network(
                                    _selectedImage!.path,
                                    fit: BoxFit.fill,
                                  )
                                : Image.file(
                                    File(_selectedImage!.path),
                                    fit: BoxFit.fill,
                                  ),
                                if (defects.isNotEmpty)
                                  CustomPaint(
                                    painter: BoundingBoxPainter(defects),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

          // ปุ่ม DETECT
          if (_selectedImage != null && defects.isEmpty)
            detecting
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: SpinKitWave(color: themeColor, size: 30),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () => detectDamage(),
                      child: const Text(
                        'ตรวจความเสียหาย',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

          // ส่วนแสดงผลลัพธ์
          if (defects.isNotEmpty)
            Column(
              children: [
                _buildDefectList(),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: adviceLoading
                            ? const SpinKitWave(color: Colors.blue, size: 30)
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => showRepairAdvice(),
                                icon: Icon(Icons.build_outlined, color: textColor),
                                label: Text('แนวทางซ่อม',
                                    style: TextStyle(color: textColor, fontSize: 13)),
                              ),
                      ),

                      const SizedBox(width: 15),

                      Expanded(
                        child: isSaving
                            ? SpinKitWave(color: themeColor, size: 30)
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => _saveDataWithLocation(),
                                icon: Icon(Icons.save, color: textColor),
                                label: Text('บันทึกจุดนี้',
                                    style: TextStyle(color: textColor, fontSize: 13)),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
