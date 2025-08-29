import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

class RealtimeChatApp extends StatelessWidget {
  const RealtimeChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DentPal Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}
