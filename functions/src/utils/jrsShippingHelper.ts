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

// Payment processing fee configuration
interface PaymentFeeConfig {
  percentage: number;
  fixedFee?: number;
}

const PAYMENT_PROCESSING_FEES: Record<string, PaymentFeeConfig> = {
  'card': { percentage: 3.5, fixedFee: 15 },
  'gcash': { percentage: 2.5 },
  'paymaya': { percentage: 2.2 },
  'grab_pay': { percentage: 2.2 },
  'billease': { percentage: 1.5 },
};

const PLATFORM_FEE_PERCENTAGE = 8.88; // 8.88% of cart value

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
 * Calculate payment processing fee based on payment method
 * @param totalChargedToBuyer - Total amount charged to buyer (cart value + applicable shipping)
 * @param paymentMethod - Payment method used
 * @returns Payment processing fee amount
 */
export function calculatePaymentProcessingFee(totalChargedToBuyer: number, paymentMethod: string): number {
  const feeConfig = PAYMENT_PROCESSING_FEES[paymentMethod.toLowerCase()];
  
  if (!feeConfig) {
    logger.warn(`Unknown payment method: ${paymentMethod}, defaulting to card fees`);
    const defaultConfig = PAYMENT_PROCESSING_FEES['card'];
    const percentageFee = (totalChargedToBuyer * defaultConfig.percentage) / 100;
    return percentageFee + (defaultConfig.fixedFee || 0);
  }
  
  const percentageFee = (totalChargedToBuyer * feeConfig.percentage) / 100;
  return percentageFee + (feeConfig.fixedFee || 0);
}

/**
 * Calculate platform fee (8.88% of cart value ONLY, excluding shipping)
 * @param cartValue - Subtotal/cart value (excluding shipping)
 * @returns Platform fee amount
 */
export function calculatePlatformFee(cartValue: number): number {
  return (cartValue * PLATFORM_FEE_PERCENTAGE) / 100;
}

/**
 * Calculate net payout to seller after all fees and charges
 * @param cartValue - Subtotal/cart value (excluding shipping)
 * @param paymentProcessingFee - Payment processing fee
 * @param platformFee - Platform fee
 * @param sellerShippingCharge - Seller's portion of shipping (if applicable)
 * @returns Net payout to seller
 */
export function calculateNetPayout(
  cartValue: number, 
  paymentProcessingFee: number, 
  platformFee: number, 
  sellerShippingCharge: number
): number {
  return cartValue - paymentProcessingFee - platformFee - sellerShippingCharge;
}

/**
 * Calculate complete shipping and fee breakdown
 * @param cartValue - Subtotal/cart value (excluding shipping)
 * @param shippingCost - Total shipping cost
 * @param paymentMethod - Payment method to calculate processing fee
 * @returns Complete breakdown of charges and fees
 */
export function calculateCompleteBreakdown(
  cartValue: number,
  shippingCost: number,
  paymentMethod: string = 'card'
): {
  // Shipping allocation
  buyerShippingCharge: number;
  sellerShippingCharge: number;
  shippingSplitRule: 'buyer_pays_full' | 'split_50_50';
  
  // Buyer charges
  totalChargedToBuyer: number;
  
  // Seller fees
  paymentProcessingFee: number;
  platformFee: number;
  totalSellerFees: number;
  netPayoutToSeller: number;
} {
  // Determine shipping split rule
  const movThreshold = cartValue * 0.1; // 10% of cart value
  const shippingSplitRule: 'buyer_pays_full' | 'split_50_50' = 
    shippingCost > movThreshold ? 'buyer_pays_full' : 'split_50_50';
  
  // Calculate shipping allocation
  let buyerShippingCharge: number;
  let sellerShippingCharge: number;
  
  if (shippingSplitRule === 'split_50_50') {
    buyerShippingCharge = shippingCost * 0.5;
    sellerShippingCharge = shippingCost * 0.5;
  } else {
    buyerShippingCharge = shippingCost;
    sellerShippingCharge = 0;
  }
  
  // Calculate total charged to buyer
  const totalChargedToBuyer = cartValue + buyerShippingCharge;
  
  // Calculate seller fees
  const paymentProcessingFee = calculatePaymentProcessingFee(totalChargedToBuyer, paymentMethod);
  const platformFee = calculatePlatformFee(cartValue);
  const totalSellerFees = paymentProcessingFee + platformFee + sellerShippingCharge;
  
  // Calculate net payout
  const netPayoutToSeller = calculateNetPayout(
    cartValue, 
    paymentProcessingFee, 
    platformFee, 
    sellerShippingCharge
  );
  
  logger.info('Complete breakdown calculated', {
    cartValue,
    shippingCost,
    paymentMethod,
    shippingSplitRule,
    buyerShippingCharge,
    sellerShippingCharge,
    totalChargedToBuyer,
    paymentProcessingFee,
    platformFee,
    totalSellerFees,
    netPayoutToSeller
  });
  
  return {
    buyerShippingCharge,
    sellerShippingCharge,
    shippingSplitRule,
    totalChargedToBuyer,
    paymentProcessingFee,
    platformFee,
    totalSellerFees,
    netPayoutToSeller
  };
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
      timeout: 60000 // 60 seconds timeout
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
