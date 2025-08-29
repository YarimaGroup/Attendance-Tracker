import 'package:attendance_tracker/screens/auth.dart';
import 'package:attendance_tracker/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissionsIfNeeded();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await NotificationService.instance.scheduleDailySafe(
    id: 1001,
    hour: 9,
    minute: 0,
    title: 'Clock In',
    body: 'Good morning! Don’t forget to clock in.',
    payload: 'clock_in',
  );

  await NotificationService.instance.scheduleDailySafe(
    id: 1002,
    hour: 18,
    minute: 0,
    title: 'Clock Out',
    body: 'Workday ending. Remember to clock out.',
    payload: 'clock_out',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
