import { onRequest, Request, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import axios from 'axios';
import { 
  calculateJRSShippingCost, 
  extractShippingCostFromJRS,
  calculateCompleteBreakdown,
  calculateMultiSellerBreakdown,
  calculatePaymentProcessingFee,
  calculatePlatformFee,
  SellerFeeBreakdown,
  MultiSellerBreakdown
} from './utils/jrsShippingHelper';
import cors = require('cors');



// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Configure Firestore to ignore undefined values
db.settings({
  ignoreUndefinedProperties: true
});

// Rate limiting store (in-memory for demo, use Redis in production)
// NOTE: This implementation only mitigates memory leaks in warm instances.
// For production environments, use a Redis-backed store for proper persistence and cleanup.
const rateLimitStore = new Map<string, { count: number; resetTime: number }>();

// Start periodic cleanup of expired rate limit entries
// This runs every 5 minutes to remove expired entries and prevent unbounded memory growth
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
setInterval(() => {
  const now = Date.now();
  let cleanedCount = 0;
  
  for (const [userId, data] of rateLimitStore.entries()) {
    if (now > data.resetTime) {
      rateLimitStore.delete(userId);
      cleanedCount++;
    }
  }
  
  if (cleanedCount > 0) {
    console.log(`Cleaned up ${cleanedCount} expired rate limit entries. Current size: ${rateLimitStore.size}`);
  }
}, CLEANUP_INTERVAL_MS);

// Security headers middleware
function setSecurityHeaders(response: any): void {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('X-XSS-Protection', '1; mode=block');
  response.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
}

// Rate limiting function with inline cleanup of expired entries
function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const windowMs = 60000; // 1 minute
  const maxRequests = 5;
  
  // Clean up expired entries before applying rate limit logic
  // This prevents memory growth during active usage
  for (const [id, data] of rateLimitStore.entries()) {
    if (now > data.resetTime) {
      rateLimitStore.delete(id);
    }
  }
  
  const userLimit = rateLimitStore.get(userId);
  
  if (!userLimit || now > userLimit.resetTime) {
    // Reset window
    rateLimitStore.set(userId, { count: 1, resetTime: now + windowMs });
    return true;
  }
  
  if (userLimit.count >= maxRequests) {
    return false; // Rate limit exceeded
  }
  
  userLimit.count++;
  return true;
}

// Input sanitization and validation functions
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

function validatePaymentMethods(methods: any): string[] {
  if (!Array.isArray(methods)) {
    throw new Error('Payment methods must be an array');
  }
  
  const validMethods = ['card', 'gcash', 'grab_pay', 'paymaya', 'billease', 'dob', 'dob_ubp'];
  const sanitizedMethods = methods.filter(method => 
    typeof method === 'string' && validMethods.includes(method)
  );
  
  if (sanitizedMethods.length === 0) {
    throw new Error('No valid payment methods provided');
  }
  
  return sanitizedMethods;
}

function validateUrl(url: any): string | undefined {
  if (!url) return undefined;
  
  if (typeof url !== 'string') {
    throw new Error('URL must be a string');
  }
  
  try {
    const parsedUrl = new URL(url);
    if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
      throw new Error('URL must use HTTP or HTTPS protocol');
    }
    return url;
  } catch {
    throw new Error('Invalid URL format');
  }
}

function validateRequestBody(body: any): {
  cartItemIds: string[];
  addressId: string;
  notes?: string;
  paymentMethodTypes: string[];
  successUrl?: string;
  cancelUrl?: string;
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

  // Validate payment methods
  const paymentMethodTypes = validatePaymentMethods(
    body.payment_method_types || ['card', 'gcash', 'grab_pay', 'paymaya']
  );

  // Validate URLs (optional)
  const successUrl = validateUrl(body.success_url);
  const cancelUrl = validateUrl(body.cancel_url);

  return {
    cartItemIds,
    addressId,
    notes,
    paymentMethodTypes,
    successUrl,
    cancelUrl
  };
}

