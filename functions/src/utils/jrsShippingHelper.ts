import axios from 'axios';
import * as logger from 'firebase-functions/logger';

// Interfaces
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

interface CartItemData {
  productId: string;
  quantity: number;
  price: number;
  length?: number;
  width?: number;
  height?: number;
  weight?: number;
}

/**
 * Calculates JRS shipping cost for given order items between two addresses
 */
export async function calculateJRSShippingCost(
  sellerAddress: string,
  recipientAddress: string,
  orderItems: CartItemData[],
  jrsApiKey?: string,
  jrsApiUrl?: string
): Promise<number> {
  if (!jrsApiKey || !jrsApiUrl) {
    throw new Error('JRS API configuration missing - API key and URL are required');
  }

  try {
    // Format addresses
    const shipperAddress = sellerAddress.includes(',') ? sellerAddress : `${sellerAddress}, Metro Manila`;
    const recipientFormattedAddress = recipientAddress.includes(',') ? recipientAddress : `${recipientAddress}, Metro Manila`;

    // Convert order items to shipment items
    const shipmentItems = [];
    for (const item of orderItems) {
      // Skip items that don't have required dimensions
      if (!item.length || !item.width || !item.height || !item.weight) {
        logger.warn('Skipping item with missing dimensions:', {
          productId: item.productId,
          dimensions: {
            length: item.length,
            width: item.width,
            height: item.height,
            weight: item.weight
          }
        });
        continue;
      }

      for (let i = 0; i < item.quantity; i++) {
        shipmentItems.push({
          declaredValue: item.price,
          length: item.length,
          width: item.width,
          height: item.height,
          weight: item.weight
        });
      }
    }

    // If no items have dimensions, throw an error
    if (shipmentItems.length === 0) {
      throw new Error('No items have the required dimensions for shipping calculation');
    }

    const jrsRequest: JRSShippingRequest = {
      requestType: 'getrate',
      apiShippingRequest: {
        express: true,
        insurance: true,
        valuation: true,
        codAmountToCollect: 0,
        shipperAddressLine1: shipperAddress,
        recipientAddressLine1: recipientFormattedAddress,
        shipmentItems
      }
    };

    logger.info('Calling JRS API for shipping calculation:', {
      shipperAddress,
      recipientAddress: recipientFormattedAddress,
      itemCount: shipmentItems.length
    });

    const response = await axios.post(jrsApiUrl, jrsRequest, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Ocp-Apim-Subscription-Key': jrsApiKey
      },
      timeout: 15000 // 15 seconds timeout
    });

    if (response.status === 200 && response.data) {
      // Extract shipping cost from JRS response
      const shippingCost = extractShippingCostFromJRS(response.data);
      
      if (shippingCost > 0) {
        logger.info(`✅ JRS shipping cost calculated: ₱${shippingCost}`);
        return shippingCost;
      } else {
        throw new Error(`JRS API returned invalid shipping cost: ${shippingCost}`);
      }
    } else {
      throw new Error(`JRS API returned status ${response.status}: ${response.statusText}`);
    }

  } catch (error: any) {
    logger.error('Failed to calculate JRS shipping cost:', {
      error: error.message,
      status: error.response?.status,
      data: error.response?.data
    });
    throw new Error(`JRS shipping calculation failed: ${error.message}`);
  }
}

/**
 * Helper function to extract shipping cost from JRS API response
 */
export function extractShippingCostFromJRS(responseData: any): number {
  try {
    // Check various possible fields for shipping cost
    if (responseData.TotalShippingRate && typeof responseData.TotalShippingRate === 'number') {
      return responseData.TotalShippingRate;
    }
    
    if (responseData.BaseRate && typeof responseData.BaseRate === 'number') {
      return responseData.BaseRate;
    }
    
    if (responseData.rate && typeof responseData.rate === 'number') {
      return responseData.rate;
    }
    
    if (responseData.totalAmount && typeof responseData.totalAmount === 'number') {
      return responseData.totalAmount;
    }
    
    if (responseData.shippingCost && typeof responseData.shippingCost === 'number') {
      return responseData.shippingCost;
    }
    
    // Check nested objects
    if (responseData.rateResponse) {
      if (responseData.rateResponse.TotalShippingRate && typeof responseData.rateResponse.TotalShippingRate === 'number') {
        return responseData.rateResponse.TotalShippingRate;
      }
      if (responseData.rateResponse.BaseRate && typeof responseData.rateResponse.BaseRate === 'number') {
        return responseData.rateResponse.BaseRate;
      }
    }
    
    if (responseData.data && responseData.data.rate && typeof responseData.data.rate === 'number') {
      return responseData.data.rate;
    }
    
    logger.warn('Could not extract shipping cost from JRS response:', responseData);
    return 0;
    
  } catch (error) {
    logger.error('Error extracting shipping cost from JRS response:', error);
    return 0;
  }
}
