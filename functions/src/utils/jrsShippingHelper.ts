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
  'card': { percentage: 3.125, fixedFee: 13.39 },
  'gcash': { percentage: 2.5 },
  'cash_on_delivery': { percentage: 0 },
};

const PLATFORM_FEE_PERCENTAGE = 8.88; // 8.88% of cart value

// PayMongo divisor rate per supported payment method. Used by the new fee model
// to gross-up seller charges via `base × 1.12 / (1 − rate)` so both 12% VAT and
// the seller's share of the PayMongo cut are absorbed into a single deduction.
const PAYMONGO_DIVISOR_RATES: Record<string, number> = {
  'card': 0.03125,
  'gcash': 0.025,
  'cash_on_delivery': 0,
};

export function getPaymongoRate(paymentMethod: string): number {
  const method = paymentMethod.toLowerCase();
  if (method in PAYMONGO_DIVISOR_RATES) {
    return PAYMONGO_DIVISOR_RATES[method];
  }
  logger.warn(`Unknown payment method for divisor rate: ${paymentMethod}, defaulting to card`);
  return PAYMONGO_DIVISOR_RATES['card'];
}

// Seller fee breakdown interface
export interface SellerFeeBreakdown {
  sellerId: string;
  sellerName: string;
  cartValue: number;
  shippingCost: number;
  shippingVat: number;
  buyerShippingCharge: number;
  sellerShippingCharge: number;
  shippingSplitRule: 'buyer_pays_full' | 'seller_pays_full' | 'shipping_voucher_partial';
  totalChargedToBuyer: number; // Cart value + buyer's shipping portion
  paymentProcessingFee: number; // PayMongo base fee on buyer's total (0 for COD)
  paymentProcessingFeeVat: number; // VAT portion grossed-up via the new fee model
  platformFee: number; // Custom % or default 8.88% of this seller's cart value
  platformFeeVat: number;
  platformFeePercentage: number; // The actual percentage used for this seller
  totalSellerFees: number;
  netPayoutToSeller: number;
  hasInsuranceAndEvaluation?: boolean;
  insuranceCost?: number | null;
  evaluationCost?: number | null;
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
    insurance?: true; // Omit (or set true) — JRS returns 500 when sent as false
    valuation?: true;
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
      shippingVat: 0, // filled in by applyNewFeeModel
      buyerShippingCharge,
      sellerShippingCharge,
      shippingSplitRule,
      totalChargedToBuyer,
      paymentProcessingFee,
      paymentProcessingFeeVat: 0, // filled in by applyNewFeeModel
      platformFee,
      platformFeeVat: 0, // filled in by applyNewFeeModel
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
 * Apply the new gross-up seller fee model to a single SellerFeeBreakdown.
 *
 * The helper assumes the breakdown has been seeded by `calculateMultiSellerBreakdown`
 * (which sets `platformFee`, the initial split rule, and the initial buyer/seller
 * shipping allocation) and that any voucher post-processing pass has already
 * overwritten `buyerShippingCharge` / `sellerShippingCharge` / `shippingSplitRule`
 * / `totalChargedToBuyer` as needed.
 *
 * For each charge to the seller (shipping, paymongo, platform) we compute
 * `base × 1.12 / (1 − paymongoRate)` and split it into the base + VAT portion.
 * `sellerShippingCharge` is then redefined to be the seller's actual shipping
 * deduction (shipping+VAT when seller_pays_full; VAT-only otherwise; voucher
 * partial keeps the seller's pre-VAT portion and adds the full shipping VAT).
 *
 * Mutates the breakdown in place.
 */
export function applyNewFeeModel(
  breakdown: SellerFeeBreakdown,
  opts: {
    actualShippingCost: number;
    postDiscountCartValue: number;
    paymentMethod: string;
  }
): void {
  const { actualShippingCost, postDiscountCartValue, paymentMethod } = opts;
  const rate = getPaymongoRate(paymentMethod);
  const divisor = 1 - rate;

  // Use the buyer's actual transaction amount (already discounted + voucher-adjusted)
  // as the PayMongo base. For COD this is informational only (rate = 0).
  const buyerTotal = postDiscountCartValue + breakdown.buyerShippingCharge;
  breakdown.shippingCost = actualShippingCost;
  breakdown.totalChargedToBuyer = buyerTotal;

  // Gross-up helper: turn a seller-borne base into its grossed (× 1.12 ÷ D) total.
  const gross = (x: number) => (x * 1.12) / divisor;

  // PayMongo base
  let paymongoBase = 0;
  const method = paymentMethod.toLowerCase();
  if (method === 'card') {
    paymongoBase = buyerTotal * 0.03125 + 13.39;
  } else if (method === 'gcash') {
    paymongoBase = buyerTotal * 0.025;
  } // cash_on_delivery → 0

  const paymongoVat = gross(paymongoBase) - paymongoBase;

  // Shipping VAT — always charged to the seller, regardless of who pays the principal.
  const shippingVat = actualShippingCost > 0 ? gross(actualShippingCost) - actualShippingCost : 0;

  // Platform fee base: pre-discount cart + actual shipping cost (always, regardless of
  // who pays the shipping principal). Voucher discounts do not reduce DentPal's commission.
  const platformBase = (breakdown.cartValue + actualShippingCost) * (breakdown.platformFeePercentage / 100);
  breakdown.platformFee = platformBase;
  const platformVat = platformBase > 0 ? gross(platformBase) - platformBase : 0;

  // sellerShippingCharge: redefined as the seller's actual shipping deduction.
  // For partial voucher coverage the seller is still responsible for the full shipping VAT.
  const sellerShippingChargePreVat =
    breakdown.shippingSplitRule === 'shipping_voucher_partial'
      ? breakdown.sellerShippingCharge
      : (breakdown.shippingSplitRule === 'seller_pays_full' ? actualShippingCost : 0);

  const sellerShippingCharge = sellerShippingChargePreVat + shippingVat;

  breakdown.shippingVat = shippingVat;
  breakdown.paymentProcessingFee = paymongoBase;
  breakdown.paymentProcessingFeeVat = paymongoVat;
  breakdown.platformFeeVat = platformVat;
  breakdown.sellerShippingCharge = sellerShippingCharge;
  breakdown.totalSellerFees =
    sellerShippingCharge + paymongoBase + paymongoVat + breakdown.platformFee + platformVat;
  breakdown.netPayoutToSeller = postDiscountCartValue - breakdown.totalSellerFees;
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
 * Rules are checked in order from smallest to largest package — first match wins.
 * Weight thresholds are MAXIMUM capacities (the item must weigh at or below the limit).
 * Dimension checks are orientation-independent (item can be rotated to fit).
 * Express Letter is a flexible pouch (9.5 × 6.3 in / 24.13 × 16.00 cm, max 100g) —
 *   JRS confirmed no thickness limit applies; any item whose 2D footprint fits qualifies.
 * Pounder bags (1/3/5 Pounder) enforce a maxThickness for stacked items.
 * General Cargo is a last resort — returned as undefined so the JRS API decides.
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

  // Maximum thickness (cm) for poly mailer packaging types.
  // Express Letter is a flexible pouch — JRS confirmed it fits any item whose
  // 2D footprint fits within 9.5 × 6.3 in (24.13 × 16.00 cm), regardless of thickness.
  const ONE_POUNDER_MAX_THICKNESS = 5;      // small poly mailer
  const THREE_POUNDER_MAX_THICKNESS = 7;    // medium poly mailer
  const FIVE_POUNDER_MAX_THICKNESS = 10;    // large poly mailer

  // Helper: check if items fit in a 2D envelope/pouch (width × length)
  // with an optional maximum thickness for flat mailers.
  // Package dimensions are also sorted so the larger is "long" and smaller is "short"
  const fitsIn2D = (pkgDim1: number, pkgDim2: number, maxThickness?: number): boolean => {
    const pkgShort = Math.min(pkgDim1, pkgDim2);
    const pkgLong = Math.max(pkgDim1, pkgDim2);
    if (maxShort > pkgShort || maxLong > pkgLong) return false;
    if (maxThickness !== undefined && totalHeight > maxThickness) return false;
    return true;
  };

  // Helper: check if item fits in a 3D box (width × length × height)
  // All three dimensions are sorted and compared
  const fitsIn3D = (pkgDim1: number, pkgDim2: number, pkgDim3: number): boolean => {
    const pkgDims = [pkgDim1, pkgDim2, pkgDim3].sort((a, b) => a - b);
    const itemDims = [maxShort, maxLong, totalHeight].sort((a, b) => a - b);
    return itemDims[0] <= pkgDims[0] && itemDims[1] <= pkgDims[1] && itemDims[2] <= pkgDims[2];
  };

  // Rule 1: Express Letter — JRS pouch 9.5 × 6.3 in (24.13 × 16.00 cm), max 100g.
  // No thickness limit: the pouch is flexible and fits any item within the 2D footprint.
  if (totalWeight <= 100 && fitsIn2D(24.13, 16.00)) {
    logger.info('📦 Matched: Express Letter');
    return 'Express Letter';
  }

  // Rule 2: 1 Pounder (max 500g, fits 38.10 × 27.94 cm, max 5 cm thick)
  if (totalWeight <= 500 && fitsIn2D(38.10, 27.94, ONE_POUNDER_MAX_THICKNESS)) {
    logger.info('📦 Matched: 1 Pounder');
    return '1 Pounder';
  }

  // Rule 3: 3 Pounder (max 1500g, fits 45.72 × 35.56 cm, max 7 cm thick)
  if (totalWeight <= 1500 && fitsIn2D(45.72, 35.56, THREE_POUNDER_MAX_THICKNESS)) {
    logger.info('📦 Matched: 3 Pounder');
    return '3 Pounder';
  }

  // Rule 4: Bulilit Box — checked BEFORE 5 Pounder because it's a specialized small box
  // (max 2500g, fits 20.32 × 29.21 × 10.16 cm, preferred for fragile items)
  if (totalWeight <= 2500 && fitsIn3D(20.32, 29.21, 10.16)) {
    logger.info('📦 Matched: Bulilit Box');
    return 'Bulilit Box';
  }

  // Rule 5: 5 Pounder (max 2500g, fits 50.80 × 35.56 cm, max 10 cm thick)
  if (totalWeight <= 2500 && fitsIn2D(50.80, 35.56, FIVE_POUNDER_MAX_THICKNESS)) {
    logger.info('📦 Matched: 5 Pounder');
    return '5 Pounder';
  }

  // No rule matched — General Cargo is the last resort (JRS API determines automatically)
  logger.info('📦 No rule matched — falling back to General Cargo (JRS API determines)', {
    totalWeight,
    maxShort,
    maxLong,
    totalHeight
  });
  return undefined;
}

/**
 * Calculates JRS shipping cost for given order items between two addresses.
 * Returns both the shipping cost and the packaging name as reported by the JRS API.
 */
export async function calculateJRSShippingCost(
  sellerAddress: string,
  recipientAddress: string,
  orderItems: CartItemData[],
  jrsApiKey?: string,
  jrsApiUrl?: string,
  express: boolean = true,
  insurance: boolean = true,
  valuation: boolean = true,
  codAmountToCollect?: number
): Promise<{ shippingCost: number; packagingName?: string; insuranceCost?: number; evaluationCost?: number }> {
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

    // Determine the correct packaging locally first, then send it to JRS so the
    // getRate API prices against the right package instead of defaulting to General Cargo.
    // When productName is undefined (item too large for all known packages), JRS decides.
    const productName = determineProductName(shipmentItems);

    const resolvedCodAmount = typeof codAmountToCollect === 'number' && codAmountToCollect > 0
      ? codAmountToCollect
      : 0;

    const jrsRequest: JRSShippingRequest = {
      requestType: 'getrate',
      apiShippingRequest: {
        express,
        // insurance and valuation intentionally omitted from getRate — including them
        // adds a JRS surcharge to the estimate that isn't applied at actual booking time,
        // causing the quoted rate to exceed the real shipping charge.
        codAmountToCollect: resolvedCodAmount,
        // productName is only sent for standard (non-express) calls. When sent, JRS
        // overrides the express flag and returns the same fixed package rate regardless
        // of delivery speed. For express calls we omit it so JRS prices freely based
        // on the express flag + dimensions, giving the correct express premium.
        ...(!express && productName ? { productName } : {}),
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
      codAmountToCollect: resolvedCodAmount,
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
        codAmountToCollect: jrsRequest.apiShippingRequest.codAmountToCollect,
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
      timeout: 30000 // 30 seconds
    });

    // Log successful response
    logger.info('JRS API Response received:', {
      status: response.status,
      statusText: response.statusText,
      contentType: response.headers?.['content-type'],
      hasData: !!response.data,
      dataType: typeof response.data,
      dataKeys: response.data && typeof response.data === 'object' ? Object.keys(response.data) : []
    });

    if (response.status === 200 && response.data) {
      // Extract shipping cost and packaging name from JRS response
      const shippingCost = extractShippingCostFromJRS(response.data);
      const packagingName = extractPackagingNameFromJRS(response.data);
      const insuranceCost = insurance ? extractInsuranceCostFromJRS(response.data) : undefined;
      const evaluationCost = valuation ? extractEvaluationCostFromJRS(response.data) : undefined;

      if (shippingCost > 0) {
        logger.info(`✅ JRS shipping cost calculated: ₱${shippingCost}`, { packagingName: packagingName ?? 'unknown' });
        return { shippingCost, packagingName, insuranceCost, evaluationCost };
      } else {
        logger.error('JRS API returned invalid shipping cost', {
          shippingCost,
          responseData: JSON.stringify(response.data).substring(0, 500)
        });
        throw new Error(`JRS API returned invalid shipping cost: ${shippingCost}`);
      }
    } else {
      // Diagnostic: JRS replied 200 but with an empty/unparseable body. Capture
      // the content-type and a raw preview so we can see WHY (e.g. unrecognized
      // address, an HTML/gateway message, or a content-type axios didn't parse).
      // The getRate response is a shipping rate, not buyer PII.
      logger.error('JRS API returned an empty/unparseable 200 body', {
        status: response.status,
        statusText: response.statusText,
        contentType: response.headers?.['content-type'],
        dataType: typeof response.data,
        rawPreview: typeof response.data === 'string'
          ? response.data.substring(0, 500)
          : JSON.stringify(response.data ?? null).substring(0, 500),
        shipperRegion: maskAddress(shipperAddress),
        recipientRegion: maskAddress(recipientFormattedAddress),
        sameOriginAndDestination: shipperAddress === recipientFormattedAddress,
      });
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
      errorContext.errorCode = error.code; // e.g. ECONNABORTED for timeout, ECONNREFUSED, etc.
    }

    logger.error('Failed to calculate JRS shipping cost:', errorContext);
    throw new Error(`JRS shipping calculation failed: [${error.code ?? 'unknown'}] ${error.message}`);
  }
}

// Default fallback shipping cost when JRS API is unavailable. Only used by
// callers that opt into config fallback (allowConfigFallback = true). The
// checkout quote and order-creation paths surface an error instead so the buyer
// is never silently charged a placeholder rate.
export const DEFAULT_FALLBACK_SHIPPING_COST = 250;

// Bounded retry tuning for the flaky JRS API.
const JRS_MAX_ATTEMPTS = 4;
const JRS_RETRY_BASE_DELAY_MS = 400;

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

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
  allowConfigFallback: boolean = false,
  express: boolean = true,
  insurance: boolean = true,
  valuation: boolean = true,
  codAmountToCollect?: number
): Promise<{ shippingCost: number; isFallback: boolean; error?: string; packagingName?: string; insuranceCost?: number; evaluationCost?: number }> {
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

  // JRS is intermittently flaky (e.g. HTTP 200 with an empty body). Retry the
  // call a bounded number of times with exponential backoff before giving up,
  // so transient failures self-heal into a real rate instead of a fallback.
  const maxAttempts = JRS_MAX_ATTEMPTS;
  let lastError: any;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await calculateJRSShippingCost(
        sellerAddress,
        recipientAddress,
        orderItems,
        jrsApiKey,
        jrsApiUrl,
        express,
        insurance,
        valuation,
        codAmountToCollect
      );

      if (attempt > 1) {
        logger.info(`JRS shipping calculated after retry (attempt ${attempt}/${maxAttempts})`);
      }
      return {
        shippingCost: result.shippingCost,
        packagingName: result.packagingName,
        insuranceCost: result.insuranceCost,
        evaluationCost: result.evaluationCost,
        isFallback: false
      };
    } catch (error: any) {
      lastError = error;
      logger.warn(`JRS API attempt ${attempt}/${maxAttempts} failed:`, {
        error: error.message,
        errorType: 'runtime',
        attempt,
        sellerRegion: maskAddress(sellerAddress),
        recipientRegion: maskAddress(recipientAddress),
        itemCount: orderItems.length,
      });
      if (attempt < maxAttempts) {
        // Exponential backoff: 400ms, 800ms, 1600ms, ...
        await sleep(JRS_RETRY_BASE_DELAY_MS * Math.pow(2, attempt - 1));
      }
    }
  }

  // All attempts failed. Surface the error (no silent ₱250) unless a caller has
  // explicitly opted into config fallback for resilience.
  if (allowConfigFallback) {
    logger.warn(`JRS API failed after ${maxAttempts} attempts, using fallback ₱${fallbackCost}:`, {
      error: lastError?.message,
      sellerRegion: maskAddress(sellerAddress),
      recipientRegion: maskAddress(recipientAddress),
      itemCount: orderItems.length,
      fallbackCost,
    });
    return { shippingCost: fallbackCost, isFallback: true, error: lastError?.message };
  }

  throw new Error(
    `JRS shipping unavailable after ${maxAttempts} attempts: ${lastError?.message || 'unknown error'}`
  );
}

