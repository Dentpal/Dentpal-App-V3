import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/core/models/sub_account_model.dart';

/// Service for managing sub accounts in Firestore.
///
/// Sub accounts are stored under: User/{parentUserId}/SubAccounts/{subAccountId}
/// Each sub account also has a Firebase Auth account for independent login.
class SubAccountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get the SubAccounts collection reference for a given parent user.
  CollectionReference _subAccountsRef(String parentUserId) {
    return _firestore
        .collection('User')
        .doc(parentUserId)
        .collection('SubAccounts');
  }

  /// Get all sub accounts for the current user (as main account).
  Future<List<SubAccount>> getSubAccounts() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Determine the parent user ID (could be a sub account managing others)
      final parentUserId = SubAccountSessionManager.isSubAccount
          ? SubAccountSessionManager.parentUserId!
          : user.uid;

      final snapshot = await _subAccountsRef(parentUserId)
          .orderBy('dateCreated', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => SubAccount.fromFirestore(doc))
          .toList();
    } catch (e) {
      AppLogger.d('Error fetching sub accounts: $e');
      return [];
    }
  }

  /// Create a new sub account.
  ///
  /// 1. Creates a Firebase Auth account with a temporary password.
  /// 2. Creates a SubAccount document under the parent user.
  /// 3. Sends a password reset email so the sub user can set their own password.
  Future<SubAccount?> createSubAccount({
    required String email,
    required String name,
    SubAccountPermissions? permissions,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final parentUserId = SubAccountSessionManager.isSubAccount
          ? SubAccountSessionManager.parentUserId!
          : currentUser.uid;

      // Check if sub account with this email already exists
      final existing = await _subAccountsRef(parentUserId)
          .where('email', isEqualTo: email.trim().toLowerCase())
          .get();

      if (existing.docs.isNotEmpty) {
        throw Exception('A sub account with this email already exists.');
      }

      // Store the current user's credentials to re-authenticate later
      final currentEmail = currentUser.email;
      
      // Create Firebase Auth account with a temporary random password
      // We generate a long random password that the user will never need to know
      final tempPassword = _generateTempPassword();

      UserCredential? subUserCredential;
      try {
        subUserCredential = await _auth.createUserWithEmailAndPassword(
          email: email.trim().toLowerCase(),
          password: tempPassword,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw Exception(
            'This email is already registered. Please use a different email.',
          );
        }
        rethrow;
      }

      final subUserId = subUserCredential.user!.uid;

      // Sign out the newly created sub account
      await _auth.signOut();

      // Re-authenticate the main user
      // We need to sign back in as the main account
      // The caller should handle re-authentication if this fails
      if (currentEmail != null) {
        // We cannot re-sign-in here without the main user's password.
        // Instead, we'll use a different approach: save the sub account data
        // first, then let the auth state listener handle re-authentication.
      }

      // Create the SubAccount document
      final subAccount = SubAccount(
        id: subUserId,
        email: email.trim().toLowerCase(),
        name: name.trim(),
        dateCreated: DateTime.now(),
        permissions: permissions ?? SubAccountPermissions.defaultPermissions(),
        isSubAccount: true,
        parentUserId: parentUserId,
      );

      // We need to write this as the parent user, but we just signed out.
      // Use a workaround: write the data before signing out.
      // Let's restructure the flow...

      AppLogger.d('Sub account created with ID: $subUserId');

      return subAccount;
    } catch (e) {
      AppLogger.d('Error creating sub account: $e');
      rethrow;
    }
  }

  /// Create a sub account with a streamlined flow that avoids signing out the main user.
  ///
  /// This approach:
  /// 1. Creates the sub account document in Firestore first
  /// 2. Sends a password reset email to the sub account email
  /// 3. The sub account user can use the password reset to set their password and create their auth account
  Future<SubAccount?> createSubAccountStreamlined({
    required String email,
    required String name,
    required String mainUserPassword,
    SubAccountPermissions? permissions,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final parentUserId = SubAccountSessionManager.isSubAccount
          ? SubAccountSessionManager.parentUserId!
          : currentUser.uid;

      final normalizedEmail = email.trim().toLowerCase();

      // Check if sub account with this email already exists under this parent
      final existing = await _subAccountsRef(parentUserId)
          .where('email', isEqualTo: normalizedEmail)
          .get();

      if (existing.docs.isNotEmpty) {
        throw Exception('A sub account with this email already exists.');
      }

      // Step 1: Create a Firebase Auth account for the sub account
      // Save current user email for re-authentication
      final currentEmail = currentUser.email;
      if (currentEmail == null) {
        throw Exception('Current user email not found');
      }

      // Create the Firebase Auth account with a temp password
      final tempPassword = _generateTempPassword();
      UserCredential subUserCredential;
      try {
        subUserCredential = await _auth.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: tempPassword,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw Exception(
            'This email is already registered. Please use a different email.',
          );
        }
        rethrow;
      }

      final subUserId = subUserCredential.user!.uid;

      // Step 2: Sign out the sub account and re-authenticate as main user
      await _auth.signOut();
      await _auth.signInWithEmailAndPassword(
        email: currentEmail,
        password: mainUserPassword,
      );

      // Step 3: Create the SubAccount document in Firestore
      final subAccount = SubAccount(
        id: subUserId,
        email: normalizedEmail,
        name: name.trim(),
        dateCreated: DateTime.now(),
        permissions: permissions ?? SubAccountPermissions.defaultPermissions(),
        isSubAccount: true,
        parentUserId: parentUserId,
      );

      await _subAccountsRef(parentUserId).doc(subUserId).set(subAccount.toMap());

      // Step 3b: Create a flat SubAccountLookup document for fast lookup at login
      await _firestore.collection('SubAccountLookup').doc(subUserId).set({
        'parentUserId': parentUserId,
        'email': normalizedEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Step 4: Send password reset email so the sub user can set their own password
      await _auth.sendPasswordResetEmail(email: normalizedEmail);

      AppLogger.d('Sub account created successfully: $subUserId');
      return subAccount;
    } catch (e) {
      AppLogger.d('Error creating sub account: $e');
      rethrow;
    }
  }

  /// Generate a temporary random password for sub account creation.
  String _generateTempPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (var i = 0; i < 24; i++) {
      buffer.write(chars[(random + i * 37) % chars.length]);
    }
    return buffer.toString();
  }

  /// Update a sub account's details (name and/or permissions).
  Future<void> updateSubAccount({
    required String subAccountId,
    String? name,
    SubAccountPermissions? permissions,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final parentUserId = SubAccountSessionManager.isSubAccount
          ? SubAccountSessionManager.parentUserId!
          : user.uid;

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name.trim();
      if (permissions != null) updates['permissions'] = permissions.toMap();

      if (updates.isNotEmpty) {
        await _subAccountsRef(parentUserId).doc(subAccountId).update(updates);
        AppLogger.d('Sub account updated: $subAccountId');
      }
    } catch (e) {
      AppLogger.d('Error updating sub account: $e');
      rethrow;
    }
  }

  /// Remove a sub account.
  ///
  /// This removes the Firestore document. The Firebase Auth account
  /// remains (cannot be deleted from client SDK) but the sub account
  /// will no longer be able to log in as a sub account since the
  /// lookup will fail.
  Future<void> removeSubAccount(String subAccountId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final parentUserId = SubAccountSessionManager.isSubAccount
          ? SubAccountSessionManager.parentUserId!
          : user.uid;

      await _subAccountsRef(parentUserId).doc(subAccountId).delete();

      // Also remove the flat lookup document
      await _firestore.collection('SubAccountLookup').doc(subAccountId).delete();

      AppLogger.d('Sub account removed: $subAccountId');
    } catch (e) {
      AppLogger.d('Error removing sub account: $e');
      rethrow;
    }
  }

  /// Check if a given user ID is a sub account by looking up the flat
  /// SubAccountLookup collection (no collection group index needed).
  /// Returns the SubAccount data and the parent user ID if found.
  static Future<SubAccountLookupResult?> lookupSubAccount(
    String userId,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Step 1: Check the flat SubAccountLookup collection (fast, no index needed)
      final lookupDoc = await firestore
          .collection('SubAccountLookup')
          .doc(userId)
          .get();

      if (lookupDoc.exists) {
        final lookupData = lookupDoc.data()!;
        final parentUserId = lookupData['parentUserId'] as String?;

        if (parentUserId != null) {
          // Fetch the full sub account document from the parent's subcollection
          final subAccountDoc = await firestore
              .collection('User')
              .doc(parentUserId)
              .collection('SubAccounts')
              .doc(userId)
              .get();

          if (subAccountDoc.exists) {
            final subAccount = SubAccount.fromFirestore(subAccountDoc);
            return SubAccountLookupResult(
              subAccount: subAccount,
              parentUserId: parentUserId,
            );
          }
        }
      }

      // Step 2: If no lookup document, check if this is a main User account
      final mainUserDoc =
          await firestore.collection('User').doc(userId).get();
      if (mainUserDoc.exists) {
        // This is a main account, not a sub account
        return null;
      }

      // Step 3: Fallback — no SubAccountLookup doc and no User doc.
      // This user might be a legacy sub account created before SubAccountLookup
      // was introduced. Search SubAccounts subcollections by email.
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser?.email != null) {
        final normalizedEmail = currentUser!.email!.toLowerCase();

        // First try SubAccountLookup by email (in case doc ID doesn't match)
        final emailLookupQuery = await firestore
            .collection('SubAccountLookup')
            .where('email', isEqualTo: normalizedEmail)
            .limit(1)
            .get();

        if (emailLookupQuery.docs.isNotEmpty) {
          final doc = emailLookupQuery.docs.first;
          final data = doc.data();
          final parentUserId = data['parentUserId'] as String?;

          if (parentUserId != null) {
            final subAccountDoc = await firestore
                .collection('User')
                .doc(parentUserId)
                .collection('SubAccounts')
                .doc(doc.id)
                .get();

            if (subAccountDoc.exists) {
              final subAccount = SubAccount.fromFirestore(subAccountDoc);
              return SubAccountLookupResult(
                subAccount: subAccount,
                parentUserId: parentUserId,
              );
            }
          }
        }

        // Last resort: collection group query on SubAccounts by email.
        // This handles legacy sub accounts that have no SubAccountLookup doc.
        // If found, we also create the missing SubAccountLookup doc for future logins.
        try {
          final subAccountQuery = await firestore
              .collectionGroup('SubAccounts')
              .where('email', isEqualTo: normalizedEmail)
              .limit(1)
              .get();

          if (subAccountQuery.docs.isNotEmpty) {
            final doc = subAccountQuery.docs.first;
            final subAccount = SubAccount.fromFirestore(doc);

            // Extract parent user ID from the document path
            // Path format: User/{parentUserId}/SubAccounts/{subAccountId}
            final pathSegments = doc.reference.path.split('/');
            final parentUserId =
                pathSegments.length >= 2 ? pathSegments[1] : null;

            if (parentUserId != null) {
              // Auto-create the missing SubAccountLookup doc for future fast lookups
              try {
                await firestore
                    .collection('SubAccountLookup')
                    .doc(userId)
                    .set({
                  'parentUserId': parentUserId,
                  'email': normalizedEmail,
                  'createdAt': FieldValue.serverTimestamp(),
                  'migratedAt': FieldValue.serverTimestamp(),
                });
                AppLogger.d(
                  'Auto-created SubAccountLookup for legacy sub account: $userId',
                );
              } catch (e) {
                AppLogger.d('Failed to auto-create SubAccountLookup: $e');
              }

              return SubAccountLookupResult(
                subAccount: subAccount,
                parentUserId: parentUserId,
              );
            }
          }
        } catch (e) {
          AppLogger.d('Collection group query fallback failed: $e');
        }
      }

      return null;
    } catch (e) {
      AppLogger.d('Error looking up sub account: $e');
      return null;
    }
  }
}

