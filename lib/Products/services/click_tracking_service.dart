import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentpal/utils/app_logger.dart';

class ClickTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Track product click with daily limit per user
  Future<void> trackProductClick(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.d('❌ No authenticated user for product click tracking');
        return;
      }

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'product_click_${productId}_${userId}_$today';

      // Check if user already clicked this product today using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(clickKey) == true) {
        AppLogger.d('✅ User already clicked product $productId today');
        return;
      }

      // Increment the click counter in Firestore
      await _firestore.collection('Product').doc(productId).update({
        'clickCounter': FieldValue.increment(1),
      });

      // Mark this product as clicked today for this user
      await prefs.setBool(clickKey, true);

      AppLogger.d('✅ Product click tracked for product: $productId');
    } catch (e) {
      AppLogger.d('❌ Error tracking product click: $e');
    }
  }

  // Track category click with daily limit per user
  Future<void> trackCategoryClick(String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.d('❌ No authenticated user for category click tracking');
        return;
      }

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'category_click_${categoryId}_${userId}_$today';

      // Check if user already clicked this category today using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(clickKey) == true) {
        AppLogger.d('✅ User already clicked category $categoryId today');
        return;
      }

      // Increment the click counter in Firestore
      await _firestore.collection('Category').doc(categoryId).update({
        'clickCounter': FieldValue.increment(1),
      });

      // Mark this category as clicked today for this user
      await prefs.setBool(clickKey, true);

      AppLogger.d('✅ Category click tracked for category: $categoryId');
    } catch (e) {
      AppLogger.d('❌ Error tracking category click: $e');
    }
  }

  // Track subcategory click with daily limit per user
  Future<void> trackSubCategoryClick(String categoryId, String subCategoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.d('❌ No authenticated user for subcategory click tracking');
        return;
      }

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'subcategory_click_${subCategoryId}_${userId}_$today';

      // Check if user already clicked this subcategory today using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(clickKey) == true) {
        AppLogger.d('✅ User already clicked subcategory $subCategoryId today');
        return;
      }

      // Increment the click counter in Firestore (subcategory is nested under category)
      await _firestore
          .collection('Category')
          .doc(categoryId)
          .collection('subCategory')
          .doc(subCategoryId)
          .update({
        'clickCounter': FieldValue.increment(1),
      });

      // Mark this subcategory as clicked today for this user
      await prefs.setBool(clickKey, true);

      AppLogger.d('✅ SubCategory click tracked for subcategory: $subCategoryId in category: $categoryId');
    } catch (e) {
      AppLogger.d('❌ Error tracking subcategory click: $e');
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
        if ((key.startsWith('product_click_') || 
             key.startsWith('category_click_') ||
             key.startsWith('subcategory_click_')) 
            && !key.endsWith(today)) {
          await prefs.remove(key);
        }
      }
      
      AppLogger.d('✅ Cleaned up old click tracking data');
    } catch (e) {
      AppLogger.d('❌ Error cleaning up click tracking data: $e');
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
      AppLogger.d('❌ Error checking product click status: $e');
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
      AppLogger.d('❌ Error checking category click status: $e');
      return false;
    }
  }

  // Check if user clicked a subcategory today (for UI feedback if needed)
  Future<bool> hasUserClickedSubCategoryToday(String subCategoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userId = user.uid;
      final today = _getTodayKey();
      final clickKey = 'subcategory_click_${subCategoryId}_${userId}_$today';

      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(clickKey) ?? false;
    } catch (e) {
      AppLogger.d('❌ Error checking subcategory click status: $e');
      return false;
    }
  }
}
