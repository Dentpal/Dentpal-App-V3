import axios from 'axios';
import * as crypto from 'crypto';
import * as logger from 'firebase-functions/logger';

// Enable verbose debug logging (set via environment variable)
const ENABLE_DEBUG_LOGGING = process.env.JRS_DEBUG_LOGGING === 'true';

/**
 * Masks an address for logging purposes by keeping only region/city hints.
 * Removes street numbers, names, and zip codes to protect PII.
 * @example "123 Main St, Makati City, Metro Manila 1234" -> "*****, Makati City, Metro Manila *****"
 */
function maskAddress(address: string): string {
  if (!address) return '[empty]';
  
  const parts = address.split(',').map(p => p.trim());
  
  // Keep only city/region parts (typically the last 2-3 segments), mask the rest
  if (parts.length <= 2) {
    // Short address - mask first part, keep last
    return parts.length === 1 ? '*****' : `*****, ${parts[parts.length - 1]}`;
  }
  
  // Mask street-level detail (first parts), keep city/region (last 2 parts)
  const maskedParts = parts.map((part, index) => {
    // Keep last 2 parts (typically city and region)
    if (index >= parts.length - 2) {
      // Mask Philippine postal codes (exactly 4 digits) at word boundaries
      // Also mask any digits preceded by postal-related keywords
      return part
        .replace(/\b\d{4}\b/g, '*****') // Philippine postal codes are exactly 4 digits
        .replace(/(?:zip|postal|zipcode|postal\s*code)\s*:?\s*\d+/gi, '*****'); // Contextual keyword match
    }
    return '*****';
  });
  
  return maskedParts.join(', ');
}

/**
 * Creates a one-way hash of an address for correlation in logs.
 * Useful for debugging without exposing actual address.
 */
function hashAddress(address: string): string {
  if (!address) return 'empty';
  return crypto.createHash('sha256').update(address).digest('hex').substring(0, 8);
}

/**
 * Summarizes shipment items for logging without exposing sensitive details.
 */
function summarizeShipmentItems(items: ShipmentItem[]): {
  count: number;
  totalWeight: number;
  totalDeclaredValue: number;
  avgDimensions?: { length: number; width: number; height: number };
} {
  if (!items || items.length === 0) {
    return { count: 0, totalWeight: 0, totalDeclaredValue: 0 };
  }
  
  const totalWeight = items.reduce((sum, item) => sum + item.weight, 0);
  const totalDeclaredValue = items.reduce((sum, item) => sum + item.declaredValue, 0);
  
  // Calculate average dimensions
  const avgLength = items.reduce((sum, item) => sum + item.length, 0) / items.length;
  const avgWidth = items.reduce((sum, item) => sum + item.width, 0) / items.length;
  const avgHeight = items.reduce((sum, item) => sum + item.height, 0) / items.length;
  
  return {
    count: items.length,
    totalWeight: Math.round(totalWeight * 100) / 100,
    totalDeclaredValue: Math.round(totalDeclaredValue * 100) / 100,
    avgDimensions: {
      length: Math.round(avgLength * 10) / 10,
      width: Math.round(avgWidth * 10) / 10,
      height: Math.round(avgHeight * 10) / 10
    }
  };
}

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

// Seller fee breakdown interface
export interface SellerFeeBreakdown {
  sellerId: string;
  sellerName: string;
  cartValue: number;
  shippingCost: number;
  buyerShippingCharge: number;
  sellerShippingCharge: number;
  shippingSplitRule: 'buyer_pays_full' | 'seller_pays_full';
  totalChargedToBuyer: number; // Cart value + buyer's shipping portion
  paymentProcessingFee: number; // Based on buyer's total for this seller
  platformFee: number; // Custom % or default 8.88% of this seller's cart value
  platformFeePercentage: number; // The actual percentage used for this seller
  totalSellerFees: number;
  netPayoutToSeller: number;
}

// Multi-seller order breakdown
export interface MultiSellerBreakdown {
  // Summary totals
  totalCartValue: number;
  totalShippingCost: number;
  totalBuyerShippingCharge: number;
  totalSellerShippingCharge: number;
  grandTotalChargedToBuyer: number;
  totalPaymentProcessingFee: number;
  totalPlatformFee: number;
  totalSellerFees: number;
  totalNetPayoutToSellers: number;
  
