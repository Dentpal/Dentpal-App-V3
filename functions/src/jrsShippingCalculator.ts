import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import axios from 'axios';

interface ShipmentItem {
  declaredValue: number;
  length: number;
  width: number;
  height: number;
  weight: number;
}

interface JRSShippingRequest {
  requestType: 'getrate';
  apiShippingRequest: {
    express: boolean;
    insurance: boolean;
    valuation: boolean;
    codAmountToCollect: number;
    shipperAddressLine1: string;
    recipientAddressLine1: string;
    shipmentItems: ShipmentItem[];
  };
}

interface JRSShippingResponse {
  success: boolean;
  data?: {
    rateResponse?: {
      rate?: number;
      currency?: string;
      transitTime?: string;
    };
    totalAmount?: number;
    shippingCost?: number;
  };
  error?: string;
  message?: string;
}

interface CartItemData {
  productId: string;
  quantity: number;
  price: number;
  weight?: number; // in grams
  length?: number; // in cm
  width?: number; // in cm
  height?: number; // in cm
}

interface CalculateShippingRequest {
  sellerAddress: string; // Format: "City, Province/State"
  recipientAddress: string; // Format: "City, Province/State"
  cartItems: CartItemData[];
  express?: boolean;
  insurance?: boolean;
  valuation?: boolean;
}

// JRS API Configuration
const JRS_API_URL = 'https://jrs-express.azure-api.net/qa-online-shipping-getrate/ShippingRequestFunction';
const JRS_API_KEY = 'ab2a8be01b614cd1ad17dccb617a7652';

// Default shipping address if seller address is not available
const DEFAULT_SHIPPER_ADDRESS = 'Makati, Metro Manila';

// Default product dimensions if not specified (in cm)
const DEFAULT_DIMENSIONS = {
  length: 10,
  width: 10,
  height: 5,
  weight: 100 // in grams
};

/**
 * Calculates shipping cost using JRS Express API
 */
export const calculateJRSShipping = onCall(
  { 
    region: 'asia-southeast1', // Philippines region
    cors: true,
    enforceAppCheck: false // Set to true in production for security
  },
  async (request: CallableRequest<CalculateShippingRequest>): Promise<JRSShippingResponse> => {
    try {
      logger.info('JRS Shipping calculation started', { 
        sellerAddress: request.data.sellerAddress,
        recipientAddress: request.data.recipientAddress,
        itemCount: request.data.cartItems.length
      });

      // Validate request data
      if (!request.data.sellerAddress || !request.data.recipientAddress || !request.data.cartItems || request.data.cartItems.length === 0) {
        logger.error('Invalid request data', request.data);
        throw new HttpsError('invalid-argument', 'Missing required shipping data');
      }

      // Format addresses - ensure they are in "City, Province" format
      const shipperAddress = formatAddress(request.data.sellerAddress);
      const recipientAddress = formatAddress(request.data.recipientAddress);

      logger.info('Formatted addresses', { 
        shipperAddress, 
        recipientAddress 
      });

      // Process cart items and create shipment items
      const shipmentItems = processCartItems(request.data.cartItems);
      
      logger.info('Processed shipment items', { 
        itemCount: shipmentItems.length,
        totalWeight: shipmentItems.reduce((sum, item) => sum + item.weight, 0),
        totalValue: shipmentItems.reduce((sum, item) => sum + item.declaredValue, 0)
      });

      // Prepare JRS API request
      const jrsRequest: JRSShippingRequest = {
        requestType: 'getrate',
        apiShippingRequest: {
          express: request.data.express ?? true,
          insurance: request.data.insurance ?? true,
          valuation: request.data.valuation ?? true,
          codAmountToCollect: 0, // COD not supported in this implementation
          shipperAddressLine1: shipperAddress,
          recipientAddressLine1: recipientAddress,
          shipmentItems: shipmentItems
        }
      };

      logger.info('Calling JRS API', { 
        url: JRS_API_URL,
        request: jrsRequest
      });

      // Call JRS API
      const jrsResponse = await callJRSAPI(jrsRequest);

      logger.info('JRS API response received', jrsResponse);

      return {
        success: true,
        data: {
          shippingCost: jrsResponse.shippingCost || 50.0, // Fallback to ₱50 if no rate returned
          totalAmount: jrsResponse.totalAmount,
          rateResponse: jrsResponse.rateResponse
        }
      };

    } catch (error: any) {
      logger.error('Error calculating JRS shipping', error);
      
      // Return fallback shipping cost instead of throwing error
      // This ensures the cart/checkout process doesn't break
      return {
        success: false,
        error: error.message || 'Failed to calculate shipping cost',
        data: {
          shippingCost: 50.0 // Fallback shipping cost
        }
      };
    }
  }
);

