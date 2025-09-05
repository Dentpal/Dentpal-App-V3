import 'package:flutter/material.dart';
import '../models/product_form_model.dart';
import '../services/product_service.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({Key? key}) : super(key: key);

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final ProductFormModel _productForm = ProductFormModel();
  final List<VariationFormModel> _variations = [VariationFormModel()];
  final ProductService _productService = ProductService();
  
  // Add controllers for all text fields
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final List<Map<String, TextEditingController>> _variationControllers = [];

  bool _isLoading = false;
  String _errorMessage = '';
  bool _isSeller = false;
  String _sellerMessage = '';

  final List<String> _categories = [
    'Dental Equipment',
    'Dental Supplies',
    'Dental Instruments',
    'Dental Materials',
    'Dental Accessories',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _checkSellerStatus();
    _initializeVariationControllers();
  }
  
  // Initialize controllers for the first variation
  void _initializeVariationControllers() {
    _variationControllers.add({
      'imageURL': TextEditingController(),
      'price': TextEditingController(text: '0'),
      'stock': TextEditingController(text: '0'),
      'sku': TextEditingController(),
      'weight': TextEditingController(),
      'length': TextEditingController(text: '0'),
      'width': TextEditingController(text: '0'),
      'height': TextEditingController(text: '0'),
    });
  }
  
  @override
  void dispose() {
    // Dispose all controllers to prevent memory leaks
    _nameController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    for (var controllers in _variationControllers) {
      controllers.values.forEach((controller) => controller.dispose());
    }
    super.dispose();
  }

  Future<void> _checkSellerStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _productService.checkSellerStatus();
      
      setState(() {
        _isSeller = result['isSeller'];
        _sellerMessage = result['message'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isSeller = false;
        _sellerMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  void _addVariation() {
    setState(() {
      _variations.add(VariationFormModel());
      // Add controllers for the new variation
      _variationControllers.add({
        'imageURL': TextEditingController(),
        'price': TextEditingController(text: '0'),
        'stock': TextEditingController(text: '0'),
        'sku': TextEditingController(),
        'weight': TextEditingController(),
        'length': TextEditingController(text: '0'),
        'width': TextEditingController(text: '0'),
        'height': TextEditingController(text: '0'),
      });
    });
  }

  void _removeVariation(int index) {
    if (_variations.length > 1) {
      setState(() {
        _variations.removeAt(index);
        // Dispose controllers for the removed variation
        final controllers = _variationControllers.removeAt(index);
        controllers.values.forEach((controller) => controller.dispose());
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least one variation')),
      );
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Save all form fields
    _formKey.currentState!.save();
    
    // Manually transfer values from controllers to models
    _productForm.name = _nameController.text;
    _productForm.description = _descriptionController.text;
    _productForm.imageURL = _imageUrlController.text;
    
    // Set variation values from controllers
    for (int i = 0; i < _variations.length; i++) {
      final controllers = _variationControllers[i];
      _variations[i].imageURL = controllers['imageURL']!.text;
      _variations[i].price = double.tryParse(controllers['price']!.text) ?? 0;
      _variations[i].stock = int.tryParse(controllers['stock']!.text) ?? 0;
      _variations[i].sku = controllers['sku']!.text;
      _variations[i].weight = controllers['weight']!.text.isNotEmpty ? 
                             double.tryParse(controllers['weight']!.text) : null;
      
      // Set dimensions
      _variations[i].dimensions = {
        'length': double.tryParse(controllers['length']!.text) ?? 0,
        'width': double.tryParse(controllers['width']!.text) ?? 0,
        'height': double.tryParse(controllers['height']!.text) ?? 0,
      };
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await _productService.addProduct(_productForm, _variations);

      setState(() {
        _isLoading = false;
      });

      if (result['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'])),
          );
          // Navigate back or to product detail
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage = result['message'];
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Product')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isSeller) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Product')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                Text(
                  'Seller Access Required',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  _sellerMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Product')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                // Product Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Product Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Description is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Product Image URL
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL *',
                    border: OutlineInputBorder(),
                    hintText: 'https://example.com/image.jpg',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Image URL is required';
                    }
                    try {
                      final uri = Uri.parse(value);
                      if (!uri.isAbsolute) {
                        return 'Please enter a valid URL';
                      }
                      return null;
                    } catch (e) {
                      return 'Invalid URL format';
                    }
                  },
                  onChanged: (value) {
                    // Update UI when image URL changes
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),

                // Preview Image
                Builder(
                  builder: (context) {
                    final imageURL = _imageUrlController.text;
                    if (imageURL.isNotEmpty) {
                      try {
                        final uri = Uri.parse(imageURL);
                        if (uri.isAbsolute) {
                          return Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Image.network(
                              imageURL,
                              fit: BoxFit.contain,
                              errorBuilder: (context, _, __) => const Center(
                                child: Text('Invalid image URL'),
                              ),
                            ),
                          );
                        }
                      } catch (_) {}
                    }
                    return Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: Text('Enter a valid image URL to see preview'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Category
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _productForm.category = value ?? '';
                    });
                  },
                  validator: (_) => _productForm.validateCategory(),
                ),
                
                const SizedBox(height: 24),
                const Text(
                  'Product Variations',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add at least one variation with price, stock, and SKU',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Variations
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _variations.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Variation ${index + 1}', 
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16
                                  )
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeVariation(index),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Variation Image URL (Optional)
                            TextFormField(
                              controller: _variationControllers[index]['imageURL'],
                              decoration: const InputDecoration(
                                labelText: 'Variation Image URL (Optional)',
                                border: OutlineInputBorder(),
                                hintText: 'https://example.com/variation.jpg',
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Price
                            TextFormField(
                              controller: _variationControllers[index]['price'],
                              decoration: const InputDecoration(
                                labelText: 'Price *',
                                border: OutlineInputBorder(),
                                prefixText: '\$ ',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Price is required';
                                }
                                final price = double.tryParse(value);
                                if (price == null) {
                                  return 'Please enter a valid number';
                                }
                                if (price <= 0) {
                                  return 'Price must be greater than 0';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Stock
                            TextFormField(
                              controller: _variationControllers[index]['stock'],
                              decoration: const InputDecoration(
                                labelText: 'Stock *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Stock is required';
                                }
                                final stock = int.tryParse(value);
                                if (stock == null) {
                                  return 'Please enter a valid number';
                                }
                                if (stock < 0) {
                                  return 'Stock cannot be negative';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // SKU
                            TextFormField(
                              controller: _variationControllers[index]['sku'],
                              decoration: const InputDecoration(
                                labelText: 'SKU *',
                                border: OutlineInputBorder(),
                                hintText: 'Unique product identifier',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'SKU is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Weight (Optional)
                            TextFormField(
                              controller: _variationControllers[index]['weight'],
                              decoration: const InputDecoration(
                                labelText: 'Weight (g) (Optional)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value != null && value.isNotEmpty) {
                                  final weight = double.tryParse(value);
                                  if (weight == null) {
                                    return 'Please enter a valid number';
                                  }
                                  if (weight < 0) {
                                    return 'Weight cannot be negative';
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Dimensions
                            const Text('Dimensions (Optional)', 
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500
                              )
                            ),
                            const SizedBox(height: 8),
                            
                            // Dimensions fields
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _variationControllers[index]['length'],
                                    decoration: const InputDecoration(
                                      labelText: 'Length (cm)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value != null && value.isNotEmpty) {
                                        final length = double.tryParse(value);
                                        if (length == null) {
                                          return 'Invalid';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _variationControllers[index]['width'],
                                    decoration: const InputDecoration(
                                      labelText: 'Width (cm)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value != null && value.isNotEmpty) {
                                        final width = double.tryParse(value);
                                        if (width == null) {
                                          return 'Invalid';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _variationControllers[index]['height'],
                                    decoration: const InputDecoration(
                                      labelText: 'Height (cm)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value != null && value.isNotEmpty) {
                                        final height = double.tryParse(value);
                                        if (height == null) {
                                          return 'Invalid';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
                // Add Variation Button
                OutlinedButton.icon(
                  onPressed: _addVariation,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Variation'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),

                const SizedBox(height: 32),
                
                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Add Product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