  // Per-seller breakdowns
  sellerBreakdowns: SellerFeeBreakdown[];
}

interface JRSShippingRequest {
  requestType: 'getrate';
  apiShippingRequest: {
    express: boolean;
    insurance: boolean;
    valuation: boolean;
    codAmountToCollect: number;
    productName?: string; // Optional: Specify package type (e.g., "1 Pounder") to bypass automatic selection
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
 * Calculate platform fee (default 8.88% of cart value ONLY, excluding shipping)
 * @param cartValue - Subtotal/cart value (excluding shipping)
 * @param customPercentage - Optional custom platform fee percentage (overrides default)
 * @returns Platform fee amount
 */
export function calculatePlatformFee(cartValue: number, customPercentage?: number): number {
  const percentage = customPercentage !== undefined ? customPercentage : PLATFORM_FEE_PERCENTAGE;
  return (cartValue * percentage) / 100;
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
 * @param customPlatformFeePercentage - Optional custom platform fee percentage
 * @returns Complete breakdown of charges and fees
 */
export function calculateCompleteBreakdown(
  cartValue: number,
  shippingCost: number,
  paymentMethod: string = 'card',
  customPlatformFeePercentage?: number
): {
  // Shipping allocation
  buyerShippingCharge: number;
  sellerShippingCharge: number;
  shippingSplitRule: 'buyer_pays_full' | 'seller_pays_full';
  
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
  const shippingSplitRule: 'buyer_pays_full' | 'seller_pays_full' = 
    shippingCost > movThreshold ? 'buyer_pays_full' : 'seller_pays_full';
  
  // Calculate shipping allocation
  let buyerShippingCharge: number;
  let sellerShippingCharge: number;
  
  if (shippingSplitRule === 'seller_pays_full') {
    buyerShippingCharge = 0;
    sellerShippingCharge = shippingCost;
  } else {
    buyerShippingCharge = shippingCost;
    sellerShippingCharge = 0;
  }
  
  // Calculate total charged to buyer
  const totalChargedToBuyer = cartValue + buyerShippingCharge;
  
  // Calculate seller fees
  const paymentProcessingFee = calculatePaymentProcessingFee(totalChargedToBuyer, paymentMethod);
  const platformFee = calculatePlatformFee(cartValue, customPlatformFeePercentage);
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
 * Calculate fee breakdown for each seller in a multi-seller order
 * Each seller's fees are calculated based on THEIR cart value and shipping cost
 * 
 * Fee Calculation Rules:
 * 
 * Shipping Split:
 * - If seller's shipping > 10% of seller's cart value: Buyer pays 100% of shipping
 * - If seller's shipping ≤ 10% of seller's cart value: Seller pays 100% of shipping
 * 
 * Seller Fees:
 * - Payment Processing Fee: Based on totalChargedToBuyer (seller's cart + buyer's shipping portion)
 * - Platform Fee: Custom percentage from seller's account or default 8.88% of seller's cart value
 * - Seller's Shipping Charge: 100% of shipping (only if seller_pays_full rule applies)
 * 
 * Net Payout = Cart Value - Payment Fee - Platform Fee - Seller Shipping
 */
export function calculateMultiSellerBreakdown(
  sellers: Array<{
    sellerId: string;
    sellerName: string;
    cartValue: number;
    shippingCost: number;
    platformFeePercentage?: number; // Custom platform fee percentage for this seller
  }>,
  paymentMethod: string = 'card'
): MultiSellerBreakdown {
  const sellerBreakdowns: SellerFeeBreakdown[] = [];
  
  // Calculate breakdown for each seller
  for (const seller of sellers) {
    // Determine shipping split rule based on THIS seller's values
    const movThreshold = seller.cartValue * 0.1; // 10% of THIS seller's cart value
    const shippingSplitRule: 'buyer_pays_full' | 'seller_pays_full' = 
      seller.shippingCost > movThreshold ? 'buyer_pays_full' : 'seller_pays_full';
    
    // Calculate shipping allocation for this seller
    let buyerShippingCharge: number;
    let sellerShippingCharge: number;
    
    if (shippingSplitRule === 'seller_pays_full') {
      buyerShippingCharge = 0;
      sellerShippingCharge = seller.shippingCost;
    } else {
      buyerShippingCharge = seller.shippingCost;
      sellerShippingCharge = 0;
    }
    
    // Calculate total charged to buyer FOR THIS SELLER's items
    const totalChargedToBuyer = seller.cartValue + buyerShippingCharge;
    
    // Calculate seller fees based on THIS seller's totals
    const paymentProcessingFee = calculatePaymentProcessingFee(totalChargedToBuyer, paymentMethod);
    // Use seller's custom platform fee percentage if available, otherwise use default
    const platformFeePercentage = seller.platformFeePercentage !== undefined ? seller.platformFeePercentage : PLATFORM_FEE_PERCENTAGE;
    const platformFee = calculatePlatformFee(seller.cartValue, seller.platformFeePercentage);
    const totalSellerFees = paymentProcessingFee + platformFee + sellerShippingCharge;
    
    // Calculate net payout for this seller
    const netPayoutToSeller = seller.cartValue - paymentProcessingFee - platformFee - sellerShippingCharge;
    
    sellerBreakdowns.push({
      sellerId: seller.sellerId,
      sellerName: seller.sellerName,
      cartValue: seller.cartValue,
      shippingCost: seller.shippingCost,
      buyerShippingCharge,
      sellerShippingCharge,
      shippingSplitRule,
      totalChargedToBuyer,
      paymentProcessingFee,
      platformFee,
      platformFeePercentage,
      totalSellerFees,
      netPayoutToSeller
    });
    
    logger.info(`Seller ${seller.sellerId} fee breakdown:`, {
      cartValue: seller.cartValue,
      shippingCost: seller.shippingCost,
      shippingSplitRule,
      buyerShippingCharge,
      sellerShippingCharge,
      totalChargedToBuyer,
      paymentProcessingFee,
      platformFee,
      platformFeePercentage,
      totalSellerFees,
      netPayoutToSeller
    });
  }
  
  // Calculate totals across all sellers
  const totalCartValue = sellerBreakdowns.reduce((sum, s) => sum + s.cartValue, 0);
  const totalShippingCost = sellerBreakdowns.reduce((sum, s) => sum + s.shippingCost, 0);
  const totalBuyerShippingCharge = sellerBreakdowns.reduce((sum, s) => sum + s.buyerShippingCharge, 0);
  const totalSellerShippingCharge = sellerBreakdowns.reduce((sum, s) => sum + s.sellerShippingCharge, 0);
  const grandTotalChargedToBuyer = sellerBreakdowns.reduce((sum, s) => sum + s.totalChargedToBuyer, 0);
  const totalPaymentProcessingFee = sellerBreakdowns.reduce((sum, s) => sum + s.paymentProcessingFee, 0);
  const totalPlatformFee = sellerBreakdowns.reduce((sum, s) => sum + s.platformFee, 0);
  const totalSellerFees = sellerBreakdowns.reduce((sum, s) => sum + s.totalSellerFees, 0);
  const totalNetPayoutToSellers = sellerBreakdowns.reduce((sum, s) => sum + s.netPayoutToSeller, 0);
  
  logger.info('Multi-seller breakdown complete:', {
    sellerCount: sellers.length,
    totalCartValue,
    totalShippingCost,
    totalBuyerShippingCharge,
    totalSellerShippingCharge,
    grandTotalChargedToBuyer,
    totalPaymentProcessingFee,
    totalPlatformFee,
    totalSellerFees,
    totalNetPayoutToSellers
  });
  
  return {
    totalCartValue,
    totalShippingCost,
    totalBuyerShippingCharge,
    totalSellerShippingCharge,
    grandTotalChargedToBuyer,
    totalPaymentProcessingFee,
    totalPlatformFee,
    totalSellerFees,
    totalNetPayoutToSellers,
    sellerBreakdowns
  };
}

/**
 * Determines the JRS product name based on item dimensions and total weight.
 *
 * The function finds the **smallest package** whose dimensions can accommodate
 * all items. Rules are checked from smallest to largest. The first matching
 * rule wins (i.e. items fit within the package dimension limits).
 *
 * Weight is used as a **maximum capacity** check – if the total weight exceeds
 * the package's max capacity, the next larger package is tried.
 *
 * If no rule matches (items too large or too heavy for all packages), returns
 * undefined so the JRS getRate API can determine the product automatically.
 *
 * All dimensions are in centimeters, all weights are in grams.
 */
/**
 * Determine the JRS product name (packaging type) based on shipment weight and dimensions.
 * 
 * Rules are checked in order from smallest to largest package.
 * Weight thresholds are MAXIMUM capacities (the item must weigh at or below the limit).
 * Dimension checks are orientation-independent (item can be rotated to fit).
 * If no rule matches, returns undefined so the JRS API determines the product automatically.
 */
export function determineProductName(shipmentItems: ShipmentItem[]): string | undefined {
  if (!shipmentItems || shipmentItems.length === 0) {
    return undefined;
  }

  const totalWeight = shipmentItems.reduce((sum, item) => sum + item.weight, 0);
  
  // Get the aggregate dimensions across all items
  // For each item, sort its 2D footprint (width × length) so the larger is always "long" and smaller is "short"
  // This makes the check orientation-independent
  // Footprint (maxShort/maxLong) = largest single-item footprint (items share the same base)
  // Height (totalHeight) = sum of all item heights (items stack on top of each other)
  let maxShort = 0;  // max of the shorter side across all items
  let maxLong = 0;   // max of the longer side across all items
  let totalHeight = 0; // total stacked height across all items

  for (const item of shipmentItems) {
    const dim1 = item.width || 0;
    const dim2 = item.length || 0;
    const short = Math.min(dim1, dim2);
    const long = Math.max(dim1, dim2);
    const h = item.height || 0;

    maxShort = Math.max(maxShort, short);
    maxLong = Math.max(maxLong, long);
    totalHeight += h;
  }

  logger.info('📐 determineProductName input:', {
    totalWeight,
    maxShort,
    maxLong,
    totalHeight,
    itemCount: shipmentItems.length
  });

  // Helper: check if item fits in a 2D envelope/pouch (width × length)
  // Package dimensions are also sorted so the larger is "long" and smaller is "short"
  const fitsIn2D = (pkgDim1: number, pkgDim2: number): boolean => {
    const pkgShort = Math.min(pkgDim1, pkgDim2);
    const pkgLong = Math.max(pkgDim1, pkgDim2);
    return maxShort <= pkgShort && maxLong <= pkgLong;
  };

  // Helper: check if item fits in a 3D box (width × length × height)
  // All three dimensions are sorted and compared
  const fitsIn3D = (pkgDim1: number, pkgDim2: number, pkgDim3: number): boolean => {
    const pkgDims = [pkgDim1, pkgDim2, pkgDim3].sort((a, b) => a - b);
    const itemDims = [maxShort, maxLong, totalHeight].sort((a, b) => a - b);
    return itemDims[0] <= pkgDims[0] && itemDims[1] <= pkgDims[1] && itemDims[2] <= pkgDims[2];
  };

  // Rule 1: Express Letter (max 100g, fits 24.13 × 16.00 cm)
  if (totalWeight <= 100 && fitsIn2D(24.13, 16.00)) {
    logger.info('📦 Matched: Express Letter');
    return 'Express Letter';
  }

  // Rule 2: 1 Pounder (max 500g, fits 38.10 × 27.94 cm)
  if (totalWeight <= 500 && fitsIn2D(38.10, 27.94)) {
    logger.info('📦 Matched: 1 Pounder');
    return '1 Pounder';
  }

  // Rule 3: 3 Pounder (max 1500g, fits 45.72 × 35.56 cm)
  if (totalWeight <= 1500 && fitsIn2D(45.72, 35.56)) {
    logger.info('📦 Matched: 3 Pounder');
    return '3 Pounder';
  }

  // Rule 4: Bulilit Box — checked BEFORE 5 Pounder because it's a specialized small box
  // (max 2500g, fits 20.32 × 29.21 × 10.16 cm, preferred for fragile items)
  if (totalWeight <= 2500 && fitsIn3D(20.32, 29.21, 10.16)) {
    logger.info('📦 Matched: Bulilit Box');
    return 'Bulilit Box';
  }

  // Rule 5: 5 Pounder (max 2500g, fits 50.80 × 35.56 cm)
  if (totalWeight <= 2500 && fitsIn2D(50.80, 35.56)) {
    logger.info('📦 Matched: 5 Pounder');
    return '5 Pounder';
  }

  // No rule matched — let the JRS API determine automatically
  logger.info('📦 No manual rule matched — API will determine productName automatically', {
    totalWeight,
    maxShort,
    maxLong,
    totalHeight
  });
  return undefined;
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

    // Determine product name based on shipment weight and dimensions.
    // If no manual rule matches, productName will be undefined and the
    // JRS API will determine the appropriate product automatically.
    const productName = determineProductName(shipmentItems);

    const jrsRequest: JRSShippingRequest = {
      requestType: 'getrate',
      apiShippingRequest: {
        express: true,
        insurance: true,
        valuation: true,
        codAmountToCollect: 0,
        ...(productName ? { productName } : {}), // Only include productName when manually determined
        shipperAddressLine1: shipperAddress,
        recipientAddressLine1: recipientFormattedAddress,
        shipmentItems
      }
    };

    // Info-level log: non-PII summary only
    const itemSummary = summarizeShipmentItems(shipmentItems);
    logger.info('Calling JRS API for shipping calculation:', {
      shipperAddressHash: hashAddress(shipperAddress),
      recipientAddressHash: hashAddress(recipientFormattedAddress),
      shipperRegion: maskAddress(shipperAddress),
      recipientRegion: maskAddress(recipientFormattedAddress),
      productName: productName ?? 'auto (API determines)',
      itemCount: itemSummary.count,
      totalWeight: itemSummary.totalWeight,
      totalDeclaredValue: itemSummary.totalDeclaredValue,
      apiUrl: jrsApiUrl ? 'configured' : 'NOT CONFIGURED',
      apiKey: jrsApiKey ? 'configured' : 'NOT CONFIGURED'
    });

    // Debug-level log: detailed payload (only when debug logging is enabled)
    if (ENABLE_DEBUG_LOGGING) {
      logger.debug('JRS API Request body (debug):', {
        requestType: jrsRequest.requestType,
        express: jrsRequest.apiShippingRequest.express,
        insurance: jrsRequest.apiShippingRequest.insurance,
        valuation: jrsRequest.apiShippingRequest.valuation,
        shipperAddressMasked: maskAddress(jrsRequest.apiShippingRequest.shipperAddressLine1),
        recipientAddressMasked: maskAddress(jrsRequest.apiShippingRequest.recipientAddressLine1),
        shipmentItemsCount: jrsRequest.apiShippingRequest.shipmentItems.length,
        avgDimensions: itemSummary.avgDimensions,
        // Only include first item's non-sensitive metadata for debugging
        firstItemMeta: jrsRequest.apiShippingRequest.shipmentItems.length > 0 ? {
          weight: jrsRequest.apiShippingRequest.shipmentItems[0].weight,
          dimensions: `${jrsRequest.apiShippingRequest.shipmentItems[0].length}x${jrsRequest.apiShippingRequest.shipmentItems[0].width}x${jrsRequest.apiShippingRequest.shipmentItems[0].height}`
        } : null
      });
    }

    const response = await axios.post(jrsApiUrl, jrsRequest, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Ocp-Apim-Subscription-Key': jrsApiKey
      },
      timeout: 60000 // 60 seconds timeout
    });

    // Log successful response
    logger.info('JRS API Response received:', {
      status: response.status,
      statusText: response.statusText,
      hasData: !!response.data,
      dataKeys: response.data ? Object.keys(response.data) : []
    });

    if (response.status === 200 && response.data) {
      // Extract shipping cost from JRS response
      const shippingCost = extractShippingCostFromJRS(response.data);
      
      if (shippingCost > 0) {
        logger.info(`✅ JRS shipping cost calculated: ₱${shippingCost}`);
        return shippingCost;
      } else {
        logger.error('JRS API returned invalid shipping cost', { 
          shippingCost, 
          responseData: JSON.stringify(response.data).substring(0, 500) // Log first 500 chars
        });
        throw new Error(`JRS API returned invalid shipping cost: ${shippingCost}`);
      }
    } else {
      throw new Error(`JRS API returned status ${response.status}: ${response.statusText}`);
    }

  } catch (error: any) {
    // Enhanced error logging with more context (PII-safe)
    const errorContext: any = {
      error: error.message,
      sellerAddressHash: hashAddress(sellerAddress),
      sellerRegion: maskAddress(sellerAddress),
      recipientAddressHash: hashAddress(recipientAddress),
      recipientRegion: maskAddress(recipientAddress),
      itemCount: orderItems.length
    };
    
    // Add axios-specific error details if available
    if (error.response) {
      errorContext.status = error.response.status;
      errorContext.statusText = error.response.statusText;
      // Only include non-sensitive response data
      errorContext.hasResponseData = !!error.response.data;
      // Debug-level only: detailed response (may contain echoed addresses)
      if (ENABLE_DEBUG_LOGGING) {
        errorContext.dataPreview = typeof error.response.data === 'string' 
          ? error.response.data.substring(0, 200) 
          : JSON.stringify(error.response.data || {}).substring(0, 200);
      }
    } else if (error.request) {
      errorContext.requestMade = true;
      errorContext.noResponse = true;
    }
    
    logger.error('Failed to calculate JRS shipping cost:', errorContext);
    throw new Error(`JRS shipping calculation failed: ${error.message}`);
  }
}

// Default fallback shipping cost when JRS API is unavailable
export const DEFAULT_FALLBACK_SHIPPING_COST = 250;

/**
 * Calculates JRS shipping cost with fallback support.
 * 
 * By default, configuration errors (missing API key/URL) will throw immediately
 * to fail fast and surface misconfigurations early. Runtime/API errors (network
 * failures, timeouts, 500 errors, etc.) will use the fallback cost instead.
 * 
 * @param sellerAddress - The seller's address for shipping origin
 * @param recipientAddress - The recipient's address for shipping destination
 * @param orderItems - Array of cart items with dimensions and quantities
 * @param jrsApiKey - JRS API subscription key (required unless allowConfigFallback is true)
 * @param jrsApiUrl - JRS API endpoint URL (required unless allowConfigFallback is true)
 * @param fallbackCost - Fallback shipping cost when API fails (default: 250)
 * @param allowConfigFallback - If true, configuration errors will also use fallback instead of throwing (default: false)
 * @returns Object containing shippingCost, whether it's a fallback value, and optional error message
 * @throws Error if jrsApiKey or jrsApiUrl is missing and allowConfigFallback is false
 */
export async function calculateJRSShippingCostWithFallback(
  sellerAddress: string,
  recipientAddress: string,
  orderItems: CartItemData[],
  jrsApiKey?: string,
  jrsApiUrl?: string,
  fallbackCost: number = DEFAULT_FALLBACK_SHIPPING_COST,
  allowConfigFallback: boolean = false
): Promise<{ shippingCost: number; isFallback: boolean; error?: string }> {
  // Fail fast on configuration issues unless explicitly allowed to fallback
  if (!jrsApiKey || !jrsApiUrl) {
    const missingConfig = [];
    if (!jrsApiKey) missingConfig.push('jrsApiKey');
    if (!jrsApiUrl) missingConfig.push('jrsApiUrl');
    const configError = `JRS API configuration missing: ${missingConfig.join(', ')}`;
    
    if (!allowConfigFallback) {
      throw new Error(configError);
    }
    
    // Config fallback explicitly allowed - log warning and return fallback (PII-safe)
    logger.warn(`JRS API configuration missing, using fallback shipping cost of ₱${fallbackCost}:`, {
      missingConfig,
      sellerAddressHash: hashAddress(sellerAddress),
      sellerRegion: maskAddress(sellerAddress),
      recipientAddressHash: hashAddress(recipientAddress),
      recipientRegion: maskAddress(recipientAddress),
      itemCount: orderItems.length,
      fallbackCost,
      allowConfigFallback
    });
    
    return {
      shippingCost: fallbackCost,
      isFallback: true,
      error: configError
    };
  }

  try {
    const shippingCost = await calculateJRSShippingCost(
      sellerAddress,
      recipientAddress,
      orderItems,
      jrsApiKey,
      jrsApiUrl
    );
    
    return {
      shippingCost,
      isFallback: false
    };
  } catch (error: any) {
    // Log runtime/API failure and use fallback (PII-safe)
    logger.warn(`JRS API runtime failure, using fallback shipping cost of ₱${fallbackCost}:`, {
      error: error.message,
      errorType: 'runtime',
      sellerAddressHash: hashAddress(sellerAddress),
      sellerRegion: maskAddress(sellerAddress),
      recipientAddressHash: hashAddress(recipientAddress),
      recipientRegion: maskAddress(recipientAddress),
      itemCount: orderItems.length,
      fallbackCost
    });
    
    return {
      shippingCost: fallbackCost,
      isFallback: true,
      error: error.message
    };
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