/**
 * Format address to ensure it's in "City, Province" format
 */
function formatAddress(address: string): string {
  if (!address || address.trim() === '') {
    return DEFAULT_SHIPPER_ADDRESS;
  }

  // Clean up the address string
  const cleanAddress = address.trim();
  
  // If address doesn't contain a comma, assume it's just a city and default to Metro Manila
  if (!cleanAddress.includes(',')) {
    return `${cleanAddress}, Metro Manila`;
  }

  // Extract city and province/state
  const parts = cleanAddress.split(',').map(part => part.trim());
  
  if (parts.length >= 2) {
    const city = parts[0];
    const province = parts[1];
    return `${city}, ${province}`;
  }

  // Fallback to default if parsing fails
  return DEFAULT_SHIPPER_ADDRESS;
}

/**
 * Process cart items and convert them to JRS shipment items
 */
function processCartItems(cartItems: CartItemData[]): ShipmentItem[] {
  const shipmentItems: ShipmentItem[] = [];

  for (const item of cartItems) {
    // Create shipment item for each quantity
    for (let i = 0; i < item.quantity; i++) {
      const shipmentItem: ShipmentItem = {
        declaredValue: item.price,
        length: item.length || DEFAULT_DIMENSIONS.length,
        width: item.width || DEFAULT_DIMENSIONS.width,
        height: item.height || DEFAULT_DIMENSIONS.height,
        weight: item.weight || DEFAULT_DIMENSIONS.weight
      };

      shipmentItems.push(shipmentItem);
    }
  }

  return shipmentItems;
}

/**
 * Call JRS API with retry logic
 */
