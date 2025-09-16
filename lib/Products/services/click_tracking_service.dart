import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClickTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Track product click with daily limit per user
  Future<void> trackProductClick(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ No authenticated user for product click tracking');
        return;
      }

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'product_click_${productId}_${userId}_$today';

      // Check if user already clicked this product today using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(clickKey) == true) {
        print('✅ User already clicked product $productId today');
        return;
      }

      // Increment the click counter in Firestore
      await _firestore.collection('Product').doc(productId).update({
        'clickCounter': FieldValue.increment(1),
      });

      // Mark this product as clicked today for this user
      await prefs.setBool(clickKey, true);

      print('✅ Product click tracked for product: $productId');
    } catch (e) {
      print('❌ Error tracking product click: $e');
    }
  }

  // Track category click with daily limit per user
  Future<void> trackCategoryClick(String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ No authenticated user for category click tracking');
        return;
      }

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'category_click_${categoryId}_${userId}_$today';

      // Check if user already clicked this category today using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(clickKey) == true) {
        print('✅ User already clicked category $categoryId today');
        return;
      }

      // Increment the click counter in Firestore
      await _firestore.collection('Category').doc(categoryId).update({
        'clickCounter': FieldValue.increment(1),
      });

      // Mark this category as clicked today for this user
      await prefs.setBool(clickKey, true);

      print('✅ Category click tracked for category: $categoryId');
    } catch (e) {
      print('❌ Error tracking category click: $e');
    }
  }

  // Clean up old click tracking data (optional, for maintenance)
  Future<void> cleanupOldClickData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final today = _getTodayKey();
      
      // Remove click tracking data older than today
      for (String key in keys) {
        if ((key.startsWith('product_click_') || key.startsWith('category_click_')) 
            && !key.endsWith(today)) {
          await prefs.remove(key);
        }
      }
      
      print('✅ Cleaned up old click tracking data');
    } catch (e) {
      print('❌ Error cleaning up click tracking data: $e');
    }
  }

  // Get today's date key for tracking
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Check if user clicked a product today (for UI feedback if needed)
  Future<bool> hasUserClickedProductToday(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'product_click_${productId}_${userId}_$today';

      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(clickKey) ?? false;
    } catch (e) {
      print('❌ Error checking product click status: $e');
      return false;
    }
  }

  // Check if user clicked a category today (for UI feedback if needed)
  Future<bool> hasUserClickedCategoryToday(String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'category_click_${categoryId}_${userId}_$today';

      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(clickKey) ?? false;
    } catch (e) {
      print('❌ Error checking category click status: $e');
      return false;
    }
  }
}
