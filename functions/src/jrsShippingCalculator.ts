import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import * as admin from 'firebase-admin';
import { 
  calculateJRSShippingCost,
  calculateJRSShippingCostWithFallback,
  DEFAULT_FALLBACK_SHIPPING_COST,
  extractShippingCostFromJRS,
  calculateCompleteBreakdown,
  calculateMultiSellerBreakdown,
  SellerFeeBreakdown,
  MultiSellerBreakdown
} from './utils/jrsShippingHelper';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// JRS shipping interfaces are now defined in ./utils/jrsShippingHelper

interface JRSShippingResponse {
  success: boolean;
  data: {
    shippingCost?: number;
    totalAmount?: number;
    sellerBreakdown?: SellerShippingCalculation[];
    sellerFeeBreakdowns?: SellerFeeBreakdown[];
    sellerShippingCharge?: number;
    buyerShippingCharge?: number;
    shippingSplitRule?: 'buyer_pays_full' | 'split_50_50' | 'per_seller';
    // Fee breakdown (totals across all sellers)
    totalChargedToBuyer?: number;
    paymentProcessingFee?: number;
    platformFee?: number;
    totalSellerFees?: number;
    netPayoutToSeller?: number;
  };
  error?: string;
}

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

interface CalculateShippingRequest {
  // New interface (multi-seller)
  cartItemIds?: string[];
  recipientAddress?: string; // Format: "City, Province/State"
  paymentMethod?: string; // Optional: for fee calculation
  // Old interface (single seller) - for backward compatibility
  sellerAddress?: string;
  cartItems?: CartItemData[];
  express?: boolean;
  insurance?: boolean;
  valuation?: boolean;
}

interface SellerShippingCalculation {
  sellerId: string;
  sellerName: string;
  sellerAddress: string;
  items: CartItemData[];
  shippingCost: number;
  cartValue: number;
  platformFeePercentage?: number;
}

const verifyAuthToken = async (authorizationHeader: string | undefined): Promise<DecodedIdToken> => {
  if (!authorizationHeader) {
    throw new Error("Missing Authorization header");
  }

  const token = authorizationHeader.startsWith("Bearer ") 
    ? authorizationHeader.substring(7) 
    : authorizationHeader;

  if (!token) {
    throw new Error("Invalid Authorization header format");
  }

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    return decodedToken;
  } catch (error) {
    logger.error("Token verification failed", { error });
    throw new Error("Invalid or expired authentication token");
  }
};

// Helper function to call JRS shipping API (similar to createCheckoutSession.ts)
// JRS shipping functions are now imported from ./utils/jrsShippingHelper

