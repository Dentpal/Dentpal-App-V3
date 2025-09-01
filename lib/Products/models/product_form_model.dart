class ProductFormModel {
  String name = '';
  String description = '';
  String imageURL = '';
  String category = '';
  List<VariationFormModel> variations = [];
  
  // Validation
  String? validateName() {
    if (name.isEmpty) {
      return 'Name is required';
    }
    return null;
  }
  
  String? validateDescription() {
    if (description.isEmpty) {
      return 'Description is required';
    }
    return null;
  }
  
  String? validateImageURL() {
    if (imageURL.isEmpty) {
      return 'Image URL is required';
    } else if (!Uri.parse(imageURL).isAbsolute) {
      return 'Please enter a valid URL';
    }
    return null;
  }
  
  String? validateCategory() {
    if (category.isEmpty) {
      return 'Category is required';
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
  String? imageURL;
  double price = 0;
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
      return 'SKU is required';
    }
    return null;
  }
}
