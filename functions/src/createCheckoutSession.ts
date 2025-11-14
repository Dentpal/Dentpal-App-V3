import { onRequest, Request, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import axios from 'axios';
import cors = require('cors');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Configure Firestore to ignore undefined values
db.settings({
  ignoreUndefinedProperties: true
});

// Rate limiting store (in-memory for demo, use Redis in production)
const rateLimitStore = new Map<string, { count: number; resetTime: number }>();

// Security headers middleware
function setSecurityHeaders(response: any): void {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('X-XSS-Protection', '1; mode=block');
  response.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
}

// Rate limiting function
function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const windowMs = 60000; // 1 minute
  const maxRequests = 5;
  
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
interface JRSShippingRequest {
  requestType: 'getrate';
  apiShippingRequest: {
    express: boolean;
    insurance: boolean;
    valuation: boolean;
    codAmountToCollect: number;
    shipperAddressLine1: string;
    recipientAddressLine1: string;
    shipmentItems: Array<{
      declaredValue: number;
      length: number;
      width: number;
      height: number;
      weight: number;
    }>;
  };
}

// Helper function to call JRS shipping API
async function calculateJRSShippingCost(
  sellerAddress: string,
  recipientAddress: string,
  orderItems: any[],
  jrsApiKey?: string,
  jrsApiUrl?: string
): Promise<number> {
  const DEFAULT_SHIPPING_COST = 50;

  try {
    if (!jrsApiKey || !jrsApiUrl) {
      console.warn('JRS API configuration missing, using default shipping cost');
      return DEFAULT_SHIPPING_COST;
    }

    // Format addresses
    const shipperAddress = sellerAddress.includes(',') ? sellerAddress : `${sellerAddress}, Metro Manila`;
    const recipientFormattedAddress = recipientAddress.includes(',') ? recipientAddress : `${recipientAddress}, Metro Manila`;

    // Convert order items to shipment items
    const shipmentItems = [];
    for (const item of orderItems) {
      for (let i = 0; i < item.quantity; i++) {
        shipmentItems.push({
          declaredValue: item.price,
          length: 10, // Default dimensions in cm
          width: 10,
          height: 5,
          weight: 100 // Default weight in grams
        });
      }
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

    console.log('Calling JRS API for shipping calculation:', {
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
        console.log(`✅ JRS shipping cost calculated: ₱${shippingCost}`);
        return shippingCost;
      } else {
        console.warn('JRS API returned invalid shipping cost, using default');
        return DEFAULT_SHIPPING_COST;
      }
    } else {
      console.warn(`JRS API returned status ${response.status}, using default shipping cost`);
      return DEFAULT_SHIPPING_COST;
    }

  } catch (error: any) {
    console.error('Failed to calculate JRS shipping cost:', {
      error: error.message,
      status: error.response?.status,
      data: error.response?.data
    });
    return DEFAULT_SHIPPING_COST;
  }
}

// Helper function to extract shipping cost from JRS API response
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
    
    console.warn('Could not extract shipping cost from JRS response:', responseData);
    return 0;
    
  } catch (error) {
    console.error('Error extracting shipping cost from JRS response:', error);
    return 0;
  }
}

// ====================================
// PAYMONGO CHECKOUT SESSION FUNCTION
// ====================================

