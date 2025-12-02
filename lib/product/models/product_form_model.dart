import 'package:image_picker/image_picker.dart';

class ProductFormModel {
  String name = '';
  String description = '';
  String imageURL = '';
  XFile? imageFile;
  String categoryId = '';
  String? subCategoryId = '';
  List<VariationFormModel> variations = [];
  
  // Warranty fields
  bool hasWarranty = false;
  String warrantyType = '';
  String warrantyPeriod = '';
  String warrantyPolicy = '';
  
  // Inquiry field
  bool allowInquiry = false;
  
  // Validation
  String? validateName() {
    if (name.isEmpty) {
      return 'Product Name is required';
    }
    return null;
  }
  
  String? validateDescription() {
    if (description.isEmpty) {
      return 'Product Description is required';
    }
    return null;
  }
  
  String? validateImageURL() {
    if (imageFile == null && imageURL.isEmpty) {
      return 'Product image is required';
    }
    return null;
  }
  
  String? validateCategory() {
    if (categoryId.isEmpty) {
      return 'Category is required';
    }
    return null;
  }
  
  String? validateSubCategory() {
    if (subCategoryId == null || subCategoryId!.isEmpty) {
      return 'Sub Category is required';
    }
    return null;
  }
  
  String? validateWarrantyType() {
    if (hasWarranty && warrantyType.isEmpty) {
      return 'Warranty type is required when warranty is enabled';
    }
    return null;
  }
  
  String? validateWarrantyPeriod() {
    if (hasWarranty && warrantyPeriod.isEmpty) {
      return 'Warranty period is required when warranty is enabled';
    }
    return null;
  }
  
  String? validateWarrantyPolicy() {
    if (hasWarranty && warrantyPolicy.isEmpty) {
      return 'Warranty policy is required';
    }
    return null;
  }
  
  bool validateVariations() {
    if (variations.isEmpty) {
      return false;
    }
    
    for (var variation in variations) {
      if (variation.price <= 0 || variation.stock < 0 || variation.sku.isEmpty) {
        return false;
      }
    }
    
    return true;
  }
}

class VariationFormModel {
  String name = '';
  String? imageURL;
  XFile? imageFile;
  double price = 0; // Price already includes VAT
  int stock = 0;
  String sku = '';
  double? weight;
  Map<String, dynamic>? dimensions = {
    'length': 0.0,
    'width': 0.0,
    'height': 0.0,
  };
  
  // Validation
  String? validatePrice() {
    if (price <= 0) {
      return 'Price must be greater than 0';
    }
    return null;
  }
  
  String? validateStock() {
    if (stock < 0) {
      return 'Stock cannot be negative';
    }
    return null;
  }
  
  String? validateSKU() {
    if (sku.isEmpty) {
      return 'Product SKU is required';
    }
    return null;
  }
  
  String? validateName() {
    if (name.isEmpty) {
      return 'Variation name is required';
    }
    return null;
  }
}
