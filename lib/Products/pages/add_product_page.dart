import 'package:flutter/material.dart';
import '../models/product_form_model.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/image_upload_service.dart';
import 'package:dentpal/utils/app_logger.dart';


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
  final CategoryService _categoryService = CategoryService();
  final ImageUploadService _imageUploadService = ImageUploadService();
  
  // Add controllers for all text fields
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<Map<String, TextEditingController>> _variationControllers = [];

  bool _isLoading = false;
  bool _isCategoriesLoading = true;
  String _errorMessage = '';
  bool _isSeller = false;
  String _sellerMessage = '';

  // Dynamic categories and subcategories
  List<Category> _categories = [];
  List<SubCategory> _subCategories = [];
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;

    @override
  void initState() {
    super.initState();
    _initializeVariationControllers();
    _checkSellerStatus();
    _loadCategories();
  }

  void _loadCategories() async {
    setState(() {
      _isCategoriesLoading = true;
    });
    
    try {
      final categories = await _categoryService.getCategories();
      AppLogger.d('✅ Loaded ${categories.length} categories');
      
      // Debug: Print category details
      for (var cat in categories) {
        AppLogger.d('  - Category: ${cat.categoryName} (ID: ${cat.categoryId})');
      }
      
      setState(() {
        _categories = categories;
        _isCategoriesLoading = false;
      });
    } catch (e) {
      AppLogger.d('❌ Error loading categories: $e');
      setState(() {
        _isCategoriesLoading = false;
        _errorMessage = 'Failed to load categories: $e';
      });
    }
  }

  void _loadSubCategories(String categoryId) async {
    AppLogger.d('🔍 Loading subcategories for categoryId: $categoryId');
    
    try {
      final subCategories = await _categoryService.getSubCategories(categoryId);
      AppLogger.d('✅ Received ${subCategories.length} subcategories');
      
      // Debug: Print subcategory details
      for (var subCat in subCategories) {
        AppLogger.d('  - SubCategory: ${subCat.subCategoryName} (ID: ${subCat.subCategoryId}, CategoryID: ${subCat.categoryId})');
      }
      
      setState(() {
        _subCategories = subCategories;
        _selectedSubCategoryId = null; // Reset subcategory selection
        _productForm.subCategoryId = null;
      });
    } catch (e) {
      AppLogger.d('❌ Error loading subcategories: $e');
      setState(() {
        _errorMessage = 'Failed to load subcategories: $e';
        _subCategories = [];
      });
    }
  }
  
  // Initialize controllers for the first variation
  void _initializeVariationControllers() {
    _variationControllers.add({
      'name': TextEditingController(),
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
    for (var controllers in _variationControllers) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
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
        'name': TextEditingController(),
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
        for (var controller in controllers.values) {
          controller.dispose();
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least one variation')),
      );
    }
  }

  // Pick main product image
  Future<void> _pickProductImage() async {
    final source = await _imageUploadService.showImageSourceDialog(context);
    if (source == null) return;

    final pickedFile = await _imageUploadService.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _productForm.imageFile = pickedFile;
      });
    }
  }

  // Pick variation image
  Future<void> _pickVariationImage(int index) async {
    final source = await _imageUploadService.showImageSourceDialog(context);
    if (source == null) return;

    final pickedFile = await _imageUploadService.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _variations[index].imageFile = pickedFile;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if main product image is selected
    if (_productForm.imageFile == null) {
      setState(() {
        _errorMessage = 'Please select a product image';
      });
      return;
    }

    // Save all form fields
    _formKey.currentState!.save();
    
    // Manually transfer values from controllers to models
    _productForm.name = _nameController.text;
    _productForm.description = _descriptionController.text;
    
    // Set variation values from controllers
    for (int i = 0; i < _variations.length; i++) {
      final controllers = _variationControllers[i];
      _variations[i].name = controllers['name']!.text;
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
      // First, upload images to Firebase Storage
      String productId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Upload main product image
      if (_productForm.imageFile != null) {
        final productImageBytes = await _imageUploadService.resizeImage(_productForm.imageFile!);
        if (productImageBytes != null) {
          final productImageUrl = await _imageUploadService.uploadImage(
            imageBytes: productImageBytes,
            path: ImageUploadService.getProductImagePath(productId),
          );
          
          if (productImageUrl != null) {
            _productForm.imageURL = productImageUrl;
          } else {
            throw Exception('Failed to upload product image');
          }
        } else {
          throw Exception('Failed to resize product image');
        }
      }
      
      // Upload variation images
      for (int i = 0; i < _variations.length; i++) {
        if (_variations[i].imageFile != null) {
          final variationImageBytes = await _imageUploadService.resizeImage(_variations[i].imageFile!);
          if (variationImageBytes != null) {
            final variationImageUrl = await _imageUploadService.uploadImage(
              imageBytes: variationImageBytes,
              path: ImageUploadService.getVariationImagePath(productId, i),
            );
            
            if (variationImageUrl != null) {
              _variations[i].imageURL = variationImageUrl;
            }
            // Note: Variation images are optional, so we don't throw an error if upload fails
          }
        }
      }

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

                // Product Image
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      if (_productForm.imageFile != null)
                        Container(
                          height: 200,
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          child: Image.file(
                            _productForm.imageFile!,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        SizedBox(
                          height: 150,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('No image selected'),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _pickProductImage,
                                icon: const Icon(Icons.add_a_photo),
                                label: Text(_productForm.imageFile != null 
                                    ? 'Change Image' 
                                    : 'Add Image *'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _productForm.imageFile != null 
                                      ? Colors.blue 
                                      : Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            if (_productForm.imageFile != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _productForm.imageFile = null;
                                  });
                                },
                                icon: const Icon(Icons.delete, color: Colors.red),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Category
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _selectedCategoryId,
                  items: _isCategoriesLoading 
                    ? [const DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _categories.map((category) {
                        return DropdownMenuItem(
                          value: category.categoryId,
                          child: Text(category.categoryName),
                        );
                      }).toList(),
                  onChanged: _isCategoriesLoading ? null : (value) {
                    AppLogger.d('🔍 Category selected: $value');
                    setState(() {
                      _selectedCategoryId = value;
                      _productForm.categoryId = value ?? '';
                    });
                    if (value != null) {
                      _loadSubCategories(value);
                    }
                  },
                  validator: (_) => _productForm.validateCategory(),
                ),
                
                const SizedBox(height: 16),

                // SubCategory
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'SubCategory *',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _selectedSubCategoryId,
                  items: _selectedCategoryId == null 
                    ? [const DropdownMenuItem(value: null, child: Text('Select a category first'))]
                    : _subCategories.isEmpty
                    ? [const DropdownMenuItem(value: null, child: Text('No subcategories available'))]
                    : _subCategories.map((subCategory) {
                        return DropdownMenuItem(
                          value: subCategory.subCategoryId,
                          child: Text(subCategory.subCategoryName),
                        );
                      }).toList(),
                  onChanged: _selectedCategoryId == null ? null : (value) {
                    setState(() {
                      _selectedSubCategoryId = value;
                      _productForm.subCategoryId = value;
                    });
                  },
                  validator: (_) => _productForm.validateSubCategory(),
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
                            
                            // Variation Name
                            TextFormField(
                              controller: _variationControllers[index]['name'],
                              decoration: const InputDecoration(
                                labelText: 'Variation Name *',
                                border: OutlineInputBorder(),
                                hintText: 'e.g., Small, Blue, Standard',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Variation name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Variation Image (Optional)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text(
                                      'Variation Image (Optional)',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (_variations[index].imageFile != null)
                                    Container(
                                      height: 120,
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      child: Image.file(
                                        _variations[index].imageFile!,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      height: 80,
                                      child: const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.image, size: 32, color: Colors.grey),
                                            Text('No image', style: TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _pickVariationImage(index),
                                            icon: const Icon(Icons.add_a_photo),
                                            label: Text(_variations[index].imageFile != null 
                                                ? 'Change Image' 
                                                : 'Add Image'),
                                          ),
                                        ),
                                        if (_variations[index].imageFile != null) ...[
                                          const SizedBox(width: 8),
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _variations[index].imageFile = null;
                                              });
                                            },
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Price
                            TextFormField(
                              controller: _variationControllers[index]['price'],
                              decoration: const InputDecoration(
                                labelText: 'Price *',
                                border: OutlineInputBorder(),
                                prefixText: '₱ ',
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