export const createCheckoutSession = onRequest(
  {
    secrets: ['PAYMONGO_SECRET_KEY', 'PAYMONGO_PUBLIC_KEY', 'JRS_API_KEY', 'JRS_SHIPPING_API_URL'],
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
        const JRS_API_URL_SECRET = process.env.JRS_SHIPPING_API_URL;

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

        console.log(`🛒 Creating checkout session for user ${userId} with ${cartItemIds.length} cart items`);
        
        // Get user's cart items with validation
        const cartPromises = cartItemIds.map(async (cartItemId: string) => {
          const cartDoc = await db
            .collection('User')
            .doc(userId!)
            .collection('Cart')
            .doc(cartItemId)
            .get();

          if (!cartDoc.exists) {
            console.error(`❌ Cart item ${cartItemId} not found`);
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
            } else {
              console.error(`❌ Variation ${cartItem.variationId} not found for product ${cartItem.productId}`);
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
          };
        });

        const orderItems = await Promise.all(orderItemsPromises);

        // Calculate totals
        const subtotal = orderItems.reduce((sum, item) => sum + item.total, 0);
        
        // Calculate shipping cost using JRS API
        let shippingCost = 50; // Default fallback
        try {
          // Get seller address for shipping calculation
          const sellerAddresses = await Promise.all(
            [...new Set(orderItems.map(item => item.sellerId))].map(async (sellerId) => {
              const sellerDoc = await db.collection('User').doc(sellerId).get();
              const sellerData = sellerDoc.data();
              return sellerData?.address || 'Makati, Metro Manila'; // Default fallback
            })
          );
          
          // For simplicity, use the first seller's address
          // In production, you might need to handle multiple sellers differently
          const sellerAddress = sellerAddresses[0];
          const recipientAddress = `${shippingAddress?.city || 'Manila'}, ${shippingAddress?.state || 'Metro Manila'}`;
          
          console.log('Calculating shipping cost using JRS API:', {
            sellerAddress,
            recipientAddress,
            itemCount: orderItems.length
          });
          
          // Call the JRS shipping calculator
          shippingCost = await calculateJRSShippingCost(
            sellerAddress, 
            recipientAddress, 
            orderItems,
            JRS_API_KEY_SECRET,
            JRS_API_URL_SECRET || "https://jrs-express.azure-api.net/qa-online-shipping-getrate/ShippingRequestFunction"
          );
          
          console.log(`✅ Final shipping cost determined: ₱${shippingCost}`);
          
        } catch (shippingError) {
          console.error('Failed to calculate JRS shipping cost, using default:', { 
            error: shippingError instanceof Error ? shippingError.message : String(shippingError)
          });
          // Keep default shipping cost of 50
        }
        
        const totalAmount = subtotal + shippingCost;

        // Get unique seller IDs
        const sellerIds = [...new Set(orderItems.map(item => item.sellerId))];

        // Create order document
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
          })),
          summary: {
            subtotal: subtotal,
            shippingCost: shippingCost,
            taxAmount: 0,
            discountAmount: 0,
            total: totalAmount,
            totalItems: orderItems.reduce((sum, item) => sum + item.quantity, 0),
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

        // Add shipping as a line item
        if (shippingCost > 0) {
          lineItems.push({
            name: 'Shipping Fee',
            quantity: 1,
            amount: Math.round(shippingCost * 100),
            currency: 'PHP',
            description: 'Standard shipping',
            images: undefined,
          });
        }

        // Create Paymongo Checkout Session
        const checkoutSessionData = {
          data: {
            attributes: {
              description: `DentPal Order #${orderRef.id}`,
              line_items: lineItems,
              payment_method_types: paymentMethodTypes,
              success_url: successUrl || 'https://dentpal-store.web.app/order-success',
              cancel_url: cancelUrl || 'https://dentpal-store.web.app/checkout?cancelled=true',
              metadata: {
                order_id: orderRef.id,
                user_id: userId,
                seller_ids: sellerIds.join(','),
                cart_item_ids: cartItemIds.join(','),
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

        // Update order with checkout session ID and URL
        await orderRef.update({
          checkoutSessionId: checkoutSession.id,
          paymentInfo: {
            checkoutSessionId: checkoutSession.id,
            checkoutUrl: checkoutSession.attributes.checkout_url,
            method: 'card', // Will be updated when payment is completed
            status: 'pending',
            amount: totalAmount,
            currency: 'PHP',
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Checkout session created: ${checkoutSession.id} for order: ${orderRef.id}`);

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
        console.error('❌ Error creating checkout session:', {
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