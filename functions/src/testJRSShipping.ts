import { onRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import axios from 'axios';
import { 
  calculateJRSShippingCost,
  calculateJRSShippingCostWithFallback,
  DEFAULT_FALLBACK_SHIPPING_COST,
  calculateCompleteBreakdown,
  calculateMultiSellerBreakdown,
  determineProductName
} from './utils/jrsShippingHelper';

interface CartItemData {
  productId: string;
  quantity: number;
  price: number;
  sellerId: string;
  weight?: number; // in grams
  length?: number; // in cm
  width?: number; // in cm
  height?: number; // in cm
}

/**
 * Raw JRS API test - logs only the actual request/response from JRS API
 * This function uses the same helper as the main function but focuses on raw data logging
 * 
 * Usage: 
 * curl https://REGION-PROJECT_ID.cloudfunctions.net/testJRSRawAPI
 */
export const testJRSRawAPI = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true,
    secrets: ['JRS_TEST_API_KEY', 'JRS_TEST_GETRATE_API_URL']
  },
  async (req, res) => {
    try {
      logger.info('=== Testing Raw JRS API Request/Response ===');

      // Test data - matches your cart items
      const sellerAddress = 'Makati, Metro Manila';
      const recipientAddress = 'San Jose del Monte, Bulacan';
      
      // Sample cart items - Test 1: Facemask 50s
      // const testCartItems: CartItemData[] = [
      //   {
      //     productId: 'Facemask 50s',
      //     quantity: 1,
      //     price: 100.00,
      //     sellerId: 'test-seller-1',
      //     weight: 200, // 200g
      //     length: 20,  // 20cm
      //     width: 10,   // 10cm
      //     height: 10   // 10cm
      //   },
      // ];

      const testCartItems: CartItemData[] = [
        {
          productId: 'Curaprox 4560 Single Toothbrush',
          quantity: 1,
          price: 100.00,
          sellerId: 'test-seller-1',
          weight: 10, // 10g
          length: 25,  // 25cm
          width: 10,   // 10cm
          height: 5   // 5cm
        },
      ];

      logger.info('Test Configuration:', {
        sellerAddress,
        recipientAddress,
        itemCount: testCartItems.length
      });

      // Format addresses (same logic as jrsShippingHelper)
      const shipperAddress = sellerAddress.includes(',') ? sellerAddress : `${sellerAddress}, Metro Manila`;
      const recipientFormattedAddress = recipientAddress.includes(',') ? recipientAddress : `${recipientAddress}, Metro Manila`;

      // Convert order items to shipment items (same logic as jrsShippingHelper)
      const shipmentItems = [];
      for (const item of testCartItems) {
        for (let i = 0; i < item.quantity; i++) {
          shipmentItems.push({
            declaredValue: item.price,
            length: item.length || 0,
            width: item.width || 0,
            height: item.height || 0,
            weight: item.weight || 0
          });
        }
      }

      // Determine productName using the same logic as the live function
      const resolvedProductName = determineProductName(shipmentItems);
      logger.info(`📦 Test - JRS packaging: ${resolvedProductName ?? 'auto (API determines)'}`, {
        totalWeight: shipmentItems.reduce((sum, i) => sum + i.weight, 0),
        itemCount: shipmentItems.length
      });

      // Construct JRS request (exact structure from jrsShippingHelper)
      const jrsRequest = {
        requestType: 'getrate',
        apiShippingRequest: {
          express: true,
          insurance: true,
          valuation: true,
          codAmountToCollect: 0,
          ...(resolvedProductName ? { productName: resolvedProductName } : {}),
          shipperAddressLine1: shipperAddress,
          recipientAddressLine1: recipientFormattedAddress,
          shipmentItems
        }
      };

      logger.info('📤 REQUEST TO JRS API:', {
        url: process.env.JRS_TEST_GETRATE_API_URL,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Ocp-Apim-Subscription-Key': process.env.JRS_TEST_API_KEY ? '[API_KEY_SET]' : '[API_KEY_MISSING]'
        },
        body: jrsRequest
      });

      // Make the actual API call (same as jrsShippingHelper)
      const apiUrl = process.env.JRS_TEST_GETRATE_API_URL;
      const apiKey = process.env.JRS_TEST_API_KEY;

      if (!apiUrl || !apiKey) {
        throw new Error('JRS API credentials not configured');
      }

      let jrsResponse;
      let jrsResponseData;
      let responseError = null;
      let extractedShippingCost = null;

      try {
        jrsResponse = await axios.post(apiUrl, jrsRequest, {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Ocp-Apim-Subscription-Key': apiKey
          },
          timeout: 60000 // 60 seconds timeout (same as jrsShippingHelper)
        });
        jrsResponseData = jrsResponse.data;

        logger.info('📥 RESPONSE FROM JRS API:', {
          status: jrsResponse.status,
          statusText: jrsResponse.statusText,
          headers: jrsResponse.headers,
          data: jrsResponseData
        });

        // Try to extract shipping cost using the helper's logic
        if (jrsResponseData) {
          // Look for shipping cost in various possible fields
          extractedShippingCost = jrsResponseData.shippingCost 
            || jrsResponseData.totalCost 
            || jrsResponseData.rate 
            || jrsResponseData.amount
            || null;
        }

      } catch (error: any) {
        responseError = error;
        
        if (error.response) {
          // JRS API responded with an error
          logger.error('❌ JRS API ERROR RESPONSE:', {
            status: error.response.status,
            statusText: error.response.statusText,
            headers: error.response.headers,
            data: error.response.data
          });
          jrsResponseData = error.response.data;
        } else if (error.request) {
          // Request was made but no response received
          logger.error('❌ NO RESPONSE FROM JRS API:', {
            error: error.message,
            request: {
              url: apiUrl,
              method: 'POST',
              timeout: '60000ms'
            }
          });
        } else {
          // Something else went wrong
          logger.error('❌ REQUEST SETUP ERROR:', {
            error: error.message
          });
        }
      }

      // Calculate totals for response
      const totalWeight = testCartItems.reduce((sum, item) => sum + (item.weight || 0) * item.quantity, 0);
      const totalValue = testCartItems.reduce((sum, item) => sum + item.price * item.quantity, 0);

      // Log the exact data in a clean format
      logger.info('📋 SUMMARY - EXACT DATA SENT & RECEIVED:', {
        SENT_TO_JRS: jrsRequest,
        RECEIVED_FROM_JRS: jrsResponseData || { error: responseError?.message }
      });

      // Prepare the response
      const response = {
        success: !responseError,
        testConfiguration: {
          sellerAddress,
          recipientAddress,
          itemCount: testCartItems.length,
          totalWeight: `${totalWeight}g`,
          totalValue: `₱${totalValue.toFixed(2)}`,
          item: testCartItems[0]
        },
        REQUEST_SENT_TO_JRS: jrsRequest,
        RESPONSE_FROM_JRS: jrsResponseData || { 
          error: responseError?.message || 'No response received',
          statusCode: (responseError as any)?.response?.status
        },
        extractedShippingCost: extractedShippingCost ? `₱${extractedShippingCost}` : 'Not found in response',
        apiEndpoint: {
          url: apiUrl,
          method: 'POST',
          authHeader: 'Ocp-Apim-Subscription-Key'
        },
        note: 'REQUEST_SENT_TO_JRS shows exactly what was sent. RESPONSE_FROM_JRS shows exactly what was received. Check Firebase logs for headers.'
      };

      logger.info('=== Raw API Test Completed ===');
      
      res.status(200).json(response);

    } catch (error: any) {
      logger.error('❌ Test failed with unexpected error:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Test failed',
        stack: error.stack,
        note: 'Check Firebase Functions logs for detailed error information'
      });
    }
  }
);