async function callJRSAPI(request: JRSShippingRequest): Promise<any> {
  const maxRetries = 3;
  let lastError: any;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      logger.info(`JRS API attempt ${attempt}/${maxRetries}`);

      const response = await axios.post(JRS_API_URL, request, {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Ocp-Apim-Subscription-Key': JRS_API_KEY
        },
        timeout: 30000 // 30 seconds timeout
      });

      logger.info('JRS API response status', { 
        status: response.status,
        statusText: response.statusText 
      });

      if (response.status === 200 && response.data) {
        logger.info('JRS API success', response.data);
        
        // Extract shipping cost from response
        // The actual response structure may vary, adjust as needed
        const extractedResult = extractShippingCost(response.data);
        
        if (extractedResult.success) {
          return {
            shippingCost: extractedResult.cost,
            totalAmount: extractedResult.cost,
            rateResponse: response.data
          };
        } else {
          // Log the detailed failure reason and throw an error
          logger.error('Failed to extract shipping cost from JRS response', {
            response: response.data,
            reason: extractedResult.reason
          });
          throw new Error(`Failed to extract shipping cost: ${extractedResult.reason}`);
        }
      } else {
        throw new Error(`JRS API returned status ${response.status}: ${response.statusText}`);
      }

    } catch (error: any) {
      lastError = error;
      
      logger.warn(`JRS API attempt ${attempt} failed`, {
        error: error.message,
        response: error.response?.data,
        status: error.response?.status
      });

      // If it's the last attempt, don't wait
      if (attempt < maxRetries) {
        // Wait before retrying (exponential backoff)
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  // All attempts failed, log error and return fallback
  logger.error('All JRS API attempts failed', lastError);
  throw new Error(`JRS API failed after ${maxRetries} attempts: ${lastError.message}`);
}

/**
 * Extract shipping cost from JRS API response
 * Based on actual JRS API response structure
 */
function extractShippingCost(responseData: any): { success: boolean; cost: number; reason?: string } {
  try {
    logger.info('Extracting shipping cost from JRS response', { 
      responseType: typeof responseData,
      responseKeys: Object.keys(responseData || {}),
      fullResponse: responseData 
    });
    
    // Primary: Check for TotalShippingRate at root level (in pesos)
    if (responseData.TotalShippingRate && typeof responseData.TotalShippingRate === 'number') {
      logger.info(`✅ Extracted TotalShippingRate: ₱${responseData.TotalShippingRate}`);
      return { success: true, cost: responseData.TotalShippingRate };
    }

    // Secondary: Check BaseRate at root level (in pesos)
    if (responseData.BaseRate && typeof responseData.BaseRate === 'number') {
      logger.info(`✅ Extracted BaseRate: ₱${responseData.BaseRate}`);
      return { success: true, cost: responseData.BaseRate };
    }

    // Tertiary: Check other possible fields in descending order of preference
    
    // Direct rate field (in pesos)
    if (responseData.rate && typeof responseData.rate === 'number') {
      logger.info(`✅ Extracted direct rate: ₱${responseData.rate}`);
      return { success: true, cost: responseData.rate };
    }

    // Total amount field (in pesos)
    if (responseData.totalAmount && typeof responseData.totalAmount === 'number') {
      logger.info(`✅ Extracted totalAmount: ₱${responseData.totalAmount}`);
      return { success: true, cost: responseData.totalAmount };
    }

    // Shipping cost field (in pesos)
    if (responseData.shippingCost && typeof responseData.shippingCost === 'number') {
      logger.info(`✅ Extracted shippingCost: ₱${responseData.shippingCost}`);
      return { success: true, cost: responseData.shippingCost };
    }

    // Nested in rateResponse object
    if (responseData.rateResponse && typeof responseData.rateResponse === 'object') {
      logger.info('Checking nested rateResponse object', { rateResponse: responseData.rateResponse });
      
      if (responseData.rateResponse.TotalShippingRate && typeof responseData.rateResponse.TotalShippingRate === 'number') {
        logger.info(`✅ Extracted nested rateResponse.TotalShippingRate: ₱${responseData.rateResponse.TotalShippingRate}`);
        return { success: true, cost: responseData.rateResponse.TotalShippingRate };
      }
      
      if (responseData.rateResponse.BaseRate && typeof responseData.rateResponse.BaseRate === 'number') {
        logger.info(`✅ Extracted nested rateResponse.BaseRate: ₱${responseData.rateResponse.BaseRate}`);
        return { success: true, cost: responseData.rateResponse.BaseRate };
      }
    }

    // Nested in data object
    if (responseData.data && typeof responseData.data === 'object') {
      logger.info('Checking nested data object', { data: responseData.data });
      
      if (responseData.data.TotalShippingRate && typeof responseData.data.TotalShippingRate === 'number') {
        logger.info(`✅ Extracted data.TotalShippingRate: ₱${responseData.data.TotalShippingRate}`);
        return { success: true, cost: responseData.data.TotalShippingRate };
      }
      
      if (responseData.data.rate && typeof responseData.data.rate === 'number') {
        logger.info(`✅ Extracted data.rate: ₱${responseData.data.rate}`);
        return { success: true, cost: responseData.data.rate };
      }
    }

    // Array of rates (take first one)
    if (Array.isArray(responseData.rates) && responseData.rates.length > 0) {
      const firstRate = responseData.rates[0];
      logger.info('Checking first rate in array', { firstRate });
      
      if (firstRate.TotalShippingRate && typeof firstRate.TotalShippingRate === 'number') {
        logger.info(`✅ Extracted array rates[0].TotalShippingRate: ₱${firstRate.TotalShippingRate}`);
        return { success: true, cost: firstRate.TotalShippingRate };
      }
      
      if (firstRate.rate && typeof firstRate.rate === 'number') {
        logger.info(`✅ Extracted array rates[0].rate: ₱${firstRate.rate}`);
        return { success: true, cost: firstRate.rate };
      }
    }

    // If we get here, log the full structure for debugging
    const responseStructure = JSON.stringify(responseData, null, 2);
    logger.warn('❌ Could not extract shipping cost from JRS response. Full response structure:', {
      response: responseStructure
    });
    
    return { 
      success: false, 
      cost: 50.0, 
      reason: `No valid shipping cost found in response. Response keys: ${Object.keys(responseData || {}).join(', ')}` 
    };

  } catch (error) {
    logger.error('❌ Error extracting shipping cost', { 
      error: error instanceof Error ? error.message : String(error),
      responseData 
    });
    return { 
      success: false, 
      cost: 50.0, 
      reason: `Error parsing response: ${error instanceof Error ? error.message : String(error)}` 
    };
  }
}

/**
 * Health check function for JRS API
 */
export const testJRSConnection = onCall(
  { 
    region: 'asia-southeast1',
    cors: true,
    enforceAppCheck: false
  },
  async (): Promise<{ success: boolean; message: string; data?: any }> => {
    try {
      logger.info('Testing JRS API connection');

      const testRequest: JRSShippingRequest = {
        requestType: 'getrate',
        apiShippingRequest: {
          express: true,
          insurance: true,
          valuation: true,
          codAmountToCollect: 0,
          shipperAddressLine1: 'Makati, Metro Manila',
          recipientAddressLine1: 'Quezon City, Metro Manila',
          shipmentItems: [{
            declaredValue: 100,
            length: 10,
            width: 10,
            height: 5,
            weight: 100
          }]
        }
      };

      const response = await callJRSAPI(testRequest);

      return {
        success: true,
        message: 'JRS API connection successful',
        data: response
      };

    } catch (error: any) {
      logger.error('JRS API connection test failed', error);
      
      return {
        success: false,
        message: `JRS API connection failed: ${error.message}`
      };
    }
  }
);