/**
 * Helper function to extract shipping cost from JRS API response
 */
export function extractShippingCostFromJRS(responseData: any): number {
  try {
    // JRS wraps the rate object under a "response" key
    const d = responseData.response ?? responseData;

    if (d.TotalShippingRate && typeof d.TotalShippingRate === 'number') {
      return d.TotalShippingRate;
    }

    if (d.BaseRate && typeof d.BaseRate === 'number') {
      return d.BaseRate;
    }

    if (d.rate && typeof d.rate === 'number') {
      return d.rate;
    }

    if (d.totalAmount && typeof d.totalAmount === 'number') {
      return d.totalAmount;
    }

    if (d.shippingCost && typeof d.shippingCost === 'number') {
      return d.shippingCost;
    }

    // Legacy nested keys
    if (d.rateResponse) {
      if (d.rateResponse.TotalShippingRate && typeof d.rateResponse.TotalShippingRate === 'number') {
        return d.rateResponse.TotalShippingRate;
      }
      if (d.rateResponse.BaseRate && typeof d.rateResponse.BaseRate === 'number') {
        return d.rateResponse.BaseRate;
      }
    }

    if (d.data && d.data.rate && typeof d.data.rate === 'number') {
      return d.data.rate;
    }

    logger.warn('Could not extract shipping cost from JRS response:', responseData);
    return 0;

  } catch (error) {
    logger.error('Error extracting shipping cost from JRS response:', error);
    return 0;
  }
}

