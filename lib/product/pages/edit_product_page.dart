import 'dart:typed_data';
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

/// A widget that displays an XFile image, working on both web and mobile platforms
class XFileImage extends StatelessWidget {
  final XFile file;
  final BoxFit fit;
  final double? width;
  final double? height;

  const XFileImage({
    Key? key,
    required this.file,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Icon(
              Icons.broken_image,
              color: AppColors.error,
              size: 48,
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: fit,
          width: width,
          height: height,
        );
      },
    );
  }
}

class EditProductPage extends StatefulWidget {
  final Product product;

  const EditProductPage({Key? key, required this.product}) : super(key: key);

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  final ProductFormModel _productForm = ProductFormModel();
  List<VariationFormModel> _variations = [];
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
  bool _hasUnsavedChanges = false;

  // Dynamic categories and subcategories
  List<Category> _categories = [];
  List<SubCategory> _subCategories = [];
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  String? _originalCategoryId; // Store original values from product
  String? _originalSubCategoryId;

  @override
  void initState() {
    super.initState();
    _populateFormWithProduct();
    _loadCategories();
    _setupChangeListeners();
  }

  void _setupChangeListeners() {
    _nameController.addListener(_markAsChanged);
    _descriptionController.addListener(_markAsChanged);
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

  // Populate the form with existing product data
  void _populateFormWithProduct() {
    final product = widget.product;

    // Set basic product info
    _nameController.text = product.name;
    _descriptionController.text = product.description;
    _productForm.name = product.name;
    _productForm.description = product.description;
    _productForm.imageURL = product.imageURL;
    _productForm.categoryId = product.categoryId;
    _productForm.subCategoryId = product.subCategoryId;
    _productForm.allowInquiry = product.allowInquiry;

    // Store the product's category and subcategory IDs but don't set them as selected yet
    // They will be set when the categories are loaded and validated
    _originalCategoryId = product.categoryId;
    _originalSubCategoryId = product.subCategoryId;

    // Populate variations
    if (product.variations != null && product.variations!.isNotEmpty) {
      _variations = product.variations!.map((variation) {
        final variationForm = VariationFormModel();
        variationForm.name = variation.name;
        variationForm.price = variation.price;
        variationForm.stock = variation.stock;
        variationForm.sku = variation.sku;
        variationForm.weight = variation.weight;
        variationForm.imageURL = variation.imageURL;
        variationForm.dimensions = variation.dimensions ?? {};
        variationForm.isFragile = variation.isFragile;
        return variationForm;
      }).toList();

      // Initialize controllers for existing variations
      _variationControllers.clear();
      for (int i = 0; i < _variations.length; i++) {
        final variation = _variations[i];
        _variationControllers.add({
          'name': TextEditingController(text: variation.name),
          'price': TextEditingController(text: variation.price.toString()),
          'stock': TextEditingController(text: variation.stock.toString()),
          'sku': TextEditingController(text: variation.sku),
          'weight': TextEditingController(
            text: variation.weight?.toString() ?? '',
          ),
          'length': TextEditingController(
            text: (variation.dimensions?['length']?.toString() ?? '0'),
          ),
          'width': TextEditingController(
            text: (variation.dimensions?['width']?.toString() ?? '0'),
          ),
          'height': TextEditingController(
            text: (variation.dimensions?['height']?.toString() ?? '0'),
          ),
        });
      }
    } else {
      // If no variations, create a default one
      _variations = [VariationFormModel()];
      _initializeVariationControllers();
    }
  }

  void _loadCategories() async {
    setState(() {
      _isCategoriesLoading = true;
    });

    try {
      final categories = await _categoryService.getCategories();
      //AppLogger.d('Loaded ${categories.length} categories');

      setState(() {
        _categories = categories;
        _isCategoriesLoading = false;

        // Validate and set the selected category from the original product data
        if (_originalCategoryId != null &&
            categories.any((cat) => cat.categoryId == _originalCategoryId)) {
          _selectedCategoryId = _originalCategoryId;
          _productForm.categoryId = _originalCategoryId!;
        } else {
          _selectedCategoryId = null;
          _productForm.categoryId = '';
          _selectedSubCategoryId = null;
          _productForm.subCategoryId = null;
        }
      });

      // Load subcategories for the selected category if we have one
      if (_selectedCategoryId != null) {
        _loadSubCategories(_selectedCategoryId!);
      }
    } catch (e) {
      //AppLogger.d('Error loading categories: $e');
      setState(() {
        _isCategoriesLoading = false;
        _errorMessage = 'Failed to load categories: $e';
      });
    }
  }

  void _loadSubCategories(String categoryId) async {
    //AppLogger.d('Loading subcategories for categoryId: $categoryId');

    try {
      final subCategories = await _categoryService.getSubCategories(categoryId);
      //AppLogger.d('Received ${subCategories.length} subcategories');

      setState(() {
        _subCategories = subCategories;
        // Validate and set the selected subcategory from the original product data
        if (_originalSubCategoryId != null &&
            subCategories.any(
              (sub) => sub.subCategoryId == _originalSubCategoryId,
            )) {
          _selectedSubCategoryId = _originalSubCategoryId;
          _productForm.subCategoryId = _originalSubCategoryId!;
        } else {
          _selectedSubCategoryId = null;
          _productForm.subCategoryId = null;
        }
      });
    } catch (e) {
      //AppLogger.d('Error loading subcategories: $e');
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
    for (var controllers in _variationControllers) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
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
      //AppLogger.d('Error picking product image: $e');
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
      //AppLogger.d('Error picking variation image: $e');
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
      //AppLogger.d('Error scanning barcode: $e');
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
      // Check if main product image is selected (either existing or new) only for published products
      if (_productForm.imageFile == null && _productForm.imageURL.isEmpty) {
        setState(() {
          _errorMessage = 'Please select a product image';
        });
        return;
      }
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
      String productId = widget.product.productId;

      // Handle image uploads for main product image
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

      // Handle variation images
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
          }
        }
      }