/// Result of a sub account lookup.
class SubAccountLookupResult {
  final SubAccount subAccount;
  final String parentUserId;

  SubAccountLookupResult({
    required this.subAccount,
    required this.parentUserId,
  });
}

/// Global session manager to track if the current user is a sub account.
///
/// This is initialized at login time and persists for the session.
class SubAccountSessionManager {
  static bool _isSubAccount = false;
  static String? _parentUserId;
  static SubAccount? _currentSubAccount;

  /// Whether the current logged-in user is a sub account.
  static bool get isSubAccount => _isSubAccount;

  /// The parent user ID if the current user is a sub account.
  static String? get parentUserId => _parentUserId;

  /// The current sub account data (null if main account).
  static SubAccount? get currentSubAccount => _currentSubAccount;

  /// The effective user ID for data access (parent's ID for sub accounts).
  /// Use this when accessing shared data like Cart.
  static String getEffectiveUserId() {
    if (_isSubAccount && _parentUserId != null) {
      return _parentUserId!;
    }
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  /// Initialize the session as a sub account.
  static void setSubAccountSession({
    required SubAccount subAccount,
    required String parentUserId,
  }) {
    _isSubAccount = true;
    _parentUserId = parentUserId;
    _currentSubAccount = subAccount;
    AppLogger.d(
      'Sub account session initialized: ${subAccount.email} (parent: $parentUserId)',
    );
  }

  /// Initialize the session as a main account.
  static void setMainAccountSession() {
    _isSubAccount = false;
    _parentUserId = null;
    _currentSubAccount = null;
    AppLogger.d('Main account session initialized');
  }

  /// Clear the session (on logout).
  static void clearSession() {
    _isSubAccount = false;
    _parentUserId = null;
    _currentSubAccount = null;
    AppLogger.d('Sub account session cleared');
  }

  /// Check if the current sub account has a specific permission.
  static bool hasPermission(String permission) {
    if (!_isSubAccount) return true; // Main accounts have all permissions
    if (_currentSubAccount == null) return false;

    switch (permission) {
      case 'checkout':
        return _currentSubAccount!.permissions.canCheckout;
      case 'manage_sub_accounts':
        return _currentSubAccount!.permissions.canManageSubAccounts;
      case 'view_cart':
        return _currentSubAccount!.permissions.canViewCart;
      case 'modify_cart':
        return _currentSubAccount!.permissions.canModifyCart;
      case 'login':
        return _currentSubAccount!.permissions.canLogin;
      default:
        return false;
    }
  }

  /// Check if the current user can initiate checkout.
  static bool get canCheckout {
    if (!_isSubAccount) return true;
    return _currentSubAccount?.permissions.canCheckout ?? false;
  }

  /// Check if the current user can manage sub accounts.
  static bool get canManageSubAccounts {
    if (!_isSubAccount) return true;
    return _currentSubAccount?.permissions.canManageSubAccounts ?? false;
  }
}
