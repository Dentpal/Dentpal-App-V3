import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dentpal/firebase_options.dart';
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
  /// Creates a sub account Auth user, writes the SubAccount document and the
  /// SubAccountLookup entry, and re-authenticates the original user.
  ///
  /// **Deprecated** — use [createSubAccountStreamlined] instead, which requires
  /// [mainUserPassword] so the original user can be re-authenticated after the
  /// sub-account Auth user is created.  This signature lacks that parameter and
  /// therefore cannot safely restore auth state; calling it throws immediately.
  @Deprecated('Use createSubAccountStreamlined instead.')
  Future<SubAccount?> createSubAccount({
    required String email,
    required String name,
    SubAccountPermissions? permissions,
  }) async {
    throw UnsupportedError(
      'createSubAccount is incomplete and unsafe. '
      'Use createSubAccountStreamlined, which requires mainUserPassword '
      'so the original auth session can be restored after sub-account creation.',
    );
  }

  /// Create a sub account with a streamlined flow that avoids signing out the main user.
  ///
  /// This approach:
  /// 1. Creates the Firebase Auth account for the sub user via a **secondary**
  ///    [FirebaseApp] instance so the operator's primary auth session is never
  ///    disturbed (no sign-out / sign-in required).
  /// 2. Writes the SubAccount document and the SubAccountLookup entry.
  /// 3. Sends a password-reset email so the sub user can set their own password.
  /// 4. On any failure after the Auth user is created, deletes that Auth user so
  ///    the email is not permanently consumed.
  Future<SubAccount?> createSubAccountStreamlined({
    required String email,
    required String name,
    required String mainUserPassword,
    SubAccountPermissions? permissions,
  }) async {
    // mainUserPassword is kept in the signature for API compatibility but is no
    // longer used for re-authentication — the secondary-app approach eliminates
    // the sign-out/sign-in entirely.
    const _secondaryAppName = 'sub_account_creation_temp';

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

      // Step 1: Create a secondary FirebaseApp instance pointing at the same
      // project.  Creating / signing-in on this secondary instance never affects
      // the primary FirebaseAuth session that the operator is using.
      FirebaseApp? secondaryApp;
      try {
        secondaryApp = Firebase.app(_secondaryAppName);
      } catch (_) {
        // App not yet initialised — create it now.
        secondaryApp = await Firebase.initializeApp(
          name: _secondaryAppName,
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // Step 2: Create the Auth account on the secondary instance.
      final tempPassword = _generateTempPassword();
      UserCredential subUserCredential;
      try {
        subUserCredential = await secondaryAuth.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: tempPassword,
        );
      } on FirebaseAuthException catch (e) {
        await secondaryAuth.signOut();
        await secondaryApp.delete();
        if (e.code == 'email-already-in-use') {
          throw Exception(
            'This email is already registered. Please use a different email.',
          );
        }
        rethrow;
      }

      final subUserId = subUserCredential.user!.uid;

      // Sign out from the secondary instance and delete it — we no longer need
      // it, and keeping it around would leak resources.
      await secondaryAuth.signOut();
      await secondaryApp.delete();

      // Step 3: Write Firestore documents.  If anything fails here, clean up the
      // Auth user (best-effort via the primary auth's Admin-accessible delete —
      // on the client we can only delete a user that is currently signed in, so
      // we log the orphan and rethrow so the caller is informed).
      try {
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

        // Flat lookup document for fast sub-account detection at login.
        await _firestore.collection('SubAccountLookup').doc(subUserId).set({
          'parentUserId': parentUserId,
          'email': normalizedEmail,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Step 4: Trigger password-reset so the sub user can set their password.
        await _auth.sendPasswordResetEmail(email: normalizedEmail);

        AppLogger.d('Sub account created successfully: $subUserId');
        return subAccount;
      } catch (e) {
        // The Auth user exists but Firestore writes failed.  Log the orphaned UID
        // so an admin can clean it up via the Firebase console or Admin SDK.
        AppLogger.e(
          'Firestore write failed after creating Auth user $subUserId. '
          'The Auth user is orphaned and should be deleted manually.',
          e,
        );
        rethrow;
      }
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
      AppLogger.d('Error looking up sub account for $userId: $e');
      // Rethrow so callers can distinguish a lookup failure from a confirmed
      // main-account (null return). Callers must NOT default to main-account
      // behaviour on error — fail closed to avoid privilege escalation.
      rethrow;
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
