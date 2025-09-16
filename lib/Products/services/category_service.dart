import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all categories
  Future<List<Category>> getCategories() async {
    try {
      print('🔍 Fetching categories from Firestore...');
      
      QuerySnapshot querySnapshot = await _firestore
          .collection('Category')
          .orderBy('categoryName')
          .get();
      
      List<Category> categories = querySnapshot.docs
          .map((doc) => Category.fromFirestore(doc))
          .toList();
      
      print('✅ Fetched ${categories.length} categories');
      return categories;
    } catch (e) {
      print('❌ Error fetching categories: $e');
      return [];
    }
  }

  // Get subcategories for a specific category
  Future<List<SubCategory>> getSubCategories(String categoryId) async {
    try {
      print('🔍 Fetching subcategories for category: $categoryId');
      
      QuerySnapshot querySnapshot = await _firestore
          .collection('Category')
          .doc(categoryId)
          .collection('subCategory')  // Changed from 'SubCategory' to 'subCategory'
          .orderBy('subCategoryName')
          .get();
      
      List<SubCategory> subCategories = querySnapshot.docs
          .map((doc) => SubCategory.fromFirestore(doc))
          .toList();
      
      print('✅ Fetched ${subCategories.length} subcategories for $categoryId');
      return subCategories;
    } catch (e) {
      print('❌ Error fetching subcategories: $e');
      return [];
    }
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
      print('❌ Error fetching category by ID: $e');
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
      print('❌ Error fetching subcategory by ID: $e');
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
      
      print('✅ Created category with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ Error creating category: $e');
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
      
      print('✅ Created subcategory with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ Error creating subcategory: $e');
      return null;
    }
  }
}