// Configure CORS
const corsHandler = cors({ 
  origin: [
    'https://dentpal-store.web.app',
    'https://dentpal-store-sandbox-testing.web.app',
    'https://dentpal-161e5.web.app',
    'https://dentpal-161e5.firebaseapp.com',
    // Add localhost for development
    'http://localhost:1337',
    // Add common development ports
    'http://localhost:3000',
    'http://127.0.0.1:1337',
    // Add localhost for Flutter web development
    ...(process.env.NODE_ENV === 'development' || process.env.FUNCTIONS_EMULATOR === 'true' ? [
      'http://localhost:1337',
      'http://localhost:3000',
      'http://localhost:8080',
      'http://127.0.0.1:1337'
    ] : [])
  ],
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
  optionsSuccessStatus: 200 // For legacy browser support
});

// Paymongo API configuration
const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';
// Note: We'll use secrets for both public and secret keys in the function

// Helper function to verify authentication
async function verifyAuth(request: Request): Promise<string> {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('User must be authenticated');
  }

  const idToken = authHeader.replace('Bearer ', '');
  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error) {
    throw new Error('Invalid authentication token');
  }
}

// Country name to ISO code mapping
function getCountryCode(countryName: string): string {
  const countryMap: { [key: string]: string } = {
    'philippines': 'PH',
    'united states': 'US',
    'united states of america': 'US',
    'canada': 'CA',
    'united kingdom': 'GB',
    'australia': 'AU',
    'singapore': 'SG',
    'malaysia': 'MY',
    'thailand': 'TH',
    'vietnam': 'VN',
    'indonesia': 'ID',
    'japan': 'JP',
    'south korea': 'KR',
    'china': 'CN',
    'india': 'IN',
  };

  const normalized = countryName.toLowerCase().trim();
  return countryMap[normalized] || 'PH'; // Default to Philippines
}

// JRS Shipping Calculator Integration
// JRS shipping functions are now imported from ./utils/jrsShippingHelper

// ====================================
// PAYMONGO CHECKOUT SESSION FUNCTION
// ====================================

