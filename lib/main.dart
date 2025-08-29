
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'realtime_chat/realtime_chat_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Set the database URL for Firebase Realtime Database
  FirebaseDatabase.instance.databaseURL = 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DentPal Chat',
      theme: ThemeData(
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 24,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.normal,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
      home: const RealtimeChatApp(),
      debugShowCheckedModeBanner: false,
    );
  }
}
