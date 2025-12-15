import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import 'package:dentpal/utils/app_logger.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache for categories
  static List<Category>? _cachedCategories;
  static DateTime? _categoriesCacheTimestamp;
  static const Duration _cacheDuration = Duration(hours: 1);
  
  // Cache for subcategories
  static Map<String, List<SubCategory>> _cachedSubCategories = {};
  static Map<String, DateTime> _subCategoriesCacheTimestamp = {};

  // Get all categories with caching
  Future<List<Category>> getCategories() async {
    try {
      // Check if cache is valid
      if (_cachedCategories != null && 
          _categoriesCacheTimestamp != null &&
          DateTime.now().difference(_categoriesCacheTimestamp!) < _cacheDuration) {
        //AppLogger.d('Using cached categories (${_cachedCategories!.length} items)');
        return _cachedCategories!;
      }
      
      //AppLogger.d('Fetching categories from Firestore...');
      
      QuerySnapshot querySnapshot = await _firestore
          .collection('Category')
          .orderBy('categoryName')
          .get();
      
      List<Category> categories = querySnapshot.docs
          .map((doc) => Category.fromFirestore(doc))
          .toList();
      
      // Update cache
      _cachedCategories = categories;
      _categoriesCacheTimestamp = DateTime.now();
      
      //AppLogger.d('Fetched and cached ${categories.length} categories');
      return categories;
    } catch (e) {
      //AppLogger.d('Error fetching categories: $e');
      // Return cached data if available, even if expired
      return _cachedCategories ?? [];
    }
  }

  // Get subcategories for a specific category with caching
  Future<List<SubCategory>> getSubCategories(String categoryId) async {
    try {
      // Check if cache is valid for this category
      if (_cachedSubCategories.containsKey(categoryId) && 
          _subCategoriesCacheTimestamp.containsKey(categoryId) &&
          DateTime.now().difference(_subCategoriesCacheTimestamp[categoryId]!) < _cacheDuration) {
        //AppLogger.d('Using cached subcategories for $categoryId (${_cachedSubCategories[categoryId]!.length} items)');
        return _cachedSubCategories[categoryId]!;
      }
      
      //AppLogger.d('Fetching subcategories for category: $categoryId');
      
      QuerySnapshot querySnapshot = await _firestore
          .collection('Category')
          .doc(categoryId)
          .collection('subCategory')  // Changed from 'SubCategory' to 'subCategory'
          .orderBy('subCategoryName')
          .get();
      
      List<SubCategory> subCategories = querySnapshot.docs
          .map((doc) => SubCategory.fromFirestore(doc))
          .toList();
      
      // Update cache
      _cachedSubCategories[categoryId] = subCategories;
      _subCategoriesCacheTimestamp[categoryId] = DateTime.now();
      
      //AppLogger.d('Fetched and cached ${subCategories.length} subcategories for $categoryId');
      return subCategories;
    } catch (e) {
      //AppLogger.d('Error fetching subcategories: $e');
      // Return cached data if available, even if expired
      return _cachedSubCategories[categoryId] ?? [];
    }
  }
  
  // Clear cache (useful for forced refresh)
  static void clearCache() {
    _cachedCategories = null;
    _categoriesCacheTimestamp = null;
    _cachedSubCategories.clear();
    _subCategoriesCacheTimestamp.clear();
    //AppLogger.d('Category cache cleared');
  }

  // Get category by ID
  Future<Category?> getCategoryById(String categoryId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('Category')
          .doc(categoryId)
          .get();
      
      if (doc.exists) {
        return Category.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      //AppLogger.d('Error fetching category by ID: $e');
      return null;
    }
  }

  // Get subcategory by ID
  Future<SubCategory?> getSubCategoryById(String categoryId, String subCategoryId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('Category')
          .doc(categoryId)
          .collection('subCategory')  // Changed from 'SubCategory' to 'subCategory'
          .doc(subCategoryId)
          .get();
      
      if (doc.exists) {
        return SubCategory.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      //AppLogger.d('Error fetching subcategory by ID: $e');
      return null;
    }
  }

  // Create a new category (admin function)
  Future<String?> createCategory(String categoryName) async {
    try {
      DocumentReference docRef = await _firestore
          .collection('Category')
          .add({
        'categoryName': categoryName,
      });
      
      //AppLogger.d('Created category with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      //AppLogger.d('Error creating category: $e');
      return null;
    }
  }

  // Create a new subcategory (admin function)
  Future<String?> createSubCategory(String categoryId, String subCategoryName) async {
    try {
      DocumentReference docRef = await _firestore
          .collection('Category')
          .doc(categoryId)
          .collection('subCategory')  // Changed from 'SubCategory' to 'subCategory'
          .add({
        'subCategoryName': subCategoryName,
        'categoryId': categoryId,  // Changed from 'categoryID' to 'categoryId'
      });
      
      //AppLogger.d('Created subcategory with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      //AppLogger.d('Error creating subcategory: $e');
      return null;
    }
  }

  // Get subcategories by searching through all categories
  Future<List<SubCategory>> getSubCategoriesByIds(List<String> subCategoryIds) async {
    try {
      //AppLogger.d('Searching for subcategories with IDs: $subCategoryIds');
      
      List<SubCategory> foundSubCategories = [];
      
      // Get all categories first
      QuerySnapshot categoriesSnapshot = await _firestore
          .collection('Category')
          .get();
      
      // Search through each category's subcategories
      for (var categoryDoc in categoriesSnapshot.docs) {
        QuerySnapshot subCategoriesSnapshot = await _firestore
            .collection('Category')
            .doc(categoryDoc.id)
            .collection('subCategory')
            .get();
        
        for (var subCategoryDoc in subCategoriesSnapshot.docs) {
          if (subCategoryIds.contains(subCategoryDoc.id)) {
            foundSubCategories.add(SubCategory.fromFirestore(subCategoryDoc));
          }
        }
      }
      
      //AppLogger.d('Found ${foundSubCategories.length} subcategories');
      return foundSubCategories;
    } catch (e) {
      //AppLogger.d('Error searching subcategories: $e');
      return [];
    }
  }
}