/**
 * Manual test function for JRS shipping calculation
 * Can be called via HTTP to test shipping calculations
 * 
 * Usage: 
 * curl https://REGION-PROJECT_ID.cloudfunctions.net/testJRSShipping
 */
export const testJRSShipping = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true,
    secrets: ['JRS_TEST_API_KEY', 'JRS_TEST_GETRATE_API_URL']
  },
  async (req, res) => {
    try {
      logger.info('=== Starting JRS Shipping Test ===');

      // Test data
      const sellerAddress = 'Makati, Metro Manila';
      const recipientAddress = 'San Jose del Monte, Bulacan';
      
      // Sample cart items with realistic dental product dimensions
      const testCartItems: CartItemData[] = [
        {
          productId: 'Curaprox 4560 Single Toothbrush',
          quantity: 1,
          price: 100.00,
          sellerId: 'test-seller-1',
          weight: 10, // 10g
          length: 25,  // 25cm
          width: 10,   // 10cm
          height: 5   // 5cm
        },
      ];

      const paymentMethod = 'cash'; // or 'cash'

      logger.info('Test Configuration:', {
        sellerAddress,
        recipientAddress,
        itemCount: testCartItems.length,
        paymentMethod
      });

      // Log request data that will be sent to JRS API
      const totalWeight = testCartItems.reduce((sum, item) => sum + (item.weight || 0) * item.quantity, 0);
      const subtotal = testCartItems.reduce((sum, item) => sum + item.price * item.quantity, 0);

      logger.info('Calculated totals:', {
        totalWeight: `${totalWeight}g`,
        subtotal: `₱${subtotal.toFixed(2)}`,
        itemBreakdown: testCartItems.map(item => ({
          productId: item.productId,
          quantity: item.quantity,
          itemPrice: `₱${item.price.toFixed(2)}`,
          itemTotal: `₱${(item.price * item.quantity).toFixed(2)}`,
          weight: `${(item.weight || 0) * item.quantity}g`,
          dimensions: `${item.length}x${item.width}x${item.height}cm`
        }))
      });

      // Test 1: Calculate shipping with fallback
      logger.info('\n--- Test 1: Calculate Shipping with Fallback ---');
      const shippingResult = await calculateJRSShippingCostWithFallback(
        sellerAddress,
        recipientAddress,
        testCartItems,
        process.env.JRS_TEST_API_KEY,
        process.env.JRS_TEST_GETRATE_API_URL,
        DEFAULT_FALLBACK_SHIPPING_COST
      );

      logger.info('Shipping Result:', {
        shippingCost: `₱${shippingResult.shippingCost.toFixed(2)}`,
        isFallback: shippingResult.isFallback,
        error: shippingResult.error || 'None'
      });

      // Test 2: Calculate complete breakdown (single seller)
      logger.info('\n--- Test 2: Complete Breakdown (Single Seller) ---');
      const breakdown = calculateCompleteBreakdown(subtotal, shippingResult.shippingCost, paymentMethod);

      logger.info('Fee Breakdown:', {
        subtotal: `₱${subtotal.toFixed(2)}`,
        shippingCost: `₱${shippingResult.shippingCost.toFixed(2)}`,
        paymentMethod,
        buyerShippingCharge: `₱${breakdown.buyerShippingCharge.toFixed(2)}`,
        sellerShippingCharge: `₱${breakdown.sellerShippingCharge.toFixed(2)}`,
        shippingSplitRule: breakdown.shippingSplitRule,
        totalChargedToBuyer: `₱${breakdown.totalChargedToBuyer.toFixed(2)}`,
        paymentProcessingFee: `₱${breakdown.paymentProcessingFee.toFixed(2)}`,
        platformFee: `₱${breakdown.platformFee.toFixed(2)}`,
        totalSellerFees: `₱${breakdown.totalSellerFees.toFixed(2)}`,
        netPayoutToSeller: `₱${breakdown.netPayoutToSeller.toFixed(2)}`
      });

      // Test 3: Multi-seller breakdown (simulate 2 sellers)
      logger.info('\n--- Test 3: Multi-Seller Breakdown ---');
      const multiSellerData = [
        {
          sellerId: 'seller-1',
          sellerName: 'Dental Supplier A',
          cartValue: 300.00,
          shippingCost: shippingResult.shippingCost * 0.6,
          platformFeePercentage: 10 // Custom 10% fee
        },
        {
          sellerId: 'seller-2',
          sellerName: 'Dental Supplier B',
          cartValue: 200.00,
          shippingCost: shippingResult.shippingCost * 0.4,
          platformFeePercentage: undefined // Will use default
        }
      ];

      const multiSellerBreakdown = calculateMultiSellerBreakdown(multiSellerData, paymentMethod);

      logger.info('Multi-Seller Results:', {
        totalCartValue: `₱${multiSellerBreakdown.totalCartValue.toFixed(2)}`,
        totalShippingCost: `₱${(multiSellerData[0].shippingCost + multiSellerData[1].shippingCost).toFixed(2)}`,
        totalBuyerShippingCharge: `₱${multiSellerBreakdown.totalBuyerShippingCharge.toFixed(2)}`,
        totalSellerShippingCharge: `₱${multiSellerBreakdown.totalSellerShippingCharge.toFixed(2)}`,
        grandTotalChargedToBuyer: `₱${multiSellerBreakdown.grandTotalChargedToBuyer.toFixed(2)}`,
        totalPaymentProcessingFee: `₱${multiSellerBreakdown.totalPaymentProcessingFee.toFixed(2)}`,
        totalPlatformFee: `₱${multiSellerBreakdown.totalPlatformFee.toFixed(2)}`,
        totalSellerFees: `₱${multiSellerBreakdown.totalSellerFees.toFixed(2)}`,
        totalNetPayoutToSellers: `₱${multiSellerBreakdown.totalNetPayoutToSellers.toFixed(2)}`,
        perSellerBreakdown: multiSellerBreakdown.sellerBreakdowns.map(seller => ({
          sellerId: seller.sellerId,
          sellerName: seller.sellerName,
          cartValue: `₱${seller.cartValue.toFixed(2)}`,
          shippingCost: `₱${seller.shippingCost.toFixed(2)}`,
          buyerShippingCharge: `₱${seller.buyerShippingCharge.toFixed(2)}`,
          sellerShippingCharge: `₱${seller.sellerShippingCharge.toFixed(2)}`,
          platformFee: `₱${seller.platformFee.toFixed(2)}`,
          paymentProcessingFee: `₱${seller.paymentProcessingFee.toFixed(2)}`,
          totalSellerFees: `₱${seller.totalSellerFees.toFixed(2)}`,
          netPayoutToSeller: `₱${seller.netPayoutToSeller.toFixed(2)}`,
          shippingSplitRule: seller.shippingSplitRule
        }))
      });

      // Prepare response
      const response = {
        success: true,
        message: 'JRS Shipping Test Completed Successfully',
        testConfiguration: {
          sellerAddress,
          recipientAddress,
          paymentMethod,
          totalWeight: `${totalWeight}g`,
          subtotal: `₱${subtotal.toFixed(2)}`
        },
        test1_ShippingCalculation: {
          shippingCost: `₱${shippingResult.shippingCost.toFixed(2)}`,
          isFallback: shippingResult.isFallback,
          error: shippingResult.error || null
        },
        test2_SingleSellerBreakdown: {
          subtotal: `₱${subtotal.toFixed(2)}`,
          shippingCost: `₱${shippingResult.shippingCost.toFixed(2)}`,
          buyerShippingCharge: `₱${breakdown.buyerShippingCharge.toFixed(2)}`,
          sellerShippingCharge: `₱${breakdown.sellerShippingCharge.toFixed(2)}`,
          shippingSplitRule: breakdown.shippingSplitRule,
          totalChargedToBuyer: `₱${breakdown.totalChargedToBuyer.toFixed(2)}`,
          paymentProcessingFee: `₱${breakdown.paymentProcessingFee.toFixed(2)}`,
          platformFee: `₱${breakdown.platformFee.toFixed(2)}`,
          totalSellerFees: `₱${breakdown.totalSellerFees.toFixed(2)}`,
          netPayoutToSeller: `₱${breakdown.netPayoutToSeller.toFixed(2)}`
        },
        test3_MultiSellerBreakdown: {
          totalCartValue: `₱${multiSellerBreakdown.totalCartValue.toFixed(2)}`,
          totalBuyerShippingCharge: `₱${multiSellerBreakdown.totalBuyerShippingCharge.toFixed(2)}`,
          totalSellerShippingCharge: `₱${multiSellerBreakdown.totalSellerShippingCharge.toFixed(2)}`,
          grandTotalChargedToBuyer: `₱${multiSellerBreakdown.grandTotalChargedToBuyer.toFixed(2)}`,
          totalPaymentProcessingFee: `₱${multiSellerBreakdown.totalPaymentProcessingFee.toFixed(2)}`,
          totalPlatformFee: `₱${multiSellerBreakdown.totalPlatformFee.toFixed(2)}`,
          totalNetPayoutToSellers: `₱${multiSellerBreakdown.totalNetPayoutToSellers.toFixed(2)}`,
          sellers: multiSellerBreakdown.sellerBreakdowns.map(seller => ({
            sellerId: seller.sellerId,
            sellerName: seller.sellerName,
            cartValue: `₱${seller.cartValue.toFixed(2)}`,
            netPayout: `₱${seller.netPayoutToSeller.toFixed(2)}`
          }))
        },
        note: 'Check Firebase Functions logs for detailed breakdown of sent/received data'
      };

      logger.info('=== Test Completed Successfully ===');
      
      res.status(200).json(response);

    } catch (error: any) {
      logger.error('Test failed:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Test failed',
        note: 'Check Firebase Functions logs for detailed error information'
      });
    }
  }
);
