import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import * as admin from 'firebase-admin';
import axios from 'axios';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

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
    sellerBreakdown?: SellerShippingCalculation[];
  };
  error?: string;
  message?: string;
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
async function calculateJRSShippingCost(
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

// Helper function to extract shipping cost from JRS API response (same as createCheckoutSession.ts)
function extractShippingCostFromJRS(responseData: any): number {
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

// Handle old interface for backward compatibility
async function handleOldInterface(request: CallableRequest<CalculateShippingRequest>): Promise<JRSShippingResponse> {
  try {
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

    // Calculate shipping cost using the existing helper
    const shippingCost = await calculateJRSShippingCost(
      sellerAddress,
      formattedRecipientAddress,
      cartItems,
      process.env.JRS_API_KEY,
      process.env.JRS_GETRATE_API_URL
    );

    logger.info('Old interface shipping calculation completed', {
      shippingCost,
      sellerAddress,
      recipientAddress: formattedRecipientAddress
    });

    return {
      success: true,
      data: {
        shippingCost: shippingCost,
        totalAmount: shippingCost
      }
    };

  } catch (error: any) {
    logger.error('Error in old interface shipping calculation', error);
    
    return {
      success: false,
      error: error.message || 'Failed to calculate shipping cost',
      data: {
        shippingCost: 50.0 // Fallback shipping cost
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

      // Handle old interface (backward compatibility)
      if (isOldInterface) {
        return await handleOldInterface(request);
      }

      // Verify authentication for new interface
      const authHeader = request.rawRequest.headers.authorization;
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
            length: product?.dimensions?.length,
            width: product?.dimensions?.width,
            height: product?.dimensions?.height,
            weight: product?.dimensions?.weight,
          };
        })
      );

      // Group items by seller
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
        // Get seller info and address
        const sellerDoc = await db.collection('User').doc(sellerId).get();
        const sellerData = sellerDoc.data();
        const sellerAddress = sellerData?.address || 'Makati, Metro Manila';
        const sellerName = sellerData?.displayName || 'Unknown Seller';

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

        return {
          sellerId,
          sellerName,
          sellerAddress,
          items: sellerItems,
          shippingCost: sellerShippingCost
        } as SellerShippingCalculation;
      });

      // Wait for all seller shipping calculations
      const sellerShippingResults = await Promise.all(sellerShippingPromises);
      
      // Calculate total shipping cost
      const totalShippingCost = sellerShippingResults.reduce((total, seller) => total + seller.shippingCost, 0);

      logger.info('Multi-seller shipping calculation completed', {
        totalShippingCost,
        sellerResults: sellerShippingResults.map(seller => ({
          sellerId: seller.sellerId,
          sellerName: seller.sellerName,
          shippingCost: seller.shippingCost
        }))
      });

      return {
        success: true,
        data: {
          shippingCost: totalShippingCost,
          totalAmount: totalShippingCost,
          sellerBreakdown: sellerShippingResults
        }
      };

    } catch (error: any) {
      logger.error('Error calculating JRS shipping', error);
      
      // Return fallback shipping cost instead of throwing error
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


