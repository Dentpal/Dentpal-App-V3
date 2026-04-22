import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import * as admin from 'firebase-admin';
import {
  calculateJRSShippingCost,
  calculateJRSShippingCostWithFallback,
  DEFAULT_FALLBACK_SHIPPING_COST,
  calculateMultiSellerBreakdown,
  determineProductName,
  SellerFeeBreakdown,
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
    // Single unified packaging name: our local rule wins; JRS name used only when our rule returned nothing
    packagingSize?: string | null;
    insuranceCost?: number | null;
    evaluationCost?: number | null;
    isFallback?: boolean;
    fallbackError?: string | null;
    // New-interface (multi-seller) fields only
    sellerBreakdown?: SellerShippingCalculation[];
    sellerFeeBreakdowns?: SellerFeeBreakdown[];
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
  packagingName?: string; // packaging name returned by the JRS API
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
    const express: boolean = typeof request.data.express === 'boolean' ? request.data.express : true;
    const insurance: boolean = typeof request.data.insurance === 'boolean' ? request.data.insurance : true;
    const valuation: boolean = typeof request.data.valuation === 'boolean' ? request.data.valuation : true;
    
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

    // Determine the JRS product/packaging name for logging
    const shipmentItemsForProductName = cartItems
      .filter(item => item.length && item.width && item.height && item.weight)
      .flatMap(item => {
        const items = [];
        for (let i = 0; i < item.quantity; i++) {
          items.push({
            declaredValue: item.price,
            length: item.length!,
            width: item.width!,
            height: item.height!,
            weight: item.weight!
          });
        }
        return items;
      });
    const resolvedProductName = determineProductName(shipmentItemsForProductName);
    
    logger.info(`📦 Old interface - JRS packaging: ${resolvedProductName ?? 'auto (API determines)'}`, {
      totalWeight: shipmentItemsForProductName.reduce((sum, i) => sum + i.weight, 0),
      maxWidth: shipmentItemsForProductName.length > 0 ? Math.max(...shipmentItemsForProductName.map(i => i.width)) : 0,
      maxLength: shipmentItemsForProductName.length > 0 ? Math.max(...shipmentItemsForProductName.map(i => i.length)) : 0,
      totalHeight: shipmentItemsForProductName.reduce((sum, i) => sum + i.height, 0),
      itemCount: shipmentItemsForProductName.length
    });

    // Calculate shipping cost using the helper with fallback support
    const shippingResult = await calculateJRSShippingCostWithFallback(
      sellerAddress,
      formattedRecipientAddress,
      cartItems,
      process.env.JRS_API_KEY,
      process.env.JRS_GETRATE_API_URL,
      DEFAULT_FALLBACK_SHIPPING_COST,
      false,
      express,
      insurance,
      valuation
    );

    const shippingCost = shippingResult.shippingCost;
    const jrsPackagingName = shippingResult.packagingName;
    const jrsInsuranceCost = shippingResult.insuranceCost;
    const jrsEvaluationCost = shippingResult.evaluationCost;

    if (shippingResult.isFallback) {
      logger.warn('JRS API failed, using fallback shipping cost', {
        fallbackCost: shippingCost,
        error: shippingResult.error
      });
    }

    // Use our local rule if it matched; fall back to JRS's own name only when we had no rule
    const packagingSize = resolvedProductName ?? jrsPackagingName ?? null;

    logger.info('Old interface shipping calculation completed', {
      shippingCost,
      packagingSize: packagingSize ?? 'unknown',
      packagingSource: resolvedProductName ? 'local-rule' : 'jrs-api',
      isFallback: shippingResult.isFallback,
    });

    return {
      success: true,
      data: {
        shippingCost,
        packagingSize,
        insuranceCost: jrsInsuranceCost ?? null,
        evaluationCost: jrsEvaluationCost ?? null,
        isFallback: shippingResult.isFallback,
        fallbackError: shippingResult.error ?? null,
      }
    };

  } catch (error: any) {
    logger.error('Error in old interface shipping calculation', error);
    return {
      success: false,
      error: error.message || 'Failed to calculate shipping cost',
      data: { shippingCost: DEFAULT_FALLBACK_SHIPPING_COST, isFallback: true }
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

      // Express delivery preference from the frontend checkout page
      const expressDelivery: boolean =
        typeof request.data.express === 'boolean' ? request.data.express : true;

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

        // Determine the JRS product/packaging name for this seller's shipment
        const shipmentItemsForProductName = sellerItems
          .filter(item => item.length && item.width && item.height && item.weight)
          .flatMap(item => {
            const items = [];
            for (let i = 0; i < item.quantity; i++) {
              items.push({
                declaredValue: item.price,
                length: item.length!,
                width: item.width!,
                height: item.height!,
                weight: item.weight!
              });
            }
            return items;
          });
        const resolvedProductName = determineProductName(shipmentItemsForProductName);
        
        logger.info(`📦 Seller ${sellerId} (${sellerName}) - JRS packaging: ${resolvedProductName ?? 'auto (API determines)'}`, {
          totalWeight: shipmentItemsForProductName.reduce((sum, i) => sum + i.weight, 0),
          maxWidth: shipmentItemsForProductName.length > 0 ? Math.max(...shipmentItemsForProductName.map(i => i.width)) : 0,
          maxLength: shipmentItemsForProductName.length > 0 ? Math.max(...shipmentItemsForProductName.map(i => i.length)) : 0,
          totalHeight: shipmentItemsForProductName.reduce((sum, i) => sum + i.height, 0),
          itemCount: shipmentItemsForProductName.length
        });

        // Calculate shipping cost for this seller's items
        const jrsResult = await calculateJRSShippingCost(
          sellerAddress,
          recipientAddress,
          sellerItems,
          process.env.JRS_API_KEY,
          process.env.JRS_GETRATE_API_URL,
          expressDelivery
        );

        // Calculate cart value for this seller's items
        const sellerCartValue = sellerItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);

        return {
          resolvedProductName: resolvedProductName ?? 'auto',
          jrsPackagingName: jrsResult.packagingName,
          result: {
            sellerId,
            sellerName,
            sellerAddress,
            items: sellerItems,
            shippingCost: jrsResult.shippingCost,
            cartValue: sellerCartValue,
            platformFeePercentage,
            packagingName: jrsResult.packagingName,
          } as SellerShippingCalculation
        };
      });

      // Wait for all seller shipping calculations
      const sellerShippingResultsWithProduct = await Promise.all(sellerShippingPromises);
      const sellerShippingResults = sellerShippingResultsWithProduct.map(r => r.result);
      const resolvedProductNames = sellerShippingResultsWithProduct.map(r => r.resolvedProductName);

      // Use the first seller's locally-resolved product name for the response (backward compat)
      const primaryProductName = resolvedProductNames.find(n => n !== undefined) ?? 'auto';

      // Aggregate JRS-returned packaging names across all sellers
      const uniqueJrsPackagingNames = [...new Set(
        sellerShippingResultsWithProduct.map(r => r.jrsPackagingName).filter(Boolean) as string[]
      )];
      const overallPackagingSize = uniqueJrsPackagingNames.length > 0 ? uniqueJrsPackagingNames.join(', ') : undefined;

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

      return {
        success: true,
        data: {
          shippingCost: totalShippingCost,
          packagingSize: primaryProductName ?? overallPackagingSize ?? null,
          sellerBreakdown: sellerShippingResults,
          sellerFeeBreakdowns: multiSellerBreakdown.sellerBreakdowns,
        }
      };

    } catch (error: any) {
      logger.error('Error calculating JRS shipping', error);
      return {
        success: false,
        error: error.message || 'Failed to calculate shipping cost',
        data: { shippingCost: DEFAULT_FALLBACK_SHIPPING_COST, isFallback: true }
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


