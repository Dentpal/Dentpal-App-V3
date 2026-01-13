import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:http/http.dart' as http;

class PlatformPoliciesService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch Terms and Conditions from Firebase Storage
  /// Looks for document in platform_policies collection with type: 'user-terms-of-service'
  /// and downloads content from the downloadUrl
  static Future<String?> getTermsAndConditions() async {
    try {
      AppLogger.d('Fetching Terms and Conditions from Firebase...');
      
      final querySnapshot = await _firestore
          .collection('platform_policies')
          .where('type', isEqualTo: 'user-terms-of-service')
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final downloadUrl = doc.data()['downloadUrl'] as String?;
        
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          AppLogger.d('Found download URL, downloading content...');
          
          // Download content from Firebase Storage
          final response = await http.get(Uri.parse(downloadUrl))
              .timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            final content = response.body;
            AppLogger.d('Successfully fetched Terms and Conditions from Storage');
            return content;
          } else {
            AppLogger.d('Failed to download from Storage. Status: ${response.statusCode}');
            return null;
          }
        } else {
          AppLogger.d('Download URL is empty or null');
          return null;
        }
      } else {
        AppLogger.d('No Terms and Conditions document found');
        return null;
      }
    } catch (e) {
      AppLogger.d('Error fetching Terms and Conditions: $e');
      return null;
    }
  }

  /// Fetch Privacy Policy from Firebase Storage
  /// Looks for document in platform_policies collection with type: 'privacy-policy'
  /// and downloads content from the downloadUrl
  static Future<String?> getPrivacyPolicy() async {
    try {
      AppLogger.d('Fetching Privacy Policy from Firebase...');
      
      final querySnapshot = await _firestore
          .collection('platform_policies')
          .where('type', isEqualTo: 'privacy-policy')
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final downloadUrl = doc.data()['downloadUrl'] as String?;
        
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          AppLogger.d('Found download URL, downloading content...');
          
          // Download content from Firebase Storage
          final response = await http.get(Uri.parse(downloadUrl));
          
          if (response.statusCode == 200) {
            final content = response.body;
            AppLogger.d('Successfully fetched Privacy Policy from Storage');
            return content;
          } else {
            AppLogger.d('Failed to download from Storage. Status: ${response.statusCode}');
            return null;
          }
        } else {
          AppLogger.d('Download URL is empty or null');
          return null;
        }
      } else {
        AppLogger.d('No Privacy Policy document found');
        return null;
      }
    } catch (e) {
      AppLogger.d('Error fetching Privacy Policy: $e');
      return null;
    }
  }

  /// Stream Terms and Conditions download URL from Firebase for real-time updates
  /// Note: You'll need to manually fetch content when URL changes
  static Stream<String?> streamTermsAndConditionsUrl() {
    return _firestore
        .collection('platform_policies')
        .where('type', isEqualTo: 'user-terms-of-service')
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return doc.data()['downloadUrl'] as String?;
      }
      return null;
    });
  }

  /// Stream Privacy Policy download URL from Firebase for real-time updates
  /// Note: You'll need to manually fetch content when URL changes
  static Stream<String?> streamPrivacyPolicyUrl() {
    return _firestore
        .collection('platform_policies')
        .where('type', isEqualTo: 'privacy-policy')
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return doc.data()['downloadUrl'] as String?;
      }
      return null;
    });
  }
}
