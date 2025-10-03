import 'package:cloud_firestore/cloud_firestore.dart';

class ShippingAddress {
  final String id;
  final String fullName;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final String phoneNumber;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  ShippingAddress({
    required this.id,
    required this.fullName,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.phoneNumber,
    this.latitude,
    this.longitude,
    this.notes,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'postalCode': postalCode,
      'country': country,
      'phoneNumber': phoneNumber,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from Firestore DocumentSnapshot
  factory ShippingAddress.fromMap(Map<String, dynamic> map, String id) {
    return ShippingAddress(
      id: id,
      fullName: map['fullName'] ?? '',
      addressLine1: map['addressLine1'] ?? '',
      addressLine2: map['addressLine2'],
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      postalCode: map['postalCode'] ?? '',
      country: map['country'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      notes: map['notes'],
      isDefault: map['isDefault'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  factory ShippingAddress.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ShippingAddress.fromMap(data, doc.id);
  }

  // Convert to Paymongo-compatible format
  Map<String, dynamic> toPaymongoFormat() {
    return {
      'line_1': addressLine1,
      'line_2': addressLine2 ?? '',
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'country': country.toUpperCase(), // Paymongo expects country code in uppercase
    };
  }

  // Copy with method for updates
  ShippingAddress copyWith({
    String? id,
    String? fullName,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? phoneNumber,
    double? latitude,
    double? longitude,
    String? notes,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShippingAddress(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      notes: notes ?? this.notes,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ShippingAddress(id: $id, fullName: $fullName, addressLine1: $addressLine1, city: $city, state: $state, postalCode: $postalCode, country: $country, isDefault: $isDefault)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShippingAddress && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // Helper method to get formatted address string
  String get formattedAddress {
    List<String> parts = [
      fullName,
      addressLine1,
      if (addressLine2 != null && addressLine2!.isNotEmpty) addressLine2!,
      '$city, $state $postalCode',
      country,
    ];
    return parts.join('\n');
  }

  // Helper method to get single line address
  String get singleLineAddress {
    List<String> parts = [
      addressLine1,
      if (addressLine2 != null && addressLine2!.isNotEmpty) addressLine2!,
      city,
      state,
      postalCode,
      country,
    ];
    return parts.join(', ');
  }
}