// Handle old interface for backward compatibility
async function handleOldInterface(request: CallableRequest<CalculateShippingRequest>, authHeader: string | undefined): Promise<JRSShippingResponse> {
  try {
    // Verify authentication
    await verifyAuthToken(authHeader);
    
    const { sellerAddress, cartItems, recipientAddress } = request.data;
    
    if (!sellerAddress || !cartItems || cartItems.length === 0) {
      throw new HttpsError('invalid-argument', 'Missing required shipping data');
    }

    logger.info('Using old interface - single seller calculation', {
      sellerAddress,
      recipientAddress: recipientAddress || sellerAddress,
      itemCount: cartItems.length
    });

    // Use provided recipientAddress or fallback to formatted sellerAddress
    const formattedRecipientAddress = formatAddress(recipientAddress || sellerAddress);

    // Calculate shipping cost using the helper with fallback support
    const shippingResult = await calculateJRSShippingCostWithFallback(
      sellerAddress,
      formattedRecipientAddress,
      cartItems,
      process.env.JRS_API_KEY,
      process.env.JRS_GETRATE_API_URL,
      DEFAULT_FALLBACK_SHIPPING_COST
    );

    const shippingCost = shippingResult.shippingCost;

    if (shippingResult.isFallback) {
      logger.warn('JRS API failed, using fallback shipping cost', {
        fallbackCost: shippingCost,
        error: shippingResult.error
      });
    }

    // Calculate subtotal for shipping allocation
    const subtotal = cartItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);

    // Get payment method from request, default to 'card'
    const paymentMethod = request.data.paymentMethod || 'card';

    // Calculate complete breakdown including all fees
    const breakdown = calculateCompleteBreakdown(subtotal, shippingCost, paymentMethod);

    logger.info('Old interface shipping calculation completed', {
      shippingCost,
      subtotal,
      paymentMethod,
      isFallback: shippingResult.isFallback,
      ...breakdown
    });

    return {
      success: true,
      data: {
        shippingCost: shippingCost,
        totalAmount: shippingCost,
        sellerShippingCharge: breakdown.sellerShippingCharge,
        buyerShippingCharge: breakdown.buyerShippingCharge,
        shippingSplitRule: breakdown.shippingSplitRule,
        totalChargedToBuyer: breakdown.totalChargedToBuyer,
        paymentProcessingFee: breakdown.paymentProcessingFee,
        platformFee: breakdown.platformFee,
        totalSellerFees: breakdown.totalSellerFees,
        netPayoutToSeller: breakdown.netPayoutToSeller
      }
    };

  } catch (error: any) {
    logger.error('Error in old interface shipping calculation', error);
    
    // Even if there's an unexpected error, return fallback values
    const fallbackCost = DEFAULT_FALLBACK_SHIPPING_COST;
    return {
      success: false,
      error: error.message || 'Failed to calculate shipping cost',
      data: {
        shippingCost: fallbackCost,
        sellerShippingCharge: 0, // Buyer pays full fallback cost
        buyerShippingCharge: fallbackCost
      }
    };
  }
}

/**
 * Calculates shipping cost using JRS Express API with multi-seller support
 */
