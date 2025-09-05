#!/bin/bash

# Make script exit on error
set -e

echo "======================================="
echo "    Adding sample products to DentPal"
echo "======================================="

# Navigate to project root directory
cd "$(dirname "$0")/.."

# Run the Dart script
echo "Running product seeder script..."
flutter run -d chrome --web-port 5000 lib/utils/add_sample_products.dart

echo "Done! Sample products have been added to Firestore."
