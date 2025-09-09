
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/Products/products_module.dart';
import 'package:dentpal/auth_wrapper.dart';
import 'package:dentpal/core/app_theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set Firestore cache size to 100MB
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DentPal',
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
      routes: {
        ...ProductsModule.getRoutes(),
      },
      onGenerateRoute: (settings) {
        // Try product module routes first
        final productRoute = ProductsModule.generateRoute(settings);
        if (productRoute != null) return productRoute;
        
        // Add other dynamic routes if needed
        return null;
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
