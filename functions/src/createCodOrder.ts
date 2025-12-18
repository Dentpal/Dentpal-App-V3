import { onRequest, Request, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { 
  calculateJRSShippingCostWithFallback,
  calculateMultiSellerBreakdown,
  calculatePaymentProcessingFee,
  calculatePlatformFee,
} from './utils/jrsShippingHelper';
import cors = require('cors');

const db = admin.firestore();

// Configure CORS
const corsHandler = cors({
  origin: true,
  credentials: true
});

// Security headers middleware
function setSecurityHeaders(response: any): void {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('X-XSS-Protection', '1; mode=block');
  response.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
}

// Input sanitization functions
function sanitizeString(input: any, maxLength: number = 255): string {
  if (typeof input !== 'string') {
    throw new Error('Input must be a string');
  }
  return input.trim().substring(0, maxLength).replace(/[<>]/g, '');
}

function validateCartItemId(id: any): string {
  if (typeof id !== 'string') {
    throw new Error('Cart item ID must be a string');
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) {
    throw new Error('Cart item ID contains invalid characters');
  }
  if (id.length > 50) {
    throw new Error('Cart item ID too long');
  }
  return id;
}

function validateAddressId(id: any): string {
  if (typeof id !== 'string') {
    throw new Error('Address ID must be a string');
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) {
    throw new Error('Address ID contains invalid characters');
  }
  if (id.length > 50) {
    throw new Error('Address ID too long');
  }
  return id;
}

function validateRequestBody(body: any): {
  cartItemIds: string[];
  addressId: string;
  notes?: string;
} {
  if (!body || typeof body !== 'object') {
    throw new Error('Request body must be an object');
  }

  // Validate cart item IDs
  if (!body.cart_item_ids || !Array.isArray(body.cart_item_ids)) {
    throw new Error('cart_item_ids must be a non-empty array');
  }
  
  if (body.cart_item_ids.length === 0) {
    throw new Error('cart_item_ids cannot be empty');
  }
  
  if (body.cart_item_ids.length > 100) {
    throw new Error('Too many cart items (max 100)');
  }
  
  const cartItemIds = body.cart_item_ids.map(validateCartItemId);

  // Validate address ID
  const addressId = validateAddressId(body.address_id);

  // Validate notes (optional)
  const notes = body.notes ? sanitizeString(body.notes, 500) : undefined;

  return {
    cartItemIds,
    addressId,
    notes,
  };
}

/**
 * Create a Cash on Delivery order
 * - No PayMongo integration needed
 * - Payment status is set to 'paid' since COD is considered prepaid
 * - Order will be shipped and payment collected upon delivery
 */
export const createCodOrder = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true,
  },
  async (request, response) => {
    // Handle CORS
    corsHandler(request, response, async () => {
      try {
        console.log('Create COD order request started', { 
          method: request.method,
        });

        // Set security headers
        setSecurityHeaders(response);

        // Only allow POST requests
        if (request.method !== 'POST') {
          response.status(405).json({
            success: false,
            error: 'Method not allowed. Use POST.'
          });
          return;
        }

        // Verify authentication
        const authHeader = request.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
          response.status(401).json({
            success: false,
            error: 'Unauthorized: Missing or invalid authentication token'
          });
          return;
        }

        const idToken = authHeader.split('Bearer ')[1];
        let decodedToken: admin.auth.DecodedIdToken;
        
        try {
          decodedToken = await admin.auth().verifyIdToken(idToken);
        } catch (error: any) {
          console.error('Token verification failed:', error);
          response.status(401).json({
            success: false,
            error: 'Unauthorized: Invalid authentication token'
          });
          return;
        }

        const userId = decodedToken.uid;

        // Validate and sanitize request body
        const validatedData = validateRequestBody(request.body);
        const { cartItemIds, addressId, notes } = validatedData;

        console.log('Creating COD order', { 
          userId, 
          cartItemCount: cartItemIds.length,
          addressId
        });

        // Fetch cart items from user's Cart subcollection (same as createCheckoutSession)
        const cartPromises = cartItemIds.map(async (cartItemId: string) => {
          const cartDoc = await db
            .collection('User')
            .doc(userId)
            .collection('Cart')
            .doc(cartItemId)
            .get();

          if (!cartDoc.exists) {
            console.error(`Cart item ${cartItemId} not found`);
            throw new Error(`Cart item not found`);
          }

          const cartData = cartDoc.data();
          
          // Validate cart item data
          if (!cartData || typeof cartData.quantity !== 'number' || cartData.quantity <= 0) {
            throw new Error('Invalid cart item data');
          }
          
          if (!cartData.productId || typeof cartData.productId !== 'string') {
            throw new Error('Invalid product ID in cart item');
          }

          return { id: cartDoc.id, ...cartData };
        });

        const cartItems = await Promise.all(cartPromises);

        // Fetch shipping address (same path as createCheckoutSession)
        const addressDoc = await db
          .collection('User')
          .doc(userId)
          .collection('Address')
          .doc(addressId)
          .get();

        if (!addressDoc.exists) {
          throw new Error('Shipping address not found');
        }

        const shippingAddress = addressDoc.data();

        // Get product details for each cart item (same logic as createCheckoutSession)
        const orderItemsPromises = cartItems.map(async (cartItem: any) => {
          const productDoc = await db.collection('Product').doc(cartItem.productId).get();
          
          if (!productDoc.exists) {
            throw new Error(`Product ${cartItem.productId} not found`);
          }

          const product = productDoc.data();
          
          // Check if product is active
          if (product?.isActive !== true) {
            throw new Error(`Product is not available: ${product?.name || cartItem.productId}`);
          }
          
          let variationPrice = 0;
          let variationName = '';
          let isFragile = false;
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
              variationName = variationData?.name || '';
              isFragile = variationData?.isFragile || false;
              
              // Get dimensions from variation if available
              if (variationData?.dimensions) {
                dimensions = {
                  length: variationData.dimensions.length || dimensions.length,
                  width: variationData.dimensions.width || dimensions.width,
                  height: variationData.dimensions.height || dimensions.height,
                  weight: variationData.weight || dimensions.weight
                };
              } else if (variationData?.weight) {
                dimensions.weight = variationData.weight;
              }
            } else {
              console.error(`Variation ${cartItem.variationId} not found for product ${cartItem.productId}`);
              // Fallback to base product price
              variationPrice = product?.price || 0;
              variationName = 'Default';
            }
          } else {
            variationPrice = product?.price || 0;
          }

          // Get seller info
          const sellerDoc = await db.collection('User').doc(product?.sellerId).get();
          const sellerData = sellerDoc.data();

          return {
            productId: cartItem.productId,
            productName: `${product?.name || ''}${variationName ? ` - ${variationName}` : ''}`,
            productImage: product?.imageURL || '',
            price: variationPrice,
            quantity: cartItem.quantity,
            variationId: cartItem.variationId,
            sellerId: product?.sellerId,
            sellerName: sellerData?.displayName || 'Unknown Seller',
            total: variationPrice * cartItem.quantity,
            // Add physical dimensions
            length: dimensions.length,
            width: dimensions.width,
            height: dimensions.height,
            weight: dimensions.weight,
            isFragile: isFragile,
          };
        });

        const orderItems = await Promise.all(orderItemsPromises);

        // Calculate totals
        const subtotal = orderItems.reduce((sum, item) => sum + item.total, 0);
        
        // Get unique seller IDs
        const sellerIds = [...new Set(orderItems.map(item => item.sellerId))];

        // Check if any items are fragile
        const hasFragileItems = orderItems.some(item => item.isFragile);

        const sellerIdsArray = Array.from(sellerIds);

        // Calculate shipping cost using JRS API - compute per seller
        const recipientAddress = `${shippingAddress?.city}, ${shippingAddress?.state}`;
        
        console.log('Calculating shipping cost per seller using JRS API:', {
          sellerCount: sellerIds.length,
          recipientAddress,
          totalItems: orderItems.length
        });
        
        // Group order items by seller
        const itemsBySeller = orderItems.reduce((groups, item) => {
          const sellerId = item.sellerId;
          if (!groups[sellerId]) {
            groups[sellerId] = [];
          }
          groups[sellerId].push(item);
          return groups;
        }, {} as Record<string, typeof orderItems>);
        
        // Calculate shipping cost and cart value for each seller
        interface SellerShippingData {
          sellerId: string;
          sellerName: string;
          shippingCost: number;
          cartValue: number;
          isFallbackShipping: boolean;
          shippingError?: string;
        }
        
        const sellerShippingPromises: Promise<SellerShippingData>[] = Object.entries(itemsBySeller).map(async ([sellerId, sellerItems]) => {
          // Get seller address
          const sellerDoc = await db.collection('User').doc(sellerId).get();
          const sellerData = sellerDoc.data();
          const sellerAddress = `${sellerData?.address?.city || 'Makati'}, ${sellerData?.address?.state || 'Metro Manila'}`;
          const sellerName = sellerData?.displayName || sellerItems[0]?.sellerName || 'Unknown Seller';
          
          // Calculate cart value for this seller's items
          const sellerCartValue = sellerItems.reduce((sum, item) => sum + item.total, 0);
          
          console.log(`Calculating shipping for seller ${sellerId}:`, {
            sellerAddress,
            sellerName,
            cartValue: sellerCartValue,
            itemCount: sellerItems.length
          });
          
          // For COD, use a simplified shipping cost (can enhance with JRS API later)
          // For now, use default fallback shipping cost
          const shippingCost = 200; // Default COD shipping per seller
          
          return {
            sellerId,
            sellerName,
            shippingCost: shippingCost,
            cartValue: sellerCartValue,
            isFallbackShipping: false,
          };
        });
        
        // Wait for all seller shipping calculations
        const sellerShippingData = await Promise.all(sellerShippingPromises);
        
        // Calculate multi-seller breakdown
        const multiSellerBreakdown = calculateMultiSellerBreakdown(sellerShippingData, 'cash_on_delivery');

        const shippingCost = multiSellerBreakdown.totalShippingCost;
        const buyerShippingCharge = multiSellerBreakdown.totalBuyerShippingCharge;
        const sellerShippingCharge = multiSellerBreakdown.totalSellerShippingCharge;
        
        // Determine overall shipping split rule based on seller breakdowns
        const shippingSplitRules = multiSellerBreakdown.sellerBreakdowns.map(s => s.shippingSplitRule);
        const shippingSplitRule = shippingSplitRules.includes('split_50_50') ? 'split_50_50' : 
                                  (shippingSplitRules.length > 1 ? 'per_seller' : shippingSplitRules[0] || 'buyer_pays_full');

        // Calculate fees (COD typically has no payment processing fee, but keep platform fee)
        const totalAmount = subtotal + buyerShippingCharge;
        const paymentProcessingFee = 0; // No processing fee for COD
        const platformFee = calculatePlatformFee(subtotal);
        const totalSellerFees = paymentProcessingFee + platformFee + sellerShippingCharge;
        const netPayoutToSeller = subtotal - totalSellerFees;

        // Fetch user data for billing info
        const userDoc = await db.collection('User').doc(userId).get();
        const userData = userDoc.data();

        // Create order document
        const orderRef = db.collection('Order').doc();

        await orderRef.set({
          userId: userId,
          sellerIds: sellerIdsArray,
          items: orderItems,
          paymongo: {
            paymentMethod: 'cash_on_delivery',
            paymentStatus: 'paid', // COD orders are marked as 'paid' to allow shipping
            amount: totalAmount,
            currency: 'PHP',
            note: 'Cash on Delivery - Payment will be collected upon delivery',
          },
          summary: {
            subtotal: subtotal,
            shippingCost: shippingCost,
            taxAmount: 0,
            discountAmount: 0,
            total: totalAmount,
            totalItems: orderItems.reduce((sum, item) => sum + item.quantity, 0),
            sellerShippingCharge: sellerShippingCharge,
            buyerShippingCharge: buyerShippingCharge,
            shippingSplitRule: shippingSplitRule,
            usedFallbackShipping: false, // JRS API is used unless it fails
            fallbackShippingSellerCount: 0,
          },
          fees: {
            paymentProcessingFee: paymentProcessingFee,
            platformFee: platformFee,
            totalSellerFees: totalSellerFees,
            paymentMethod: 'cash_on_delivery',
          },
          sellerFeeBreakdowns: multiSellerBreakdown.sellerBreakdowns.map(s => ({
            sellerId: s.sellerId,
            sellerName: s.sellerName,
            cartValue: s.cartValue,
            shippingCost: s.shippingCost,
            buyerShippingCharge: s.buyerShippingCharge,
            sellerShippingCharge: s.sellerShippingCharge,
            shippingSplitRule: s.shippingSplitRule,
            totalChargedToBuyer: s.totalChargedToBuyer,
            paymentProcessingFee: 0, // No processing fee for COD
            platformFee: s.platformFee,
            totalSellerFees: s.platformFee + s.sellerShippingCharge,
            netPayoutToSeller: s.cartValue - (s.platformFee + s.sellerShippingCharge),
          })),
          payout: {
            netPayoutToSeller: netPayoutToSeller,
            calculatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          shippingInfo: {
            addressId: addressId,
            fullName: shippingAddress?.fullName,
            addressLine1: shippingAddress?.addressLine1,
            addressLine2: shippingAddress?.addressLine2,
            city: shippingAddress?.city,
            state: shippingAddress?.state,
            postalCode: shippingAddress?.postalCode,
            country: shippingAddress?.country,
            phoneNumber: shippingAddress?.phoneNumber,
            notes: notes,
          },
          status: 'confirmed',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusHistory: [
            {
              status: 'pending',
              timestamp: new Date(),
              note: 'Cash on Delivery order created',
            },
            {
              status: 'confirmed',
              timestamp: new Date(),
              note: 'COD order confirmed',
            }
          ],
          metadata: {
            cart_item_ids: cartItemIds,
            hasFragileItems: hasFragileItems,
            paymentMethod: 'cash_on_delivery',
          },
        });

        // Delete cart items after successful order creation (from user's Cart subcollection)
        const batch = db.batch();
        for (const cartItemId of cartItemIds) {
          batch.delete(db.collection('User').doc(userId).collection('Cart').doc(cartItemId));
        }
        await batch.commit();

        console.log(`COD order created successfully: ${orderRef.id}`);

        response.status(200).json({
          success: true,
          data: {
            order_id: orderRef.id,
            total_amount: totalAmount,
            currency: 'PHP',
            payment_method: 'cash_on_delivery',
          },
        });

      } catch (error: any) {
        console.error('Error creating COD order:', {
          error: error.message,
          timestamp: new Date().toISOString()
        });
        
        let statusCode = 500;
        let errorMessage = 'An internal error occurred. Please try again.';
        
        if (error.message.includes('authenticated')) {
          statusCode = 401;
          errorMessage = 'Authentication required.';
        } else if (error.message.includes('Cart item') || 
                   error.message.includes('Address') || 
                   error.message.includes('Invalid')) {
          statusCode = 400;
          errorMessage = 'Invalid request data. Please check your input.';
        }
        
        response.status(statusCode).json({
          success: false,
          error: errorMessage
        });
      }
    });
  });