/**
 * Extract the packaging/product name from the JRS API response.
 * JRS returns the chosen packaging as a "Name" field alongside the rate,
 * typically wrapped under a "response" key.
 */
export function extractPackagingNameFromJRS(responseData: any): string | undefined {
  try {
    // JRS wraps the rate object under a "response" key
    const d = responseData.response ?? responseData;

    if (d.Name && typeof d.Name === 'string') return d.Name;
    if (d.ProductName && typeof d.ProductName === 'string') return d.ProductName;
    if (d.packageType && typeof d.packageType === 'string') return d.packageType;
    if (d.PackageType && typeof d.PackageType === 'string') return d.PackageType;

    // Legacy nested keys
    if (d.rateResponse) {
      if (d.rateResponse.Name && typeof d.rateResponse.Name === 'string') return d.rateResponse.Name;
      if (d.rateResponse.ProductName && typeof d.rateResponse.ProductName === 'string') return d.rateResponse.ProductName;
    }

    if (d.data) {
      if (d.data.Name && typeof d.data.Name === 'string') return d.data.Name;
      if (d.data.ProductName && typeof d.data.ProductName === 'string') return d.data.ProductName;
    }

    return undefined;
  } catch {
    return undefined;
  }
}

/**
 * Extract the insurance cost from the JRS API response.
 * JRS returns this as "Insurance" inside the "response" wrapper.
 */