export const createCheckoutSession = onRequest(
  {
    secrets: ['PAYMONGO_SECRET_KEY', 'PAYMONGO_PUBLIC_KEY', 'JRS_API_KEY', 'JRS_GETRATE_API_URL'],
    memory: '512MiB',
    timeoutSeconds: 240,
    region: 'asia-southeast1'
  },
  async (request, response) => {
    // Set security headers
    setSecurityHeaders(response);
    
    corsHandler(request, response, async () => {
      let userId: string | undefined;
      
      try {
        const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
        const PAYMONGO_PUBLIC_KEY = process.env.PAYMONGO_PUBLIC_KEY;
        const JRS_API_KEY_SECRET = process.env.JRS_API_KEY;
        const JRS_GETRATE_API_URL = process.env.JRS_GETRATE_API_URL;

        // Verify user authentication
        userId = await verifyAuth(request);
        
        // Check rate limit
        if (!checkRateLimit(userId)) {
          response.status(429).json({
            success: false,
            error: 'Too many requests. Please try again later.'
          });
          return;
        }

        // Validate and sanitize input
        const validatedInput = validateRequestBody(request.body);
        const {
          cartItemIds,
          addressId,
          notes,
          paymentMethodTypes,
          successUrl,
          cancelUrl
        } = validatedInput;

        console.log(`Creating checkout session for user ${userId} with ${cartItemIds.length} cart items`);
        
        // Get user's cart items with validation
        const cartPromises = cartItemIds.map(async (cartItemId: string) => {
          const cartDoc = await db
            .collection('User')
            .doc(userId!)
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

        // Get shipping address
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

        // Get user info for billing
        const userDoc = await db.collection('User').doc(userId).get();
        const userData = userDoc.data();

        // Get product details for each cart item
        const orderItemsPromises = cartItems.map(async (cartItem: any) => {
          const productDoc = await db.collection('Product').doc(cartItem.productId).get();
          
          if (!productDoc.exists) {
            throw new Error(`Product ${cartItem.productId} not found`);
          }

          const product = productDoc.data();
          
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
              console.error(`Variation ${cartItem.variationId} not found for product ${cartItem.productId}`);
              // Fallback to base product price instead of throwing error
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
            // Add physical dimensions from variation or product
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
        
        // Calculate shipping cost using JRS API - compute per seller and sum costs
        // No fallbacks for multi-seller products - must use JRS calculated costs
        let shippingCost = 0;
        
        // Group order items by seller
        const itemsBySeller = orderItems.reduce((groups, item) => {
          const sellerId = item.sellerId;
          if (!groups[sellerId]) {
            groups[sellerId] = [];
          }
          groups[sellerId].push(item);
          return groups;
        }, {} as Record<string, typeof orderItems>);
        
        const recipientAddress = `${shippingAddress?.city || 'Manila'}, ${shippingAddress?.state || 'Metro Manila'}`;
        
        console.log('Calculating shipping cost per seller using JRS API:', {
          sellerCount: Object.keys(itemsBySeller).length,
          recipientAddress,
          totalItems: orderItems.length
        });
        
        // Calculate shipping cost and cart value for each seller in parallel
        interface SellerShippingData {
          sellerId: string;
          sellerName: string;
          shippingCost: number;
          cartValue: number;
        }
        
        const sellerShippingPromises: Promise<SellerShippingData>[] = Object.entries(itemsBySeller).map(async ([sellerId, sellerItems]) => {
          // Get seller address and name
          const sellerDoc = await db.collection('User').doc(sellerId).get();
          const sellerData = sellerDoc.data();
          const sellerAddress = sellerData?.address || 'Makati, Metro Manila';
          const sellerName = sellerData?.displayName || sellerItems[0]?.sellerName || 'Unknown Seller';
          
          // Calculate cart value for this seller's items
          const sellerCartValue = sellerItems.reduce((sum, item) => sum + item.total, 0);
          
          // Validate item dimensions and filter out items with missing dimensions
          const validItems = [];
          for (const item of sellerItems) {
            // Skip items that don't have required dimensions
            if (!item.length || !item.width || !item.height || !item.weight) {
              console.warn('Skipping item with missing dimensions:', {
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
            validItems.push(item);
          }

          // If no items have dimensions, throw an error
          if (validItems.length === 0) {
            throw new Error(`No items have the required dimensions for shipping calculation for seller ${sellerId}`);
          }
          
          console.log(`Calculating shipping for seller ${sellerId}:`, {
            sellerAddress,
            sellerName,
            cartValue: sellerCartValue,
            itemCount: validItems.length,
            originalItemCount: sellerItems.length
          });
          
          // Calculate shipping cost for this seller's items - no fallback, must succeed
          const sellerShippingCost = await calculateJRSShippingCost(
            sellerAddress,
            recipientAddress,
            validItems,
            JRS_API_KEY_SECRET,
            JRS_GETRATE_API_URL
          );
          
          // Validate that we got a valid shipping cost
          if (!sellerShippingCost || sellerShippingCost <= 0) {
            throw new Error(`JRS API returned invalid shipping cost (${sellerShippingCost}) for seller ${sellerId}`);
          }
          
          console.log(`Seller ${sellerId} shipping cost: ₱${sellerShippingCost}, cart value: ₱${sellerCartValue}`);
          
          return {
            sellerId,
            sellerName,
            shippingCost: sellerShippingCost,
            cartValue: sellerCartValue
          };
        });
        
        // Wait for all seller shipping calculations
        const sellerShippingData = await Promise.all(sellerShippingPromises);
        shippingCost = sellerShippingData.reduce((total, seller) => total + seller.shippingCost, 0);
        
        console.log(`Total shipping cost for all sellers: ₱${shippingCost}`);
        
        // Validate final shipping cost
        if (!shippingCost || shippingCost <= 0) {
          throw new Error(`Invalid total shipping cost calculated: ₱${shippingCost}`);
        }
        
        // Calculate PER-SELLER fee breakdowns using the multi-seller function
        // This ensures each seller is charged based on THEIR cart value, not the total order
        // 
        // Fee Calculation Rules:
        // - Shipping Split: If seller's shipping > 10% of seller's cart value → Buyer pays 100%
        //                   If seller's shipping ≤ 10% of seller's cart value → Split 50/50
        // - Payment Fee: Based on buyer's total for this seller (cart + buyer's shipping portion)
        // - Platform Fee: 8.88% of this seller's cart value
        // - Net Payout: Cart Value - Payment Fee - Platform Fee - Seller's Shipping
        const defaultPaymentMethod = paymentMethodTypes[0] || 'card';
        const multiSellerBreakdown = calculateMultiSellerBreakdown(sellerShippingData, defaultPaymentMethod);
        
        // Log minimal breakdown info (avoid exposing sensitive financial details in production)
        console.log(`Multi-Seller Breakdown: ${multiSellerBreakdown.sellerBreakdowns.length} seller(s), total charged: ₱${multiSellerBreakdown.grandTotalChargedToBuyer.toFixed(2)}`);
        
        // Extract totals from multi-seller breakdown
        const buyerShippingCharge = multiSellerBreakdown.totalBuyerShippingCharge;
        const sellerShippingCharge = multiSellerBreakdown.totalSellerShippingCharge;
        const totalChargedToBuyer = multiSellerBreakdown.grandTotalChargedToBuyer;
        const paymentProcessingFee = multiSellerBreakdown.totalPaymentProcessingFee;
        const platformFee = multiSellerBreakdown.totalPlatformFee;
        const totalSellerFees = multiSellerBreakdown.totalSellerFees;
        const netPayoutToSeller = multiSellerBreakdown.totalNetPayoutToSellers;
        
        // Determine overall shipping split rule
        // If all sellers have the same rule, use that; otherwise 'per_seller'
        const uniqueRules = [...new Set(multiSellerBreakdown.sellerBreakdowns.map(s => s.shippingSplitRule))];
        const shippingSplitRule = uniqueRules.length === 1 ? uniqueRules[0] : 'per_seller';
        
        // Total amount to charge buyer
        const totalAmount = totalChargedToBuyer;

        // Get unique seller IDs
        const sellerIds = [...new Set(orderItems.map(item => item.sellerId))];

        // Check if any items are fragile
        const hasFragileItems = orderItems.some(item => item.isFragile);

        // Create order document with per-seller fee breakdowns
        const orderRef = await db.collection('Order').add({
          userId: userId,
          sellerIds: sellerIds,
          items: orderItems.map(item => ({
            productId: item.productId,
            productName: item.productName,
            productImage: item.productImage,
            price: item.price,
            quantity: item.quantity,
            variationId: item.variationId,
            sellerId: item.sellerId,
            sellerName: item.sellerName,
            isFragile: item.isFragile,
          })),
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
          },
          fees: {
            paymentProcessingFee: paymentProcessingFee,
            platformFee: platformFee,
            totalSellerFees: totalSellerFees,
            paymentMethod: defaultPaymentMethod, // Will be updated when payment is completed
          },
          // Per-seller fee breakdowns for accurate payout calculation
          sellerFeeBreakdowns: multiSellerBreakdown.sellerBreakdowns.map(s => ({
            sellerId: s.sellerId,
            sellerName: s.sellerName,
            cartValue: s.cartValue,
            shippingCost: s.shippingCost,
            buyerShippingCharge: s.buyerShippingCharge,
            sellerShippingCharge: s.sellerShippingCharge,
            shippingSplitRule: s.shippingSplitRule,
            totalChargedToBuyer: s.totalChargedToBuyer,
            paymentProcessingFee: s.paymentProcessingFee,
            platformFee: s.platformFee,
            totalSellerFees: s.totalSellerFees,
            netPayoutToSeller: s.netPayoutToSeller,
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
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusHistory: [{
            status: 'pending',
            timestamp: new Date(),
            note: 'Order created',
          }],
          metadata: {
            cart_item_ids: cartItemIds,
            hasFragileItems: hasFragileItems,
          },
        });

        // Prepare line items for Paymongo checkout
        const lineItems = orderItems.map(item => ({
          name: item.productName,
          quantity: item.quantity,
          amount: Math.round(item.price * 100), // Convert to centavos
          currency: 'PHP',
          description: `Product ID: ${item.productId}`,
          images: item.productImage ? [item.productImage] : undefined,
        }));

        // Add shipping as a line item (only buyer's portion)
        if (buyerShippingCharge > 0) {
          // Generate shipping description based on split rules
          let shippingDescription: string;
          if (shippingSplitRule === 'per_seller') {
            // Multi-seller with different rules
            shippingDescription = `Shipping for ${sellerIds.length} sellers. Your portion: ₱${buyerShippingCharge.toFixed(2)}`;
          } else if (shippingSplitRule === 'split_50_50') {
            shippingDescription = `Buyer's half of shipping (Seller pays: ₱${sellerShippingCharge.toFixed(2)}). Total shipping: ₱${shippingCost.toFixed(2)}`;
          } else {
            shippingDescription = `Full shipping cost (Shipping > 10% of cart value)`;
          }
            
          lineItems.push({
            name: 'Shipping Fee',
            quantity: 1,
            amount: Math.round(buyerShippingCharge * 100),
            currency: 'PHP',
            description: shippingDescription,
            images: undefined,
          });
        }

        // Create Paymongo Checkout Session
        const fragilePrefix = hasFragileItems ? 'FRAGILE - ' : '';
        const checkoutSessionData = {
          data: {
            attributes: {
              description: `${fragilePrefix}DentPal Order #${orderRef.id}`,
              line_items: lineItems,
              payment_method_types: paymentMethodTypes,
              success_url: successUrl || 'https://dentpal-store.web.app/order-success',
              cancel_url: cancelUrl || 'https://dentpal-store.web.app/checkout?cancelled=true',
              metadata: {
                order_id: orderRef.id,
                user_id: userId,
                seller_ids: sellerIds.join(','),
                cart_item_ids: cartItemIds.join(','),
                has_fragile_items: hasFragileItems ? 'true' : 'false',
              },
              billing: {
                name: userData?.displayName || shippingAddress?.fullName,
                email: userData?.email,
                phone: shippingAddress?.phoneNumber,
                address: {
                  line1: shippingAddress?.addressLine1,
                  line2: shippingAddress?.addressLine2,
                  city: shippingAddress?.city,
                  state: shippingAddress?.state,
                  postal_code: shippingAddress?.postalCode,
                  country: getCountryCode(shippingAddress?.country || 'Philippines'),
                },
              },
            },
          },
        };

        // Use secret key if available, otherwise fall back to public key
        const paymongoKey = PAYMONGO_SECRET_KEY || PAYMONGO_PUBLIC_KEY;
        
        if (!paymongoKey) {
          console.warn('No Paymongo API key configured - checkout session will fail');
        }

        const checkoutResponse = await axios.post(
          `${PAYMONGO_BASE_URL}/checkout_sessions`,
          checkoutSessionData,
          {
            headers: {
              'Authorization': `Basic ${Buffer.from((paymongoKey || '') + ':').toString('base64')}`,
              'Content-Type': 'application/json',
            },
          }
        );

        const checkoutSession = checkoutResponse.data.data;

        // Update order with PayMongo checkout session data
        await orderRef.update({
          paymongo: {
            checkoutSessionId: checkoutSession.id,
            checkoutUrl: checkoutSession.attributes.checkout_url,
            paymentMethod: 'card', // Will be updated when payment is completed
            paymentStatus: 'pending',
            amount: totalAmount,
            currency: 'PHP',
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Checkout session created: ${checkoutSession.id} for order: ${orderRef.id}`);

        response.status(200).json({
          success: true,
          data: {
            order_id: orderRef.id,
            checkout_session: checkoutSession,
            total_amount: totalAmount,
            currency: 'PHP',
          },
        });

      } catch (error: any) {
        console.error('Error creating checkout session:', {
          error: error.message,
          userId,
          timestamp: new Date().toISOString()
        });
        
        // Determine appropriate error response
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
        } else if (error.message.includes('Too many requests')) {
          statusCode = 429;
          errorMessage = 'Too many requests. Please try again later.';
        }
        
        response.status(statusCode).json({
          success: false,
          error: errorMessage
        });
      }
    });
  });