
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dentpal/Products/products_module.dart';
import 'package:dentpal/auth_wrapper.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DentPal',
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
        primaryColor: const Color(0xFF43A047), // Green color for consistency
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF43A047),
            foregroundColor: Colors.white,
          ),
        ),
      ),
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
