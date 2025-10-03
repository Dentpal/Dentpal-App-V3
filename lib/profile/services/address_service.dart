import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/shipping_address.dart';

class AddressService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user's addresses collection reference
  static CollectionReference get _addressesCollection {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return _firestore.collection('User').doc(userId).collection('Address');
  }

  // Create a new address
  static Future<String> createAddress(ShippingAddress address) async {
    try {
      // If this is being set as default, first unset all other defaults
      if (address.isDefault) {
        await _unsetAllDefaults();
      }

      final docRef = await _addressesCollection.add(address.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create address: $e');
    }
  }

  // Get all addresses for the current user
  static Future<List<ShippingAddress>> getAllAddresses() async {
    try {
      final querySnapshot = await _addressesCollection
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => ShippingAddress.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch addresses: $e');
    }
  }

  // Get addresses as a stream for real-time updates
  static Stream<List<ShippingAddress>> getAddressesStream() {
    try {
      return _addressesCollection
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => ShippingAddress.fromFirestore(doc))
              .toList());
    } catch (e) {
      throw Exception('Failed to get addresses stream: $e');
    }
  }

  // Get the default address
  static Future<ShippingAddress?> getDefaultAddress() async {
    try {
      final querySnapshot = await _addressesCollection
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return ShippingAddress.fromFirestore(querySnapshot.docs.first);
    } catch (e) {
      throw Exception('Failed to fetch default address: $e');
    }
  }

  // Update an existing address
  static Future<void> updateAddress(ShippingAddress address) async {
    try {
      // If this is being set as default, first unset all other defaults
      if (address.isDefault) {
        await _unsetAllDefaults();
      }

      final updatedAddress = address.copyWith(
        updatedAt: DateTime.now(),
      );

      await _addressesCollection.doc(address.id).update(updatedAddress.toMap());
    } catch (e) {
      throw Exception('Failed to update address: $e');
    }
  }

  // Delete an address
  static Future<void> deleteAddress(String addressId) async {
    try {
      await _addressesCollection.doc(addressId).delete();
    } catch (e) {
      throw Exception('Failed to delete address: $e');
    }
  }

  // Set an address as default
  static Future<void> setAsDefault(String addressId) async {
    try {
      // First, unset all current defaults
      await _unsetAllDefaults();

      // Then set the selected address as default
      await _addressesCollection.doc(addressId).update({
        'isDefault': true,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to set default address: $e');
    }
  }

  // Helper method to unset all default addresses
  static Future<void> _unsetAllDefaults() async {
    try {
      final defaultAddresses = await _addressesCollection
          .where('isDefault', isEqualTo: true)
          .get();

      final batch = _firestore.batch();
      for (final doc in defaultAddresses.docs) {
        batch.update(doc.reference, {
          'isDefault': false,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to unset default addresses: $e');
    }
  }

  // Get address by ID
  static Future<ShippingAddress?> getAddressById(String addressId) async {
    try {
      final doc = await _addressesCollection.doc(addressId).get();
      if (!doc.exists) {
        return null;
      }
      return ShippingAddress.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to fetch address: $e');
    }
  }

  // Check if user has any addresses
  static Future<bool> hasAddresses() async {
    try {
      final querySnapshot = await _addressesCollection.limit(1).get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Failed to check addresses: $e');
    }
  }

  // Get address count
  static Future<int> getAddressCount() async {
    try {
      final querySnapshot = await _addressesCollection.get();
      return querySnapshot.docs.length;
    } catch (e) {
      throw Exception('Failed to get address count: $e');
    }
  }

  // Validate address data before saving
  static String? validateAddress(ShippingAddress address) {
    if (address.fullName.trim().isEmpty) {
      return 'Full name is required';
    }
    if (address.addressLine1.trim().isEmpty) {
      return 'Address line 1 is required';
    }
    if (address.city.trim().isEmpty) {
      return 'City is required';
    }
    if (address.state.trim().isEmpty) {
      return 'State/Province is required';
    }
    if (address.postalCode.trim().isEmpty) {
      return 'Postal code is required';
    }
    if (address.country.trim().isEmpty) {
      return 'Country is required';
    }
    if (address.phoneNumber.trim().isEmpty) {
      return 'Phone number is required';
    }
    
    // Validate Philippine phone number format (+639XXXXXXXXX)
    final phoneNumber = address.phoneNumber.trim();
    if (!phoneNumber.startsWith('+63') || phoneNumber.length != 13) {
      return 'Invalid phone number format. Expected: +639XXXXXXXXX';
    }
    
    // Check if the rest are digits
    final numberPart = phoneNumber.substring(3);
    if (!RegExp(r'^\d{10}$').hasMatch(numberPart)) {
      return 'Phone number must contain only digits';
    }
    
    // Check if it starts with 9 (after +63)
    if (!numberPart.startsWith('9')) {
      return 'Phone number must start with 09 (after country code)';
    }
    
    return null;
  }

  // Helper method to format Philippine phone number
  static String formatPhoneNumber(String phoneNumber) {
    // Remove any spaces or special characters except +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    // If it starts with 09, convert to +639
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    
    // If it already starts with +63, return as is (if valid)
    if (cleaned.startsWith('+63') && cleaned.length == 13) {
      return cleaned;
    }
    
    // If it starts with 63, add +
    if (cleaned.startsWith('63') && cleaned.length == 12) {
      return '+$cleaned';
    }
    
    // Return original if no pattern matches
    return phoneNumber;
  }

  // Helper method to display phone number in 09XXXXXXXXX format
  static String displayPhoneNumber(String phoneNumber) {
    if (phoneNumber.startsWith('+63') && phoneNumber.length == 13) {
      return '0${phoneNumber.substring(3)}';
    }
    return phoneNumber;
  }
}
