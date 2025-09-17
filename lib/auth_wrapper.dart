import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'core/app_theme/theme_example_page.dart';
import 'login_page.dart';
import 'home_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If the snapshot has user data, then they're already authenticated
        if (snapshot.hasData) {
          return const HomePage();
        }
        // Otherwise, they're not signed in
        return const LoginPage();
      },
      // if account has a 'seller' table, then include a
      // separate landing page so that they can transition between 
      //buying and selling
    );
  }
}