      final result = await _productService.updateProduct(
        productId,
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
              : (widget.product.isDraft && !isDraft) 
                  ? 'Product published successfully!'
                  : 'Product updated successfully!';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
            ),
          );
          // Reset unsaved changes flag before navigating
          _hasUnsavedChanges = false;
          // Navigate back to product detail
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to update product';
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
            'Edit Product',
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
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Edit Product',
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
                        color: AppColors.onSurface.withValues(alpha: 0.05),
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
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter product name';
                      }
                      return null;
                    },
                    onSaved: (value) {
                      _productForm.name = value!;
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
                        color: AppColors.onSurface.withValues(alpha: 0.05),
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
                        horizontal: 20,
                        vertical: 16,
                      ),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter product description';
                      }
                      return null;
                    },
                    onSaved: (value) {
                      _productForm.description = value!;
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
                        color: AppColors.onSurface.withValues(alpha: 0.05),
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
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: XFileImage(
                              file: _productForm.imageFile!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else if (_productForm.imageURL.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: NetworkImage(_productForm.imageURL),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.background,
                            border: Border.all(
                              color: AppColors.onSurface.withValues(alpha: 0.2),
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 48,
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to add image',
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
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _pickProductImage,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(
                              (_productForm.imageFile != null ||
                                      _productForm.imageURL.isNotEmpty)
                                  ? 'Change Image'
                                  : 'Add Image',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
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
                        color: AppColors.onSurface.withValues(alpha: 0.05),
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
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.onSurface,
                    ),
                    dropdownColor: AppColors.surface,
                    initialValue: _isCategoriesLoading
                        ? null
                        : (_categories.any(
                                (cat) => cat.categoryId == _selectedCategoryId,
                              )
                              ? _selectedCategoryId
                              : null),
                    items: _isCategoriesLoading
                        ? [
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Loading categories...',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ),
                          ]
                        : _categories
                              .where(
                                (category) => category.categoryId.isNotEmpty,
                              )
                              .fold<Map<String, DropdownMenuItem<String>>>({}, (
                                Map<String, DropdownMenuItem<String>> map,
                                category,
                              ) {
                                map[category.categoryId] =
                                    DropdownMenuItem<String>(
                                      value: category.categoryId,
                                      child: Text(category.categoryName),
                                    );
                                return map;
                              })
                              .values
                              .toList(),
                    onChanged: _isCategoriesLoading
                        ? null
                        : (value) {
                            //AppLogger.d('Category selected: $value');
                            setState(() {
                              _selectedCategoryId = value;
                              _productForm.categoryId = value ?? '';
                              _selectedSubCategoryId = null;
                              _productForm.subCategoryId = null;
                              _subCategories.clear();
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
                        color: AppColors.onSurface.withValues(alpha: 0.05),
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
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.onSurface,
                    ),
                    dropdownColor: AppColors.surface,
                    initialValue: _selectedCategoryId == null
                        ? null
                        : (_subCategories.any(
                                (sub) =>
                                    sub.subCategoryId == _selectedSubCategoryId,
                              )
                              ? _selectedSubCategoryId
                              : null),
                    items: _selectedCategoryId == null
                        ? [
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Select category first',
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
                        : _subCategories
                              .where(
                                (subCategory) =>
                                    subCategory.subCategoryId.isNotEmpty,
                              )
                              .fold<Map<String, DropdownMenuItem<String>>>({}, (
                                Map<String, DropdownMenuItem<String>> map,
                                subCategory,
                              ) {
                                map[subCategory.subCategoryId] =
                                    DropdownMenuItem<String>(
                                      value: subCategory.subCategoryId,
                                      child: Text(subCategory.subCategoryName),
                                    );
                                return map;
                              })
                              .values
                              .toList(),
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
                        'Add different variations of your product (size, color, model, etc.)',
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
                                        child: XFileImage(
                                          file: _variations[index].imageFile!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                  else if (_variations[index].imageURL !=
                                          null &&
                                      _variations[index].imageURL!.isNotEmpty)
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
                                        child: Image.network(
                                          _variations[index].imageURL!,
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
                                              (_variations[index].imageFile !=
                                                          null ||
                                                      (_variations[index]
                                                                  .imageURL !=
                                                              null &&
                                                          _variations[index]
                                                              .imageURL!
                                                              .isNotEmpty))
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
                                                null ||
                                            (_variations[index].imageURL !=
                                                    null &&
                                                _variations[index]
                                                    .imageURL!
                                                    .isNotEmpty)) ...[
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
                                                  _variations[index].imageURL =
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

                            // Price and Stock Row
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller:
                                        _variationControllers[index]['price'],
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Price *',
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
                                ),
                                const SizedBox(width: 16),
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

                            // Weight (Optional)
                            TextFormField(
                              controller:
                                  _variationControllers[index]['weight'],
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Weight (g) (Optional)',
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
                                      labelText: 'Length (cm)',
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller:
                                        _variationControllers[index]['width'],
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Width (cm)',
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller:
                                        _variationControllers[index]['height'],
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Height (cm)',
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
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: _addVariation,
                    icon: const Icon(Icons.add),
                    label: Text(
                      'Add Variation',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Button Row: Save as Draft and Update Product
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
                    // Update Product Button
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
                                  widget.product.isDraft ? 'Publish Product' : 'Update Product',
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
      )
    );
  }

  Widget _buildWebLayout() {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (bool didPop) async {
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
            'Edit Product',
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

                  // Product Inquiry Section (full width)
                  _buildWebInquirySection(),

                  const SizedBox(height: 40),

                  // Product Variations Section (full width)
                  _buildWebVariationsSection(),

                  const SizedBox(height: 40),

                  // Button Row: Save as Draft and Update Product
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
                      const SizedBox(width: 24),
                      // Update Product Button
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
                                    widget.product.isDraft ? 'Publish Product' : 'Update Product',
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
                ],
              ),
            ),
          ),
        ),
      ),
       ) // End of Scaffold
    ); // End of PopScope
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
                color:
                    (_productForm.imageFile != null ||
                        _productForm.imageURL.isNotEmpty)
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
                      child: XFileImage(
                        file: _productForm.imageFile!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : _productForm.imageURL.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        _productForm.imageURL,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Failed to load image',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          );
                        },
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
                (_productForm.imageFile != null ||
                        _productForm.imageURL.isNotEmpty)
                    ? Icons.edit
                    : Icons.add_a_photo,
                size: 20,
              ),
              label: Text(
                (_productForm.imageFile != null ||
                        _productForm.imageURL.isNotEmpty)
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
                    return 'ProductName is required';
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
                    return 'Description is required';
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
                        //AppLogger.d('Category selected: $value');
                        setState(() {
                          _selectedCategoryId = value;
                          _productForm.categoryId = value ?? '';
                          _selectedSubCategoryId = null;
                          _productForm.subCategoryId = null;
                          _subCategories.clear();
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
                  const SizedBox(height: 4),
                  Text(
                    'Add at least one variation with price, stock, and SKU',
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
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  tooltip: 'Remove Variation',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Variation Image
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            (_variations[index].imageFile != null ||
                                (_variations[index].imageURL?.isNotEmpty ??
                                    false))
                            ? Colors.transparent
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.onSurface.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: _variations[index].imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: XFileImage(
                                file: _variations[index].imageFile!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : (_variations[index].imageURL?.isNotEmpty ?? false)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.network(
                                _variations[index].imageURL!,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 32,
                                        color: AppColors.error,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Failed to load',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 40,
                                  color: AppColors.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Variation Image',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),

                    // Upload button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickVariationImage(index),
                        icon: Icon(
                          (_variations[index].imageFile != null ||
                                  (_variations[index].imageURL?.isNotEmpty ??
                                      false))
                              ? Icons.edit
                              : Icons.add_a_photo,
                          size: 16,
                        ),
                        label: Text(
                          (_variations[index].imageFile != null ||
                                  (_variations[index].imageURL?.isNotEmpty ??
                                      false))
                              ? 'Change'
                              : 'Add Image',
                          style: AppTextStyles.labelMedium,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right side - Form fields
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Row 1: Name + Price
                    Row(
                      children: [
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['name']!,
                            label: 'Variation Name *',
                            icon: Icons.label_outline,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Variation Name is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['price']!,
                            label: 'Price *',
                            icon: Icons.attach_money,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Price is required';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price < 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 2: Stock + SKU + Weight
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
                            icon: Icons.qr_code,
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
                            label: 'Weight (kg)',
                            icon: Icons.scale_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 3: Dimensions
                    Row(
                      children: [
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['length']!,
                            label: 'Length (cm)',
                            icon: Icons.straighten,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['width']!,
                            label: 'Width (cm)',
                            icon: Icons.straighten,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildWebTextField(
                            controller: controllers['height']!,
                            label: 'Height (cm)',
                            icon: Icons.height,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Fragile checkbox
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _variations[index].isFragile,
                            onChanged: (value) {
                              setState(() {
                                _variations[index].isFragile = value ?? false;
                                _markAsChanged();
                              });
                            },
                            activeColor: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.warning_amber_rounded,
                            color: _variations[index].isFragile 
                                ? AppColors.error 
                                : AppColors.onSurface.withValues(alpha: 0.5),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Fragile Item',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: _variations[index].isFragile 
                                  ? FontWeight.w600 
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mark if this item requires careful handling',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
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
