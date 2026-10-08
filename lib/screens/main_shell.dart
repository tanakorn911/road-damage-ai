import 'package:flutter/material.dart';
import 'package:gpt_vision_leaf_detect/constants/constants.dart';

import 'dashboard_page.dart';
import 'history_page.dart';
import 'homepage.dart';
import 'map_page.dart';

// ---------------------------------------------------
// โครงหลักของแอป — แถบเมนูล่าง 4 แท็บ
// ---------------------------------------------------
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // เปลี่ยนค่าทุกครั้งที่สลับแท็บ เพื่อให้หน้าประวัติ/แผนที่/สรุป โหลดข้อมูลล่าสุด
  // ส่วนหน้าตรวจไม่ผูกกับค่านี้ ภาพและผลตรวจจึงไม่หายเมื่อสลับไปมา
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(),
          HistoryPage(key: ValueKey('history$_refresh')),
          MapPage(key: ValueKey('map$_refresh')),
          DashboardPage(key: ValueKey('dashboard$_refresh')),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: themeColor,
        onTap: (index) => setState(() {
          _index = index;
          _refresh++;
        }),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt), label: 'ตรวจ'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'ประวัติ'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'แผนที่'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'สรุป'),
        ],
      ),
    );
  }
}
