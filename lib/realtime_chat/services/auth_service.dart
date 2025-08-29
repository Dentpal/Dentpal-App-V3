import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Current user
  User? get currentUser => _auth.currentUser;

  // Sign in with email and password
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;
      return user;
    } catch (error) {
      print('Error signing in: ${error.toString()}');
      return null;
    }
  }

  // Check if user is admin based on email
  Future<bool> isAdmin(String? uid) async {
    if (uid == null) return false;
    
    User? user = _auth.currentUser;
    if (user == null) return false;
    
    // Simple check based on email domain or exact match
    return user.email == 'admin@provider.com';
  }

  // Create user entry in database (only for chat functionality)
  Future<void> createUserEntry(String uid, String email) async {
    await _database.ref('users/$uid').set({
      'email': email,
      'isAdmin': email == 'admin@provider.com',
      'createdAt': ServerValue.timestamp,
    });
  }

  // Sign out
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (error) {
      print('Error signing out: ${error.toString()}');
    }
  }

  // Register user in Realtime Database if they've authenticated successfully
  Future<void> registerUserInDatabase(User user) async {
    try {
      // Check if user exists in database, if not create entry
      DataSnapshot snapshot = await _database.ref('users/${user.uid}').get();
      if (!snapshot.exists) {
        await createUserEntry(user.uid, user.email ?? 'unknown@email.com');
      }
    } catch (e) {
      print('Error registering user in database: ${e.toString()}');
    }
  }

  // This method is no longer creating users, just ensuring they have database entries
  Future<void> createPredefinedUsersIfNeeded() async {
    try {
      // Users are already created in Firebase Auth manually
      // We'll just set up database entries if needed when they log in
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await registerUserInDatabase(currentUser);
      }
    } catch (e) {
      print('Error setting up user database entries: ${e.toString()}');
    }
  }
}