export const calculateJRSShipping = onCall(
  { 
    region: 'asia-southeast1', // Philippines region
    cors: true,
    enforceAppCheck: false, // Disable AppCheck for shipping calculations to allow frontend calls
    secrets: ['JRS_API_KEY', 'JRS_GETRATE_API_URL']
  },
  async (request: CallableRequest<CalculateShippingRequest>): Promise<JRSShippingResponse> => {
    try {
      // Determine if using old or new interface
      const isOldInterface = !!(request.data.sellerAddress && request.data.cartItems);
      const isNewInterface = !!(request.data.cartItemIds && request.data.recipientAddress);

      logger.info('JRS Shipping calculation started', { 
        interface: isOldInterface ? 'old' : 'new',
        cartItemCount: isOldInterface ? request.data.cartItems?.length : request.data.cartItemIds?.length,
        recipientAddress: request.data.recipientAddress,
        sellerAddress: request.data.sellerAddress,
        userId: request.auth?.uid
      });

      // Get auth header for both interfaces
      const authHeader = request.rawRequest.headers.authorization;

      // Handle old interface (backward compatibility)
      if (isOldInterface) {
        return await handleOldInterface(request, authHeader);
      }

      // Verify authentication for new interface
      const decodedToken = await verifyAuthToken(authHeader);
      const userId = decodedToken.uid;

      // Validate request data for new interface
      if (!request.data.cartItemIds || !request.data.recipientAddress || request.data.cartItemIds.length === 0) {
        logger.error('Invalid request data', request.data);
        throw new HttpsError('invalid-argument', 'Missing required shipping data');
      }

      // Format recipient address
      const recipientAddress = formatAddress(request.data.recipientAddress);

      logger.info('Formatted recipient address', { recipientAddress });

      // Get user's cart items with validation
      const cartPromises = request.data.cartItemIds.map(async (cartItemId: string) => {
        const cartDoc = await db
          .collection('User')
          .doc(userId)
          .collection('Cart')
          .doc(cartItemId)
          .get();

        if (!cartDoc.exists) {
          throw new HttpsError('not-found', `Cart item ${cartItemId} not found`);
        }

        const cartData = cartDoc.data();
        
        // Validate cart item data
        if (!cartData || typeof cartData.quantity !== 'number' || cartData.quantity <= 0) {
          throw new HttpsError('invalid-argument', 'Invalid cart item data');
        }
        
        if (!cartData.productId || typeof cartData.productId !== 'string') {
          throw new HttpsError('invalid-argument', 'Invalid product ID in cart item');
        }

        return { id: cartDoc.id, ...cartData };
      });

      const cartItems = await Promise.all(cartPromises);

        // Get product details and group by seller
        const cartItemsWithDetails = await Promise.all(
          cartItems.map(async (cartItem: any) => {
            const productDoc = await db.collection('Product').doc(cartItem.productId).get();
            
            if (!productDoc.exists) {
              throw new HttpsError('not-found', `Product ${cartItem.productId} not found`);
            }

            const product = productDoc.data();
            
            let variationPrice = 0;
            let dimensions = {
              length: product?.dimensions?.length,
              width: product?.dimensions?.width,
              height: product?.dimensions?.height,
              weight: product?.dimensions?.weight
            };
            
            if (cartItem.variationId) {
              const variationDoc = await db
                .collection('Product')
                .doc(cartItem.productId)
                .collection('Variation')
                .doc(cartItem.variationId)
                .get();
              
              if (variationDoc.exists) {
                const variationData = variationDoc.data();
                variationPrice = variationData?.price || 0;
                
                // Get dimensions from variation if available, fallback to product dimensions
                if (variationData?.dimensions) {
                  dimensions = {
                    length: variationData.dimensions.length || dimensions.length,
                    width: variationData.dimensions.width || dimensions.width,
                    height: variationData.dimensions.height || dimensions.height,
                    weight: variationData.weight || dimensions.weight
                  };
                } else if (variationData?.weight) {
                  // Some variations might only have weight
                  dimensions.weight = variationData.weight;
                }
              } else {
                variationPrice = product?.price || 0;
              }
            } else {
              variationPrice = product?.price || 0;
            }

            return {
              productId: cartItem.productId,
              quantity: cartItem.quantity,
              price: variationPrice,
              sellerId: product?.sellerId,
              length: dimensions.length,
              width: dimensions.width,
              height: dimensions.height,
              weight: dimensions.weight,
            };
          })
        );      // Group items by seller
      const itemsBySeller = cartItemsWithDetails.reduce((groups, item) => {
        const sellerId = item.sellerId;
        if (!groups[sellerId]) {
          groups[sellerId] = [];
        }
        groups[sellerId].push(item);
        return groups;
      }, {} as Record<string, CartItemData[]>);

      logger.info('Grouped items by seller', {
        sellerCount: Object.keys(itemsBySeller).length,
        sellersData: Object.keys(itemsBySeller).map(sellerId => ({
          sellerId,
          itemCount: itemsBySeller[sellerId].length
        }))
      });

      // Calculate shipping cost for each seller in parallel
      const sellerShippingPromises = Object.entries(itemsBySeller).map(async ([sellerId, sellerItems]) => {
        // Get seller info and address from User collection
        const sellerDoc = await db.collection('User').doc(sellerId).get();
        const sellerData = sellerDoc.data();
        const sellerAddress = sellerData?.address || 'Makati, Metro Manila';
        const sellerName = sellerData?.displayName || 'Unknown Seller';
        
        // Get custom platform fee percentage from Seller collection
        const sellerProfileDoc = await db.collection('Seller').doc(sellerId).get();
        const sellerProfileData = sellerProfileDoc.data();
        const platformFeePercentage = sellerProfileData?.Platform_fee_percentage;
        if (platformFeePercentage !== undefined) {
          logger.info(`Seller ${sellerId} has custom platform fee: ${platformFeePercentage}%`);
        }

        logger.info(`Calculating shipping for seller ${sellerId}:`, {
          sellerAddress,
          itemCount: sellerItems.length
        });

        // Calculate shipping cost for this seller's items
        const sellerShippingCost = await calculateJRSShippingCost(
          sellerAddress,
          recipientAddress,
          sellerItems,
          process.env.JRS_API_KEY,
          process.env.JRS_GETRATE_API_URL
        );

        // Calculate cart value for this seller's items
        const sellerCartValue = sellerItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);

        return {
          sellerId,
          sellerName,
          sellerAddress,
          items: sellerItems,
          shippingCost: sellerShippingCost,
          cartValue: sellerCartValue,
          platformFeePercentage
        } as SellerShippingCalculation;
      });

      // Wait for all seller shipping calculations
      const sellerShippingResults = await Promise.all(sellerShippingPromises);
      
      // Calculate total shipping cost
      const totalShippingCost = sellerShippingResults.reduce((total, seller) => total + seller.shippingCost, 0);

      // Get payment method from request, default to 'card'
      const paymentMethod = request.data.paymentMethod || 'card';

      // Calculate per-seller fee breakdowns using the new multi-seller function
      const multiSellerBreakdown = calculateMultiSellerBreakdown(
        sellerShippingResults.map(seller => ({
          sellerId: seller.sellerId,
          sellerName: seller.sellerName,
          cartValue: seller.cartValue,
          shippingCost: seller.shippingCost,
          platformFeePercentage: seller.platformFeePercentage
        })),
        paymentMethod
      );

      logger.info('Multi-seller shipping calculation completed', {
        totalShippingCost,
        totalCartValue: multiSellerBreakdown.totalCartValue,
        paymentMethod,
        sellerResults: multiSellerBreakdown.sellerBreakdowns.map(seller => ({
          sellerId: seller.sellerId,
          sellerName: seller.sellerName,
          cartValue: seller.cartValue,
          shippingCost: seller.shippingCost,
          shippingSplitRule: seller.shippingSplitRule,
          buyerShippingCharge: seller.buyerShippingCharge,
          sellerShippingCharge: seller.sellerShippingCharge,
          platformFee: seller.platformFee,
          paymentProcessingFee: seller.paymentProcessingFee,
          netPayoutToSeller: seller.netPayoutToSeller
        }))
      });

      // Determine overall shipping split rule
      // If all sellers have the same rule, use that; otherwise 'per_seller'
      const uniqueRules = [...new Set(multiSellerBreakdown.sellerBreakdowns.map(s => s.shippingSplitRule))];
      const shippingSplitRule = uniqueRules.length === 1 ? uniqueRules[0] : 'per_seller';

      return {
        success: true,
        data: {
          shippingCost: totalShippingCost,
          totalAmount: totalShippingCost,
          sellerBreakdown: sellerShippingResults,
          sellerFeeBreakdowns: multiSellerBreakdown.sellerBreakdowns,
          // Use totals from multi-seller breakdown
          sellerShippingCharge: multiSellerBreakdown.totalSellerShippingCharge,
          buyerShippingCharge: multiSellerBreakdown.totalBuyerShippingCharge,
          shippingSplitRule: shippingSplitRule,
          totalChargedToBuyer: multiSellerBreakdown.grandTotalChargedToBuyer,
          paymentProcessingFee: multiSellerBreakdown.totalPaymentProcessingFee,
          platformFee: multiSellerBreakdown.totalPlatformFee,
          totalSellerFees: multiSellerBreakdown.totalSellerFees,
          netPayoutToSeller: multiSellerBreakdown.totalNetPayoutToSellers
        }
      };

    } catch (error: any) {
      logger.error('Error calculating JRS shipping', error);
      
      // Return fallback shipping cost instead of throwing error
      return {
        success: false,
        error: error.message || 'Failed to calculate shipping cost',
        data: {
          shippingCost: 250.0, // Fallback shipping cost
          sellerShippingCharge: 0, // Buyer pays full fallback cost
          buyerShippingCharge: 250.0
        }
      };
    }
  }
);

/**
 * Format address to ensure it's in "City, Province" format
 */
function formatAddress(address: string): string {
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
  return cleanAddress;
}


