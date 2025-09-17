import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'package:dentpal/utils/app_logger.dart';

/// This script adds sample dental products to the Firestore database
/// Run it with: dart run lib/utils/add_sample_products.dart

Future<void> main() async {
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Reference to Firestore
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Add sample seller
  final String sellerId = await addSampleSeller(firestore);

  // Sample dental products
  final List<Map<String, dynamic>> products = [
    {
      'name': 'Professional Dental Cleaning Kit',
      'description': 'Complete kit for professional dental cleaning, including scaling tools, polishers, and fluoride treatments.',
      'imageURL': 'https://images.unsplash.com/photo-1606811971618-4486d14f3f99?w=800&auto=format&fit=crop&q=60',
      'category': 'Dental Kits',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 89.99,
          'stock': 25,
          'SKU': 'DK-CLEAN-001',
          'weight': 0.75,
          'dimensions': {
            'length': 20,
            'width': 15,
            'height': 8
          }
        },
        {
          'price': 129.99,
          'stock': 15,
          'SKU': 'DK-CLEAN-002-PRO',
          'weight': 1.2,
          'dimensions': {
            'length': 25,
            'width': 18,
            'height': 10
          }
        }
      ]
    },
    {
      'name': 'Electric Toothbrush - Premium Model',
      'description': 'Advanced electric toothbrush with 5 cleaning modes, pressure sensor, and smart timer. Includes charging station and travel case.',
      'imageURL': 'https://images.unsplash.com/photo-1559591937-abc3eb40a461?w=800&auto=format&fit=crop&q=60',
      'category': 'Toothbrushes',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 59.99,
          'stock': 50,
          'SKU': 'TB-ELEC-001-BLACK',
          'weight': 0.35,
          'dimensions': {
            'length': 8,
            'width': 4,
            'height': 25
          }
        },
        {
          'price': 59.99,
          'stock': 45,
          'SKU': 'TB-ELEC-001-WHITE',
          'weight': 0.35,
          'dimensions': {
            'length': 8,
            'width': 4,
            'height': 25
          }
        }
      ]
    },
    {
      'name': 'Teeth Whitening Kit - Professional Strength',
      'description': 'Professional-grade teeth whitening kit with LED light, whitening gel, and custom mouth trays. Safe for sensitive teeth.',
      'imageURL': 'https://images.unsplash.com/photo-1570357602675-bce66e3b0aa6?w=800&auto=format&fit=crop&q=60',
      'category': 'Teeth Whitening',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 49.99,
          'stock': 30,
          'SKU': 'TW-KIT-001',
          'weight': 0.5,
          'dimensions': {
            'length': 15,
            'width': 10,
            'height': 5
          }
        }
      ]
    },
    {
      'name': 'Dental Floss Pack - Mint Flavored',
      'description': 'Pack of 5 mint-flavored dental floss spools. Waxed for easy use and comfort.',
      'imageURL': 'https://images.unsplash.com/photo-1612540943977-97fe1cd19fd2?w=800&auto=format&fit=crop&q=60',
      'category': 'Dental Care',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 12.99,
          'stock': 100,
          'SKU': 'DF-MINT-005',
          'weight': 0.15,
          'dimensions': {
            'length': 10,
            'width': 8,
            'height': 3
          }
        }
      ]
    },
    {
      'name': 'Orthodontic Braces Cleaning Kit',
      'description': 'Complete kit for cleaning braces and orthodontic appliances. Includes specialized brushes, floss threaders, and carrying case.',
      'imageURL': 'https://images.unsplash.com/photo-1588776814546-daab30f310ce?w=800&auto=format&fit=crop&q=60',
      'category': 'Orthodontics',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 24.99,
          'stock': 40,
          'SKU': 'OB-CLEAN-001',
          'weight': 0.3,
          'dimensions': {
            'length': 12,
            'width': 8,
            'height': 4
          }
        }
      ]
    },
    {
      'name': 'Dental Impression Kit',
      'description': 'DIY dental impression kit for creating custom mouth guards, whitening trays, or for consultation purposes.',
      'imageURL': 'https://images.unsplash.com/photo-1609840112990-4265448268d1?w=800&auto=format&fit=crop&q=60',
      'category': 'Professional Tools',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 34.99,
          'stock': 20,
          'SKU': 'DI-KIT-001',
          'weight': 0.45,
          'dimensions': {
            'length': 15,
            'width': 10,
            'height': 5
          }
        }
      ]
    },
    {
      'name': 'Sensitivity Relief Toothpaste - 3 Pack',
      'description': 'Clinically proven toothpaste for sensitive teeth. Provides long-lasting relief and strengthens enamel.',
      'imageURL': 'https://images.unsplash.com/photo-1612528845834-bcff84c3307b?w=800&auto=format&fit=crop&q=60',
      'category': 'Dental Care',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 18.99,
          'stock': 60,
          'SKU': 'TP-SENS-003',
          'weight': 0.45,
          'dimensions': {
            'length': 15,
            'width': 5,
            'height': 3
          }
        }
      ]
    },
    {
      'name': 'Dental X-Ray Film Holder Set',
      'description': 'Professional dental x-ray film holder set with positioning rings for accurate radiographic imaging.',
      'imageURL': 'https://images.unsplash.com/photo-1629909613654-28e377c37b09?w=800&auto=format&fit=crop&q=60',
      'category': 'Professional Tools',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 79.99,
          'stock': 15,
          'SKU': 'DX-HOLD-001',
          'weight': 0.6,
          'dimensions': {
            'length': 20,
            'width': 15,
            'height': 5
          }
        }
      ]
    },
    {
      'name': 'Oral Irrigator - Water Flosser',
      'description': 'Advanced water flosser with multiple pressure settings and specialized tips for comprehensive oral hygiene.',
      'imageURL': 'https://images.unsplash.com/photo-1591175524837-399d0c375c6e?w=800&auto=format&fit=crop&q=60',
      'category': 'Dental Care',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 69.99,
          'stock': 35,
          'SKU': 'OI-WATER-001',
          'weight': 0.85,
          'dimensions': {
            'length': 22,
            'width': 15,
            'height': 10
          }
        }
      ]
    },
    {
      'name': 'Children\'s Educational Dental Model',
      'description': 'Educational dental model for teaching children proper brushing techniques and dental anatomy.',
      'imageURL': 'https://images.unsplash.com/photo-1588776814546-daab30f310ce?w=800&auto=format&fit=crop&q=60',
      'category': 'Educational',
      'sellerId': sellerId,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true,
      'variations': [
        {
          'price': 29.99,
          'stock': 25,
          'SKU': 'ED-DENT-CHILD-001',
          'weight': 0.7,
          'dimensions': {
            'length': 15,
            'width': 12,
            'height': 10
          }
        }
      ]
    }
  ];

  // Add all products
  int count = 0;
  for (var product in products) {
    final List<Map<String, dynamic>> variations = 
        List<Map<String, dynamic>>.from(product.remove('variations') as List);
        
    // Add product
    final DocumentReference productRef = await firestore.collection('Product').add({
      'name': product['name'],
      'description': product['description'],
      'imageURL': product['imageURL'],
      'category': product['category'],
      'sellerId': product['sellerId'],
      'createdAt': product['createdAt'],
      'updatedAt': product['updatedAt'],
      'isActive': product['isActive'],
    });
    
    // Add variations
    for (var variation in variations) {
      await productRef.collection('Variation').add({
        'productId': productRef.id,
        'price': variation['price'],
        'stock': variation['stock'],
        'SKU': variation['SKU'],
        'weight': variation['weight'],
        'dimensions': variation['dimensions'],
      });
    }
    
    count++;
    AppLogger.d('Added product: ${product['name']}');
  }
  
  AppLogger.d('Successfully added $count products to the database.');
}

Future<String> addSampleSeller(FirebaseFirestore firestore) async {
  // Check if sample seller already exists
  final QuerySnapshot sellerQuery = await firestore.collection('Seller')
      .where('shopName', isEqualTo: 'DentPal Official Store')
      .get();
  
  if (sellerQuery.docs.isNotEmpty) {
    AppLogger.d('Using existing seller: DentPal Official Store');
    return sellerQuery.docs.first.id;
  }

  // Create a sample user first
  final userRef = await firestore.collection('User').add({
    'displayName': 'DentPal Products Test',
    'email': 'store@dentpal.com',
    'photoURL': '',
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
    'role': 'seller'
  });
  
  // Create the seller
  final sellerRef = await firestore.collection('Seller').add({
    'userID': userRef.id,
    'shopName': 'DentPal Official Store',
    'contactEmail': 'store@dentpal.com',
    'contactNumber': '+12345678901',
    'address': '123 Dental Street, Medical District, City',
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
    'isActive': true
  });
  
  AppLogger.d('Created new seller: DentPal Official Store');
  return sellerRef.id;
}
