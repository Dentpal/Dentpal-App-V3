import 'package:flutter/material.dart';
import 'package:dentpal/utils/app_logger.dart';
import '../services/jrs_shipping_service.dart';
import '../models/cart_model.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';

class JRSTestPage extends StatefulWidget {
  const JRSTestPage({super.key});

  @override
  State<JRSTestPage> createState() => _JRSTestPageState();
}

class _JRSTestPageState extends State<JRSTestPage> {
  bool _isLoading = false;
  String _result = '';
  
  final TextEditingController _sellerAddressController = TextEditingController(text: 'Makati, Metro Manila');
  final TextEditingController _recipientAddressController = TextEditingController(text: 'Quezon City, Metro Manila');

  @override
  void dispose() {
    _sellerAddressController.dispose();
    _recipientAddressController.dispose();
    super.dispose();
  }

  Future<void> _testJRSConnection() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing JRS API connection...';
    });

    try {
      AppLogger.d('🔍 Testing JRS API connection');
      
      final result = await JRSShippingService.testConnection();
      
      setState(() {
        _result = 'Connection Test Result:\n'
                 'Success: ${result.success}\n'
                 'Message: ${result.message}\n'
                 'Data: ${result.data}';
      });
      
      AppLogger.d('📋 JRS connection test result: $result');
    } catch (e) {
      setState(() {
        _result = 'Error testing JRS connection: $e';
      });
      AppLogger.d('❌ JRS connection test error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testShippingCalculation() async {
    setState(() {
      _isLoading = true;
      _result = 'Calculating shipping cost...';
    });

    try {
      AppLogger.d('🚚 Testing JRS shipping calculation');
      
      // Create sample cart items
      final sampleItems = [
        CartItem(
          cartItemId: 'test1',
          productId: 'product1',
          quantity: 2,
          addedAt: DateTime.now(),
          productPrice: 150.0,
          weight: 200.0, // 200g
          length: 15.0,   // 15cm
          width: 10.0,    // 10cm
          height: 5.0,    // 5cm
        ),
        CartItem(
          cartItemId: 'test2',
          productId: 'product2',
          quantity: 1,
          addedAt: DateTime.now(),
          productPrice: 75.0,
          weight: 150.0, // 150g
          length: 12.0,   // 12cm
          width: 8.0,     // 8cm
          height: 3.0,    // 3cm
        ),
      ];
      
      final result = await JRSShippingService.calculateShippingCost(
        sellerAddress: _sellerAddressController.text,
        recipientAddress: _recipientAddressController.text,
        cartItems: sampleItems,
        express: true,
        insurance: true,
        valuation: true,
      );
      
      setState(() {
        _result = 'Shipping Calculation Result:\n'
                 'Success: ${result.success}\n'
                 'Shipping Cost: ₱${result.shippingCost.toStringAsFixed(2)}\n'
                 'Message: ${result.message}\n'
                 '${result.error != null ? 'Error: ${result.error}\n' : ''}'
                 '\nTest Items:\n'
                 '- 2x Product 1 (₱150 each, 200g)\n'
                 '- 1x Product 2 (₱75, 150g)\n'
                 'Total Weight: ${2 * 200 + 150}g\n'
                 'Total Value: ₱${2 * 150 + 75}';
      });
      
      AppLogger.d('📋 JRS shipping calculation result: $result');
    } catch (e) {
      setState(() {
        _result = 'Error calculating shipping: $e';
      });
      AppLogger.d('❌ JRS shipping calculation error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.local_shipping, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'JRS Shipping Test',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address inputs
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Addresses',
                    style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  
                  Text('Seller Address', style: AppTextStyles.bodyMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sellerAddressController,
                    decoration: InputDecoration(
                      hintText: 'City, Province/State',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Text('Recipient Address', style: AppTextStyles.bodyMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _recipientAddressController,
                    decoration: InputDecoration(
                      hintText: 'City, Province/State',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Test buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testJRSConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Test Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testShippingCalculation,
                    icon: const Icon(Icons.calculate),
                    label: const Text('Test Shipping'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Results section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Test Results',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_result.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _result,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Click a test button to see results',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Information section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Important Notes',
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• This test uses the JRS Express QA API\n'
                    '• Addresses should be in "City, Province" format\n'
                    '• Sample items have realistic weight/dimensions\n'
                    '• Actual shipping costs may vary based on real product data\n'
                    '• Fallback cost is ₱50 if JRS API fails',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.warning,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