export function extractInsuranceCostFromJRS(responseData: any): number | undefined {
  try {
    const d = responseData.response ?? responseData;
    const fields = ['Insurance', 'InsuranceFee', 'insuranceFee', 'insurance_fee', 'InsuranceCost', 'insuranceCost'];
    for (const f of fields) {
      if (typeof d[f] === 'number') return d[f];
    }
    if (d.rateResponse) {
      for (const f of fields) {
        if (typeof d.rateResponse[f] === 'number') return d.rateResponse[f];
      }
    }
    return undefined;
  } catch {
    return undefined;
  }
}

/**
 * Extract the evaluation/valuation cost from the JRS API response.
 * JRS returns this as "Valuation" inside the "response" wrapper.
 */
export function extractEvaluationCostFromJRS(responseData: any): number | undefined {
  try {
    const d = responseData.response ?? responseData;
    const fields = ['Valuation', 'EvaluationFee', 'evaluationFee', 'evaluation_fee', 'ValuationFee', 'valuationFee', 'EvaluationCost', 'evaluationCost'];
    for (const f of fields) {
      if (typeof d[f] === 'number') return d[f];
    }
    if (d.rateResponse) {
      for (const f of fields) {
        if (typeof d.rateResponse[f] === 'number') return d.rateResponse[f];
      }
    }
    return undefined;
  } catch {
    return undefined;
  }
}
