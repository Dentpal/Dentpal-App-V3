import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the permissions a sub account can have.
class SubAccountPermissions {
  final bool canLogin;
  final bool canViewCart;
  final bool canModifyCart;
  final bool canCheckout;
  final bool canManageSubAccounts;

  const SubAccountPermissions({
    this.canLogin = true,
    this.canViewCart = true,
    this.canModifyCart = true,
    this.canCheckout = false,
    this.canManageSubAccounts = false,
  });

  /// Default permissions for a newly created sub account.
  factory SubAccountPermissions.defaultPermissions() {
    return const SubAccountPermissions(
      canLogin: true,
      canViewCart: true,
      canModifyCart: true,
      canCheckout: false,
      canManageSubAccounts: false,
    );
  }

  /// Full permissions (same as main account).
  factory SubAccountPermissions.fullPermissions() {
    return const SubAccountPermissions(
      canLogin: true,
      canViewCart: true,
      canModifyCart: true,
      canCheckout: true,
      canManageSubAccounts: true,
    );
  }

  factory SubAccountPermissions.fromMap(Map<String, dynamic> map) {
    return SubAccountPermissions(
      canLogin: map['canLogin'] as bool? ?? true,
      canViewCart: map['canViewCart'] as bool? ?? true,
      canModifyCart: map['canModifyCart'] as bool? ?? true,
      canCheckout: map['canCheckout'] as bool? ?? false,
      canManageSubAccounts: map['canManageSubAccounts'] as bool? ?? false,
    );
  }

  /// Parse from a comma-separated string like "Login, View cart, Modify Cart, Checkout"
  factory SubAccountPermissions.fromString(String permissions) {
    final lower = permissions.toLowerCase();
    return SubAccountPermissions(
      canLogin: lower.contains('login'),
      canViewCart: lower.contains('view cart'),
      canModifyCart: lower.contains('modify cart'),
      canCheckout: lower.contains('checkout'),
      canManageSubAccounts: lower.contains('manage sub accounts'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canLogin': canLogin,
      'canViewCart': canViewCart,
      'canModifyCart': canModifyCart,
      'canCheckout': canCheckout,
      'canManageSubAccounts': canManageSubAccounts,
    };
  }

  /// Returns a human-readable string of granted permissions.
  String toReadableString() {
    final granted = <String>[];
    if (canLogin) granted.add('Login');
    if (canViewCart) granted.add('View Cart');
    if (canModifyCart) granted.add('Modify Cart');
    if (canCheckout) granted.add('Checkout');
    if (canManageSubAccounts) granted.add('Manage Sub Accounts');
    return granted.join(', ');
  }

  SubAccountPermissions copyWith({
    bool? canLogin,
    bool? canViewCart,
    bool? canModifyCart,
    bool? canCheckout,
    bool? canManageSubAccounts,
  }) {
    return SubAccountPermissions(
      canLogin: canLogin ?? this.canLogin,
      canViewCart: canViewCart ?? this.canViewCart,
      canModifyCart: canModifyCart ?? this.canModifyCart,
      canCheckout: canCheckout ?? this.canCheckout,
      canManageSubAccounts: canManageSubAccounts ?? this.canManageSubAccounts,
    );
  }
}

/// Represents a sub account stored under User/{userId}/SubAccounts/{subAccountId}.
class SubAccount {
  final String id;
  final String email;
  final String name;
  final DateTime dateCreated;
  final SubAccountPermissions permissions;
  final bool isSubAccount;
  final String? parentUserId;

  SubAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.dateCreated,
    required this.permissions,
    this.isSubAccount = true,
    this.parentUserId,
  });

  factory SubAccount.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubAccount.fromMap(data, doc.id);
  }

  factory SubAccount.fromMap(Map<String, dynamic> data, String docId) {
    // Parse permissions - can be a map or a string
    SubAccountPermissions permissions;
    final permData = data['permissions'];
    if (permData is Map<String, dynamic>) {
      permissions = SubAccountPermissions.fromMap(permData);
    } else if (permData is String) {
      permissions = SubAccountPermissions.fromString(permData);
    } else {
      permissions = SubAccountPermissions.defaultPermissions();
    }

    // Parse dateCreated - can be a Timestamp, String, or Map with _seconds
    DateTime dateCreated;
    final dateData = data['dateCreated'];
    if (dateData is Timestamp) {
      dateCreated = dateData.toDate();
    } else if (dateData is String) {
      dateCreated = DateTime.tryParse(dateData) ?? DateTime.now();
    } else if (dateData is Map && dateData['_seconds'] != null) {
      dateCreated = DateTime.fromMillisecondsSinceEpoch(
        (dateData['_seconds'] as int) * 1000,
      );
    } else {
      dateCreated = DateTime.now();
    }

    return SubAccount(
      id: data['id'] as String? ?? docId,
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      dateCreated: dateCreated,
      permissions: permissions,
      isSubAccount: data['isSubAccount'] as bool? ?? true,
      parentUserId: data['parentUserId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'dateCreated': Timestamp.fromDate(dateCreated),
      'permissions': permissions.toMap(),
      'isSubAccount': isSubAccount,
      if (parentUserId != null) 'parentUserId': parentUserId,
    };
  }
}
