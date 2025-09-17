import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

/// This is a simple admin tool to add sample products to your Firestore database
class SeedProductsPage extends StatefulWidget {
  const SeedProductsPage({super.key});

  @override
  _SeedProductsPageState createState() => _SeedProductsPageState();
}

class _SeedProductsPageState extends State<SeedProductsPage> {
  bool _isLoading = false;
  String _statusMessage = '';
  int _productsAdded = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _sellerId;
  
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }
  
  Future<void> _checkAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _statusMessage = 'You must be logged in to use this feature.';
      });
    }
  }

  Future<void> _addSampleProducts() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to add products')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating sample seller...';
      _productsAdded = 0;
    });

    try {
      // Add sample seller
      _sellerId = await _addSampleSeller();
      
      // Add sample products
      await _addProducts();
      
      setState(() {
        _statusMessage = 'Successfully added $_productsAdded products to the database.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<String> _addSampleSeller() async {
    // Check if sample seller already exists
    final QuerySnapshot sellerQuery = await _firestore.collection('Seller')
        .where('shopName', isEqualTo: 'DentPal Official Store')
        .get();
    
    if (sellerQuery.docs.isNotEmpty) {
      setState(() {
        _statusMessage = 'Using existing seller: DentPal Official Store';
      });
      return sellerQuery.docs.first.id;
    }

    // Create a sample user first (or use current user)
    final currentUser = FirebaseAuth.instance.currentUser!;
    
    // Check if user record exists
    DocumentReference userRef;
    final userQuery = await _firestore.collection('User')
        .where('email', isEqualTo: currentUser.email)
        .get();
    
    if (userQuery.docs.isNotEmpty) {
      userRef = userQuery.docs.first.reference;
    } else {
      // Create user document
      userRef = await _firestore.collection('User').add({
        'displayName': currentUser.displayName ?? 'Store Admin',
        'email': currentUser.email,
        'photoURL': currentUser.photoURL ?? '',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'role': 'seller'
      });
    }
    
    // Create the seller
    final sellerRef = await _firestore.collection('Seller').add({
      'userID': userRef.id,
      'shopName': 'DentPal Official Store',
      'contactEmail': currentUser.email,
      'contactNumber': '+12345678901',
      'address': '123 Dental Street, Medical District, City',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'isActive': true
    });
    
    setState(() {
      _statusMessage = 'Created new seller: DentPal Official Store';
    });
    return sellerRef.id;
  }
  
  Future<void> _addProducts() async {
    if (_sellerId == null) {
      throw Exception('Seller ID is required');
    }
    
    final List<Map<String, dynamic>> products = [
      {
        'name': 'Professional Dental Cleaning Kit',
        'description': 'Complete kit for professional dental cleaning, including scaling tools, polishers, and fluoride treatments.',
        'imageURL': 'https://images.unsplash.com/photo-1606811971618-4486d14f3f99?w=800&auto=format&fit=crop&q=60',
        'category': 'Dental Kits',
        'sellerId': _sellerId,
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
        'sellerId': _sellerId,
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
        'sellerId': _sellerId,
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
        'sellerId': _sellerId,
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
        'sellerId': _sellerId,
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
      }
    ];
    
    for (var product in products) {
      setState(() {
        _statusMessage = 'Adding product: ${product['name']}';
      });
      
      final List<Map<String, dynamic>> variations = 
          List<Map<String, dynamic>>.from(product.remove('variations') as List);
          
      // Add product
      final DocumentReference productRef = await _firestore.collection('Product').add({
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
      
      setState(() {
        _productsAdded++;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Sample Products'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sample Products Generator',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This tool will add sample dental products to your Firestore database for testing purposes.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (_statusMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('Error') 
                      ? Colors.red.shade100 
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusMessage),
              ),
              const SizedBox(height: 24),
            ],
            ElevatedButton(
              onPressed: _isLoading ? null : _addSampleProducts,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              ),
              child: _isLoading 
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Adding Products...'),
                      ],
                    )
                  : const Text('Add Sample Products'),
            ),
          ],
        ),
      ),
    );
  }
}

// Entry point for running this tool directly
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    MaterialApp(
      title: 'DentPal Product Seeder',
      theme: ThemeData(
        primaryColor: const Color(0xFF43A047),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF43A047),
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const SeedProductsPage(),
    ),
  );
}
