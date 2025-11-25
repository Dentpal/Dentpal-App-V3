import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product_form_model.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/image_upload_service.dart';
import '../widgets/barcode_scanner_widget.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';

enum UnsavedChangesAction { saveAsDraft, discard }

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
  final _warrantyPolicyController = TextEditingController();
  final List<Map<String, TextEditingController>> _variationControllers = [];

  bool _isLoading = false;
  bool _isCategoriesLoading = true;
  String _errorMessage = '';
  bool _isSeller = false;
  String _sellerMessage = '';
  bool _hasUnsavedChanges = false;

  // Dynamic categories and subcategories
  List<Category> _categories = [];
  List<SubCategory> _subCategories = [];
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  String _selectedWarrantyPeriod = '';

  // Warranty options
  final List<String> _warrantyTypes = [
    'Local Manufacturer Warranty',
    'Local Supplier Warranty',
    'Local Supplier Refund Warranty',
    'International Manufacturer Warranty',
    'International Seller Warranty',
  ];
  
  final List<String> _warrantyPeriods = [
    '6 months',
    '1 year',
    '2 years',
    '3 years',
    '4 years',
    '5 years',
    'Lifetime warranty',
  ];

  @override
  void initState() {
    super.initState();
    _initializeVariationControllers();
    _checkSellerStatus();
    _loadCategories();
    _setupChangeListeners();
  }

  void _setupChangeListeners() {
    _nameController.addListener(_markAsChanged);
    _descriptionController.addListener(_markAsChanged);
    _warrantyPolicyController.addListener(_markAsChanged);
  }

  void _markAsChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  Future<UnsavedChangesAction?> _showUnsavedChangesDialog() async {
    return showDialog<UnsavedChangesAction>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Unsaved Changes',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'You have unsaved changes. What would you like to do?',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(UnsavedChangesAction.discard);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Discard',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop(UnsavedChangesAction.saveAsDraft);
                        await _submitForm(isDraft: true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Save Draft',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _loadCategories() async {
    setState(() {
      _isCategoriesLoading = true;
    });

    try {
      final categories = await _categoryService.getCategories();
      AppLogger.d('Loaded ${categories.length} categories');

      for (var cat in categories) {
        AppLogger.d(
          '  - Category: ${cat.categoryName} (ID: ${cat.categoryId})',
        );
      }

      setState(() {
        _categories = categories;
        _isCategoriesLoading = false;
      });
    } catch (e) {
      AppLogger.d('Error loading categories: $e');
      setState(() {
        _isCategoriesLoading = false;
        _errorMessage = 'Failed to load categories: $e';
      });
    }
  }

  void _loadSubCategories(String categoryId) async {
    AppLogger.d('Loading subcategories for categoryId: $categoryId');

    try {
      final subCategories = await _categoryService.getSubCategories(categoryId);
      AppLogger.d('Received ${subCategories.length} subcategories');

      for (var subCat in subCategories) {
        AppLogger.d(
          '  - SubCategory: ${subCat.subCategoryName} (ID: ${subCat.subCategoryId}, CategoryID: ${subCat.categoryId})',
        );
      }

      setState(() {
        _subCategories = subCategories;
        _selectedSubCategoryId = null; // Reset subcategory selection
        _productForm.subCategoryId = null;
      });
    } catch (e) {
      AppLogger.d('Error loading subcategories: $e');
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
    
    // Add listeners to variation controllers
    for (var controller in _variationControllers.last.values) {
      controller.addListener(_markAsChanged);
    }
  }

  @override
  void dispose() {
    // Dispose all controllers to prevent memory leaks
    _nameController.dispose();
    _descriptionController.dispose();
    _warrantyPolicyController.dispose();
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
      
      // Add listeners to new variation controllers
      for (var controller in _variationControllers.last.values) {
        controller.addListener(_markAsChanged);
      }
      
      _markAsChanged(); // Adding a variation counts as a change
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
        _markAsChanged(); // Removing a variation counts as a change
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least one variation')),
      );
    }
  }

  // Pick main product image with square cropping
  Future<void> _pickProductImage() async {
    try {
      final screenWidth = MediaQuery.of(context).size.width;
      final isWebView = screenWidth > 1024;

      ImageSource? source;
      if (isWebView) {
        // For web view, automatically use gallery/file picker
        source = ImageSource.gallery;
      } else {
        // For mobile, show the source selection dialog
        source = await _imageUploadService.showImageSourceDialog(context);
        if (source == null) return;
      }

      final pickedFile = await _imageUploadService.pickAndCropImage(
        source: source,
      );
      if (pickedFile != null) {
        setState(() {
          _productForm.imageFile = pickedFile;
          _markAsChanged(); // Image selection counts as a change
        });
      }
    } catch (e) {
      AppLogger.d('Error picking product image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to pick image. Please try again.'),
                ),
              ],
            ),
            backgroundColor: AppColors.error.withValues(alpha: 0.1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  // Pick variation image with square cropping
  Future<void> _pickVariationImage(int index) async {
    try {
      final screenWidth = MediaQuery.of(context).size.width;
      final isWebView = screenWidth > 1024;

      ImageSource? source;
      if (isWebView) {
        // For web view, automatically use gallery/file picker
        source = ImageSource.gallery;
      } else {
        // For mobile, show the source selection dialog
        source = await _imageUploadService.showImageSourceDialog(context);
        if (source == null) return;
      }

      final pickedFile = await _imageUploadService.pickAndCropImage(
        source: source,
      );
      if (pickedFile != null) {
        setState(() {
          _variations[index].imageFile = pickedFile;
          _markAsChanged(); // Variation image selection counts as a change
        });
      }
    } catch (e) {
      AppLogger.d('Error picking variation image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to pick image. Please try again.'),
                ),
              ],
            ),
            backgroundColor: AppColors.error.withValues(alpha: 0.1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  // Show barcode scanner for SKU
  Future<void> _scanBarcode(int index) async {
    try {
      final scannedCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()),
      );

      if (scannedCode != null && scannedCode.isNotEmpty) {
        setState(() {
          _variationControllers[index]['sku']!.text = scannedCode;
        });
      }
    } catch (e) {
      AppLogger.d('Error scanning barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: AppColors.error),
                const SizedBox(width: 8),
                const Text('Failed to scan barcode'),
              ],
            ),
            backgroundColor: AppColors.error.withValues(alpha: 0.1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Future<void> _submitForm({bool isDraft = false}) async {
    if (!isDraft && !_formKey.currentState!.validate()) {
      return;
    }

    // For drafts, we allow saving without validation
    if (!isDraft) {
      // Check if main product image is selected only for published products
      if (_productForm.imageFile == null) {
        setState(() {
          _errorMessage = 'Please select a product image';
        });
        return;
      }

      // Validate that each variation has an image
      for (int i = 0; i < _variations.length; i++) {
        if (_variations[i].imageFile == null) {
          setState(() {
            _errorMessage = 'Please select an image for variation ${i + 1}';
          });
          return;
        }
      }
    }

    // Save all form fields
    _formKey.currentState!.save();

    // Manually transfer values from controllers to models
    _productForm.name = _nameController.text;
    _productForm.description = _descriptionController.text;
    _productForm.hasWarranty = _productForm.hasWarranty;
    _productForm.warrantyPolicy = _warrantyPolicyController.text;

    // Set variation values from controllers
    for (int i = 0; i < _variations.length; i++) {
      final controllers = _variationControllers[i];
      _variations[i].name = controllers['name']!.text;
      _variations[i].price = double.tryParse(controllers['price']!.text) ?? 0; // Price already includes VAT
      _variations[i].stock = int.tryParse(controllers['stock']!.text) ?? 0;
      _variations[i].sku = controllers['sku']!.text;
      _variations[i].weight = controllers['weight']!.text.isNotEmpty
          ? double.tryParse(controllers['weight']!.text)
          : null;

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
        final productImageBytes = await _imageUploadService.resizeImage(
          _productForm.imageFile!,
          forceSquare: true,
        );
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
          final variationImageBytes = await _imageUploadService.resizeImage(
            _variations[i].imageFile!,
            forceSquare: true,
          );
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

      final result = await _productService.addProduct(
        _productForm,
        _variations,
        isDraft: isDraft,
      );

      setState(() {
        _isLoading = false;
      });

      if (result['success']) {
        if (mounted) {
          final message = isDraft 
              ? 'Product saved as draft successfully!' 
              : 'Product added successfully!';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          // Reset unsaved changes flag before navigating
          _hasUnsavedChanges = false;
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Add Product',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (!_isSeller) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Add Product',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Seller Access Required',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _sellerMessage,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Go Back',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWebView = screenWidth > 1024;

    if (isWebView) {
      return _buildWebLayout();
    }

    return _buildMobileLayout();
  }

  Widget _buildMobileLayout() {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (bool didPop, result) async {
        if (!didPop && _hasUnsavedChanges) {
          final action = await _showUnsavedChangesDialog();
          if (action == UnsavedChangesAction.discard && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(
              'Add Product',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
              onPressed: () async {
                if (_hasUnsavedChanges) {
                  final action = await _showUnsavedChangesDialog();
                  if (action == UnsavedChangesAction.discard && mounted) {
                    Navigator.of(context).pop();
                  }
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20.0),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Product Name
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _nameController,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Product Name *',
                        labelStyle: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Product Name is required';
                        }
                        if (value.length < 10) {
                          return 'Product name must be at least 10 characters long';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Product Description
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _descriptionController,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Description *',
                        labelStyle: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
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
                  ),
                  const SizedBox(height: 20),

                  // Product Image
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(
                                left: 20,
                                top: 20,
                                bottom: 8,
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: AppColors.primary,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  top: 20,
                                  right: 20,
                                  bottom: 8,
                                ),
                                child: Text(
                                  'Product Image *',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_productForm.imageFile != null)
                          Container(
                            height: 250,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppColors.surfaceVariant,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _productForm.imageFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 150,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                width: 2,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 48,
                                    color: AppColors.primary.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No image selected',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _pickProductImage,
                                  icon: const Icon(Icons.add_a_photo),
                                  label: Text(
                                    _productForm.imageFile != null
                                        ? 'Change Image'
                                        : 'Add Image',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _productForm.imageFile != null
                                        ? AppColors.secondary
                                        : AppColors.primary,
                                    foregroundColor: AppColors.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              if (_productForm.imageFile != null) ...[
                                const SizedBox(width: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _productForm.imageFile = null;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Category
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        labelStyle: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                        prefixIcon: const Icon(
                          Icons.category,
                          color: AppColors.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.onSurface,
                      ),
                      dropdownColor: AppColors.surface,
                      initialValue: _selectedCategoryId,
                      items: _isCategoriesLoading
                          ? [
                              DropdownMenuItem(
                                value: null,
                                child: Text(
                                  'Loading...',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          : _categories.map((category) {
                              return DropdownMenuItem(
                                value: category.categoryId,
                                child: Text(
                                  category.categoryName,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                      onChanged: _isCategoriesLoading
                          ? null
                          : (value) {
                              AppLogger.d('Category selected: $value');
                              setState(() {
                                _selectedCategoryId = value;
                                _productForm.categoryId = value ?? '';
                                _markAsChanged(); // Category selection counts as a change
                              });
                              if (value != null) {
                                _loadSubCategories(value);
                              }
                            },
                      validator: (_) => _productForm.validateCategory(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // SubCategory
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'SubCategory *',
                        labelStyle: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.7),
                        ),
                        prefixIcon: const Icon(
                          Icons.subdirectory_arrow_right,
                          color: AppColors.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.onSurface,
                      ),
                      dropdownColor: AppColors.surface,
                      initialValue: _selectedSubCategoryId,
                      items: _selectedCategoryId == null
                          ? [
                              DropdownMenuItem(
                                value: null,
                                child: Text(
                                  'Select a category first',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          : _subCategories.isEmpty
                          ? [
                              DropdownMenuItem(
                                value: null,
                                child: Text(
                                  'No subcategories available',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ]
                          : _subCategories.map((subCategory) {
                              return DropdownMenuItem(
                                value: subCategory.subCategoryId,
                                child: Text(
                                  subCategory.subCategoryName,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                      onChanged: _selectedCategoryId == null
                          ? null
                          : (value) {
                              setState(() {
                                _selectedSubCategoryId = value;
                                _productForm.subCategoryId = value;
                                _markAsChanged(); // Subcategory selection counts as a change
                              });
                            },
                      validator: (_) => _productForm.validateSubCategory(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Warranty Section
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Product Warranty',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Warranty checkbox
                          Row(
                            children: [
                              Checkbox(
                                value: _productForm.hasWarranty,
                                onChanged: (value) {
                                  setState(() {
                                    _productForm.hasWarranty = value ?? false;
                                    if (!_productForm.hasWarranty) {
                                      _warrantyPolicyController.clear();
                                      _productForm.warrantyPolicy = '';
                                      _productForm.warrantyType = '';
                                      _productForm.warrantyPeriod = '';
                                      _selectedWarrantyPeriod = '';
                                    }
                                    _markAsChanged(); // Warranty checkbox change counts as a change
                                  });
                                },
                                activeColor: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This product includes warranty',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          // Warranty fields (shown only if warranty is enabled)
                          if (_productForm.hasWarranty) ...[
                            const SizedBox(height: 16),
                            
                            // Warranty Type dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _productForm.warrantyType.isEmpty ? null : _productForm.warrantyType,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Warranty Type *',
                                labelStyle: AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.7),
                                ),
                                prefixIcon: Icon(Icons.category_outlined, color: AppColors.primary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                              isExpanded: true,
                              items: _warrantyTypes.map((type) {
                                return DropdownMenuItem<String>(
                                  value: type,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      type,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _productForm.warrantyType = value ?? '';
                                  _markAsChanged(); // Warranty type change counts as a change
                                });
                              },
                              validator: (value) {
                                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                                  return 'Warranty type is required';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Warranty Period section
                            DropdownButtonFormField<String>(
                              initialValue: _selectedWarrantyPeriod.isEmpty ? null : _selectedWarrantyPeriod,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Warranty Period *',
                                labelStyle: AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.7),
                                ),
                                prefixIcon: Icon(Icons.schedule_outlined, color: AppColors.primary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                              isExpanded: true,
                              items: _warrantyPeriods.map((period) {
                                return DropdownMenuItem<String>(
                                  value: period,
                                  child: Text(
                                    period,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedWarrantyPeriod = value ?? '';
                                  _markAsChanged(); // Warranty period change counts as a change
                                });
                              },
                              validator: (value) {
                                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                                  return 'Warranty period is required';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Warranty policy text field
                            TextFormField(
                              controller: _warrantyPolicyController,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Warranty Policy *',
                                labelStyle: AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.7),
                                ),
                                hintText: 'Describe the warranty terms and conditions',
                                hintStyle: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.5),
                                ),
                                prefixIcon: Icon(Icons.policy_outlined, color: AppColors.primary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.error,
                                    width: 1,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: 4,
                              validator: (value) {
                                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                                  return 'Warranty policy is required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Product Inquiry Section
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.question_answer_outlined,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Product Inquiry',
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Checkbox(
                                value: _productForm.allowInquiry,
                                onChanged: (value) {
                                  setState(() {
                                    _productForm.allowInquiry = value ?? false;
                                    _markAsChanged();
                                  });
                                },
                                activeColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Allow customers to send inquiries about this product?',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Variations',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add at least one variation with price, stock, and SKU. Prices entered already include VAT.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Variations
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _variations.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Variation ${index + 1}',
                                      style: AppTextStyles.labelLarge.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () => _removeVariation(index),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Variation Name
                              TextFormField(
                                controller: _variationControllers[index]['name'],
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.onSurface,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Variation Name *',
                                  labelStyle: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  hintText: 'e.g., Small, Blue, Standard',
                                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.grey300,
                                      width: 1,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.grey300,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.error,
                                      width: 1,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Variation name is required';
                                  }
                                  if (value.length < 10) {
                                    return 'Variation name must be at least 10 characters long';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Variation Image (Optional)
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.grey300,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Text(
                                        'Variation Image (Optional)',
                                        style: AppTextStyles.labelLarge.copyWith(
                                          color: AppColors.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (_variations[index].imageFile != null)
                                      Container(
                                        height: 250,
                                        width: double.infinity,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          color: AppColors.surface,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            _variations[index].imageFile!,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        height: 80,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.image,
                                                size: 32,
                                                color: AppColors.onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                              Text(
                                                'No image',
                                                style: AppTextStyles.bodySmall
                                                    .copyWith(
                                                      color: AppColors.onSurface
                                                          .withValues(alpha: 0.5),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _pickVariationImage(index),
                                              icon: const Icon(Icons.add_a_photo),
                                              label: Text(
                                                _variations[index].imageFile !=
                                                        null
                                                    ? 'Change Image'
                                                    : 'Add Image',
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.primary,
                                                side: BorderSide(
                                                  color: AppColors.primary,
                                                  width: 1.5,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          if (_variations[index].imageFile !=
                                              null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.error.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: IconButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _variations[index].imageFile =
                                                        null;
                                                  });
                                                },
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: AppColors.error,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Price Section (full width)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller:
                                        _variationControllers[index]['price'],
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Price (including VAT) *',
                                      labelStyle: AppTextStyles.labelLarge
                                          .copyWith(
                                            color: AppColors.onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                      prefixText: '₱ ',
                                      prefixStyle: AppTextStyles.bodyLarge
                                          .copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Roboto',
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: AppColors.grey300,
                                          width: 1,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: AppColors.grey300,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: AppColors.primary,
                                          width: 2,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: AppColors.error,
                                          width: 1,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      setState(() {}); // Trigger rebuild
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Price is required';
                                      }
                                      final price = double.tryParse(value);
                                      if (price == null) {
                                        return 'Please enter a valid number';
                                      }
                                      if (price < 1) {
                                        return 'Price must be at least ₱1';
                                      }
                                      return null;
                                    },
                                  ),

                                ],
                              ),
                              const SizedBox(height: 20),

                              // Stock Row
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _variationControllers[index]['stock'],
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Stock *',
                                        labelStyle: AppTextStyles.labelLarge
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 2,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.error,
                                            width: 1,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
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
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // SKU with Barcode Scanner
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _variationControllers[index]['sku'],
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'SKU *',
                                        labelStyle: AppTextStyles.labelLarge
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                        hintText: 'Unique product identifier',
                                        hintStyle: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 2,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.error,
                                            width: 1,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Product SKU is required';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: IconButton(
                                      onPressed: () => _scanBarcode(index),
                                      icon: const Icon(
                                        Icons.qr_code_scanner,
                                        color: AppColors.primary,
                                      ),
                                      tooltip: 'Scan Barcode',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Weight
                              TextFormField(
                                controller:
                                    _variationControllers[index]['weight'],
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.onSurface,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Weight (g) *',
                                  labelStyle: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.grey300,
                                      width: 1,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.grey300,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: AppColors.error,
                                      width: 1,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Weight is required';
                                  }
                                  final weight = double.tryParse(value);
                                  if (weight == null) {
                                    return 'Please enter a valid number';
                                  }
                                  if (weight <= 0) {
                                    return 'Weight must be greater than 0';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Dimensions
                              Text(
                                'Dimensions (Optional)',
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Dimensions fields
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _variationControllers[index]['length'],
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Length (cm) *',
                                        labelStyle: AppTextStyles.labelMedium
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Length is required';
                                        }
                                        final length = double.tryParse(value);
                                        if (length == null) {
                                          return 'Invalid number';
                                        }
                                        if (length <= 0) {
                                          return 'Must be > 0';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _variationControllers[index]['width'],
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Width (cm) *',
                                        labelStyle: AppTextStyles.labelMedium
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Width is required';
                                        }
                                        final width = double.tryParse(value);
                                        if (width == null) {
                                          return 'Invalid number';
                                        }
                                        if (width <= 0) {
                                          return 'Must be > 0';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _variationControllers[index]['height'],
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Height (cm) *',
                                        labelStyle: AppTextStyles.labelMedium
                                            .copyWith(
                                              color: AppColors.onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.grey300,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Height is required';
                                        }
                                        final height = double.tryParse(value);
                                        if (height == null) {
                                          return 'Invalid number';
                                        }
                                        if (height <= 0) {
                                          return 'Must be > 0';
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
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addVariation,
                      icon: const Icon(Icons.add),
                      label: Text(
                        'Add Variation',
                        style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Button Row: Save as Draft and Add Product
                  Row(
                    children: [
                      // Save as Draft Button
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _submitForm(isDraft: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: AppColors.primary,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Save as Draft',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Add Product Button
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: _isLoading ? null : AppColors.primaryGradient,
                            color: _isLoading ? AppColors.grey300 : null,
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _submitForm(isDraft: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: AppColors.onPrimary,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Add Product',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      )
    );
  }

  Widget _buildWebLayout() {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (bool didPop, result) async {
        if (!didPop && _hasUnsavedChanges) {
          final action = await _showUnsavedChangesDialog();
          if (action == UnsavedChangesAction.discard && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Add Product',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () async {
              if (_hasUnsavedChanges) {
                final action = await _showUnsavedChangesDialog();
                if (action == UnsavedChangesAction.discard && mounted) {
                  Navigator.of(context).pop();
                }
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error message if any
                  if (_errorMessage.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 32.0),
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 24,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Main content in two columns
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left column - Product Image
                        Expanded(
                          flex: 2,
                          child: _buildWebProductImageSection(),
                        ),
                        const SizedBox(width: 32),
                        // Right column - Product Information and Categories
                        Expanded(
                          flex: 3,
                          child: _buildWebProductInfoAndCategoriesSection(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Warranty Section (full width)
                  _buildWebWarrantySection(),

                  const SizedBox(height: 40),

                  // Product Inquiry Section (full width)
                  _buildWebInquirySection(),

                  const SizedBox(height: 40),

                  // Product Variations Section (full width)
                  _buildWebVariationsSection(),

                  const SizedBox(height: 40),

                  // Button Row: Save as Draft and Add Product
                  Row(
                    children: [
                      // Save as Draft Button  
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _submitForm(isDraft: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: AppColors.primary,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Save as Draft',
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Add Product Button
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: _isLoading ? null : AppColors.primaryGradient,
                            color: _isLoading ? AppColors.grey300 : null,
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () => _submitForm(isDraft: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: AppColors.onPrimary,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 28,
                                    width: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Add Product',
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
      )
    );
  }

  Widget _buildWebProductImageSection() {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Product Image *',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Image Preview or Placeholder - Expanded to fill available space
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _productForm.imageFile != null
                    ? Colors.transparent
                    : AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.onSurface.withValues(alpha: 0.2),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: _productForm.imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        _productForm.imageFile!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 64,
                          color: AppColors.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Click to browse files',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Upload Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickProductImage,
              icon: Icon(
                _productForm.imageFile != null ? Icons.edit : Icons.add_a_photo,
                size: 20,
              ),
              label: Text(
                _productForm.imageFile != null
                    ? 'Change Image'
                    : 'Browse Files',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebProductInfoAndCategoriesSection() {
    return Column(
      children: [
        // Product Information Section
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Product Information',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 24),

              // Product Name
              _buildWebTextField(
                controller: _nameController,
                label: 'Product Name *',
                icon: Icons.shopping_bag_outlined,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Product Name is required';
                  }
                  if (value.length < 10) {
                    return 'Product name must be at least 10 characters long';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Product Description
              _buildWebTextField(
                controller: _descriptionController,
                label: 'Description *',
                icon: Icons.description_outlined,
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Product Description is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Categories Section
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Categories',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 20),

              // Category Dropdown
              _buildWebDropdown(
                label: 'Category *',
                icon: Icons.category_outlined,
                value: _selectedCategoryId,
                items: _isCategoriesLoading
                    ? [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Loading categories...',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ]
                    : _categories.map((category) {
                        return DropdownMenuItem(
                          value: category.categoryId,
                          child: Text(
                            category.categoryName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                onChanged: _isCategoriesLoading
                    ? null
                    : (String? value) {
                        AppLogger.d('Category selected: $value');
                        setState(() {
                          _selectedCategoryId = value;
                          _productForm.categoryId = value ?? '';
                          _markAsChanged(); // Category selection counts as a change
                        });
                        if (value != null) {
                          _loadSubCategories(value);
                        }
                      },
                validator: (_) => _productForm.validateCategory(),
              ),

              const SizedBox(height: 20),

              // SubCategory Dropdown
              _buildWebDropdown(
                label: 'SubCategory *',
                icon: Icons.subdirectory_arrow_right_outlined,
                value: _selectedSubCategoryId,
                items: _selectedCategoryId == null
                    ? [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Select category first',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ]
                    : _subCategories.isEmpty
                    ? [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'No subcategories available',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ]
                    : _subCategories.map((subCategory) {
                        return DropdownMenuItem(
                          value: subCategory.subCategoryId,
                          child: Text(
                            subCategory.subCategoryName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                onChanged: _selectedCategoryId == null
                    ? null
                    : (String? value) {
                        setState(() {
                          _selectedSubCategoryId = value;
                          _productForm.subCategoryId = value;
                          _markAsChanged(); // Subcategory selection counts as a change
                        });
                      },
                validator: (_) => _productForm.validateSubCategory(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: controller,
        style: AppTextStyles.bodyLarge.copyWith(color: AppColors.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.labelLarge.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        maxLines: maxLines,
        validator: validator,
      ),
    );
  }

  Widget _buildWebDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?)? onChanged,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.labelLarge.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        style: AppTextStyles.bodyLarge.copyWith(color: AppColors.onSurface),
        dropdownColor: AppColors.surface,
        initialValue: value,
        items: items,
        onChanged: onChanged,
        validator: validator,
      ),
    );
  }

  Widget _buildWebVariationsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Product Variations',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add at least one variation with price, stock, and SKU. Final prices include 12% VAT.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _addVariation,
                icon: const Icon(Icons.add, size: 20),
                label: Text(
                  'Add Variation',
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.surface,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Variations Grid
          ...List.generate(_variations.length, (index) {
            return _buildWebVariationCard(index);
          }),
        ],
      ),
    );
  }

  Widget _buildWebVariationCard(int index) {
    final controllers = _variationControllers[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with variation title and remove button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Variation ${index + 1}',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              if (_variations.length > 1)
                IconButton(
                  onPressed: () => _removeVariation(index),
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.error,
                  tooltip: 'Remove Variation',
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Variation fields in grid layout
          Row(
            children: [
              // Left side - Image and basic info
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Variation Image - Larger container for better visual appeal
                    Container(
                      width: double.infinity,
                      height: 280, // Increased from 150 to 280
                      decoration: BoxDecoration(
                        color: _variations[index].imageFile != null
                            ? Colors.transparent
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(16), // Increased border radius
                        border: Border.all(
                          color: AppColors.onSurface.withValues(alpha: 0.2),
                          width: 2, // Slightly thicker border
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: _variations[index].imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                _variations[index].imageFile!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 64, // Increased from 32 to 64
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 16), // Increased spacing
                                Text(
                                  'Variation Image',
                                  style: AppTextStyles.titleMedium.copyWith( // Changed from bodySmall to titleMedium
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Optional',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20), // Increased spacing
                    
                    // Upload/Change Button - Enhanced styling
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon( // Changed from OutlinedButton to ElevatedButton
                        onPressed: () => _pickVariationImage(index),
                        icon: Icon(
                          _variations[index].imageFile != null
                              ? Icons.edit_outlined
                              : Icons.add_photo_alternate_outlined,
                          size: 20, // Increased icon size
                        ),
                        label: Text(
                          _variations[index].imageFile != null
                              ? 'Change Image'
                              : 'Add Image',
                          style: AppTextStyles.labelLarge.copyWith( // Changed from labelMedium to labelLarge
                            fontWeight: FontWeight.w600,
                            color: AppColors.onPrimary, // Explicitly set the color
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _variations[index].imageFile != null
                              ? AppColors.secondary
                              : AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 2,
                          shadowColor: AppColors.primary.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12), // Increased border radius
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16), // Increased padding
                        ),
                      ),
                    ),
                    
                    // Optional: Remove image button when image is present
                    if (_variations[index].imageFile != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _variations[index].imageFile = null;
                            });
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                          ),
                          label: Text(
                            'Remove Image',
                            style: AppTextStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right side - Form fields
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // First row - Variation Name (full width)
                    _buildWebTextField(
                      controller: controllers['name']!,
                      label: 'Variation Name *',
                      icon: Icons.label_outline,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Variation name is required';
                        }
                        if (value.length < 10) {
                          return 'Variation name must be at least 10 characters long';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Second row - Price (full width)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
                          ),
                          child: TextFormField(
                            controller: controllers['price']!,
                            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Price (including VAT) *',
                              labelStyle: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.7),
                              ),
                              prefixIcon: Icon(Icons.money_rounded, color: AppColors.primary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {}); // Trigger rebuild
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Price is required';
                              }
                              final price = double.tryParse(value);
                              if (price == null) {
                                return 'Please enter a valid number';
                              }
                              if (price < 1) {
                                return 'Price must be at least ₱1';
                              }
                              return null;
                            },
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 16),

                    // Third row - Stock, SKU and Weight
                    Row(
                      children: [
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['stock']!,
                            label: 'Stock *',
                            icon: Icons.inventory_2_outlined,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Stock is required';
                              }
                              final stock = int.tryParse(value);
                              if (stock == null || stock < 0) {
                                return 'Enter a valid stock number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['sku']!,
                            label: 'SKU *',
                            icon: Icons.qr_code_outlined,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Product SKU is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['weight']!,
                            label: 'Weight (g) *',
                            icon: Icons.scale_outlined,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Weight is required';
                              }
                              final weight = double.tryParse(value);
                              if (weight == null) {
                                return 'Please enter a valid number';
                              }
                              if (weight <= 0) {
                                return 'Weight must be greater than 0';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Fourth row - Dimensions only
                    Row(
                      children: [
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['length']!,
                            label: 'Length (cm) *',
                            icon: Icons.straighten,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Length is required';
                              }
                              final length = double.tryParse(value);
                              if (length == null) {
                                return 'Invalid number';
                              }
                              if (length <= 0) {
                                return 'Must be > 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['width']!,
                            label: 'Width (cm) *',
                            icon: Icons.straighten,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Width is required';
                              }
                              final width = double.tryParse(value);
                              if (width == null) {
                                return 'Invalid number';
                              }
                              if (width <= 0) {
                                return 'Must be > 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['height']!,
                            label: 'Height (cm) *',
                            icon: Icons.straighten,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Height is required';
                              }
                              final height = double.tryParse(value);
                              if (height == null) {
                                return 'Invalid number';
                              }
                              if (height <= 0) {
                                return 'Must be > 0';
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebWarrantySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Product Warranty',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Warranty checkbox
          Row(
            children: [
              Checkbox(
                value: _productForm.hasWarranty,
                onChanged: (value) {
                  setState(() {
                    _productForm.hasWarranty = value ?? false;
                    if (!_productForm.hasWarranty) {
                      _warrantyPolicyController.clear();
                      _productForm.warrantyPolicy = '';
                      _productForm.warrantyType = '';
                      _productForm.warrantyPeriod = '';
                    }
                    _markAsChanged(); // Warranty checkbox change counts as a change
                  });
                },
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'This product includes warranty',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),

          // Warranty fields (shown only if warranty is enabled)
          if (_productForm.hasWarranty) ...[
            const SizedBox(height: 24),
            
            // Warranty Type dropdown
            _buildWebDropdown(
              label: 'Warranty Type *',
              icon: Icons.category_outlined,
              value: _productForm.warrantyType.isEmpty ? null : _productForm.warrantyType,
              items: _warrantyTypes.map((type) {
                return DropdownMenuItem<String>(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _productForm.warrantyType = value ?? '';
                  _markAsChanged(); // Warranty type change counts as a change
                });
              },
              validator: (value) {
                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                  return 'Warranty type is required when warranty is enabled';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Warranty Period dropdown
            _buildWebDropdown(
              label: 'Warranty Period *',
              icon: Icons.schedule_outlined,
              value: _productForm.warrantyPeriod.isEmpty ? null : _productForm.warrantyPeriod,
              items: _warrantyPeriods.map((period) {
                return DropdownMenuItem<String>(
                  value: period,
                  child: Text(period),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _productForm.warrantyPeriod = value ?? '';
                  _markAsChanged(); // Warranty period change counts as a change
                });
              },
              validator: (value) {
                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                  return 'Warranty period is required when warranty is enabled';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Warranty policy text field
            _buildWebTextField(
              controller: _warrantyPolicyController,
              label: 'Warranty Policy *',
              icon: Icons.policy_outlined,
              maxLines: 4,
              validator: (value) {
                if (_productForm.hasWarranty && (value == null || value.isEmpty)) {
                  return 'Warranty policy is required';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebInquirySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.question_answer_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Product Inquiry',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Checkbox(
                value: _productForm.allowInquiry,
                onChanged: (value) {
                  setState(() {
                    _productForm.allowInquiry = value ?? false;
                    _markAsChanged();
                  });
                },
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Allow customers to send inquiries about this product?',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
