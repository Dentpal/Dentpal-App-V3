import { onRequest, Request, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import axios from 'axios';
import {
  calculateJRSShippingCostWithFallback,
  DEFAULT_FALLBACK_SHIPPING_COST,
  calculateMultiSellerBreakdown,
  applyNewFeeModel,
  determineProductName,
} from './utils/jrsShippingHelper';
import {
  validateAndApplyVoucher,
  validateAndApplyShippingVoucher,
  incrementVoucherUsage,
} from './utils/voucherHelper';
import { isWithinSameDayWindow } from './utils/sameDayWindow';
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

function isGenericPackagingName(name?: string | null): boolean {
  if (!name) return true;
  return name.trim().toLowerCase() === 'general cargo';
}

function validatePaymentMethods(methods: any): string[] {
  if (!Array.isArray(methods)) {
    throw new Error('Payment methods must be an array');
  }
  
  const validMethods = ['card', 'gcash'];
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
    body.payment_method_types || ['card', 'gcash']
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
    'https://dentpal.shop',
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

/**
 * Format seller address to "City, Province" format for JRS API
 * Handles both object format {city, state} and string format
 */
function formatSellerAddress(address: any): string {
  const defaultAddress = 'Makati, Metro Manila';
  
  if (!address) {
    return defaultAddress;
  }
  
  // Handle object format: {city: "Quezon City", state: "Metro Manila"}
  if (typeof address === 'object' && address !== null) {
    const city = address.city || address.City || '';
    const state = address.state || address.State || address.province || address.Province || 'Metro Manila';
    
    if (city) {
      return `${city}, ${state}`;
    }
    
    // Try to extract from other possible fields
    if (address.addressLine1 || address.address_line_1) {
      const addressLine = address.addressLine1 || address.address_line_1;
      return typeof addressLine === 'string' ? addressLine : defaultAddress;
    }
    
    return defaultAddress;
  }
  
  // Handle string format
  if (typeof address === 'string') {
    const cleanAddress = address.trim();
    
    if (!cleanAddress) {
      return defaultAddress;
    }
    
    // If address doesn't contain a comma, add Metro Manila as default province
    if (!cleanAddress.includes(',')) {
      return `${cleanAddress}, Metro Manila`;
    }
    
    return cleanAddress;
  }
  
  return defaultAddress;
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

        // Extract pre-calculated per-seller shipping costs from frontend (optional).
        // When provided, the per-seller JRS API call is skipped to avoid a duplicate
        // calculation and ensure the order total matches what the user saw on-screen.
        const sellerShippingCosts: Record<string, number> =
          (request.body.seller_shipping_costs && typeof request.body.seller_shipping_costs === 'object')
            ? request.body.seller_shipping_costs
            : {};

        // Packaging names as determined by the JRS API on the frontend (optional).
        // Used when the backend skips its own JRS call (seller_shipping_costs provided).
        const sellerPackagingSizes: Record<string, string> =
          (request.body.seller_packaging_sizes && typeof request.body.seller_packaging_sizes === 'object')
            ? request.body.seller_packaging_sizes
            : {};

        // Per-seller insurance & evaluation costs from the frontend JRS call.
        const sellerInsuranceCostsFromFrontend: Record<string, number> =
          (request.body.seller_insurance_costs && typeof request.body.seller_insurance_costs === 'object')
            ? request.body.seller_insurance_costs
            : {};
        const sellerEvaluationCostsFromFrontend: Record<string, number> =
          (request.body.seller_evaluation_costs && typeof request.body.seller_evaluation_costs === 'object')
            ? request.body.seller_evaluation_costs
            : {};

        // Per-seller shipping mode chosen on the checkout page (true = express).
        // Replaces the old global `is_express` so each seller's mode can be locked
        // independently by its shipping voucher.
        const sellerExpressShipping: Record<string, boolean> =
          (request.body.seller_express_shipping && typeof request.body.seller_express_shipping === 'object')
            ? request.body.seller_express_shipping
            : {};

        // Per-seller pickup selection. When true the buyer picks up in store and
        // no shipping is calculated / charged for that seller.
        const sellerPickupSelected: Record<string, boolean> =
          (request.body.seller_pickup_selected && typeof request.body.seller_pickup_selected === 'object')
            ? request.body.seller_pickup_selected
            : {};

        // Per-seller Same Day Delivery (Lalamove) selection. When true the
        // shipping cost is the buyer-paid Lalamove quote; JRS and vouchers are
        // skipped for that seller.
        const sellerSameDaySelected: Record<string, boolean> =
          (request.body.seller_same_day_selected && typeof request.body.seller_same_day_selected === 'object')
            ? request.body.seller_same_day_selected
            : {};

        // Both modes' costs from the frontend, needed for partial-coverage math
        // (voucher covers standard but user picks express).
        const expressSellerShippingCosts: Record<string, number> =
          (request.body.express_seller_shipping_costs && typeof request.body.express_seller_shipping_costs === 'object')
            ? request.body.express_seller_shipping_costs
            : {};
        const standardSellerShippingCosts: Record<string, number> =
          (request.body.standard_seller_shipping_costs && typeof request.body.standard_seller_shipping_costs === 'object')
            ? request.body.standard_seller_shipping_costs
            : {};
        const expressSellerTotalShippingCosts: Record<string, number> =
          (request.body.express_seller_total_shipping_costs && typeof request.body.express_seller_total_shipping_costs === 'object')
            ? request.body.express_seller_total_shipping_costs
            : {};
        const standardSellerTotalShippingCosts: Record<string, number> =
          (request.body.standard_seller_total_shipping_costs && typeof request.body.standard_seller_total_shipping_costs === 'object')
            ? request.body.standard_seller_total_shipping_costs
            : {};

        // Selected discount and shipping vouchers per seller (sent from frontend for
        // server-side validation).
        const selectedDiscountVouchers: Record<string, { code: string; seller_id: string; discount_type: string } | null> =
          (request.body.selected_discount_vouchers && typeof request.body.selected_discount_vouchers === 'object')
            ? request.body.selected_discount_vouchers
            : {};
        const selectedShippingVouchers: Record<string, { code: string; seller_id: string; discount_type: string; shipping_option?: unknown } | null> =
          (request.body.selected_shipping_vouchers && typeof request.body.selected_shipping_vouchers === 'object')
            ? request.body.selected_shipping_vouchers
            : {};

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
            insuranceAndEvaluation: product?.insuranceAndEvaluation === true,
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
          isFallbackShipping: boolean;
          shippingError?: string;
          platformFeePercentage?: number;
          packagingName?: string;
          // Voucher fields (discount)
          discountAmount: number;
          postDiscountCartValue: number;
          voucherCode?: string;
          voucherDocId?: string;
          // Voucher fields (shipping)
          shippingVoucherCode?: string;
          shippingVoucherDocId?: string;
          coversStandard: boolean;
          coversExpress: boolean;
          // Per-seller shipping mode and both modes' costs (for partial-coverage math)
          chosenMode: 'express' | 'standard' | 'pickup' | 'sameDay';
          expressTotalCost: number;
          standardTotalCost: number;
          // Insurance & evaluation
          insuranceAndEvaluation: boolean;
          insuranceCost: number | null;
          evaluationCost: number | null;
        }
        
        // Guard: Same Day (Lalamove) orders must be placed within each seller's
        // configured ordering window (days + hours, PH time). Fail fast before
        // the shipping calc so a client can't submit a same-day order off-hours.
        const sameDaySellerIds = Object.keys(sellerSameDaySelected).filter(
          (id) => sellerSameDaySelected[id] === true,
        );
        for (const sellerId of sameDaySellerIds) {
          const scheduleSnap = await db.collection('Seller').doc(sellerId).get();
          const schedule = scheduleSnap.data()?.checkoutOptions?.sameDaySchedule;
          if (!isWithinSameDayWindow(schedule)) {
            response.status(400).json({
              success: false,
              error:
                'Same Day Delivery is outside its ordering hours for one of your sellers. Please choose another delivery option.',
            });
            return;
          }
        }

        const sellerShippingPromises: Promise<SellerShippingData>[] = Object.entries(itemsBySeller).map(async ([sellerId, sellerItems]) => {
          // Get seller address and name from User collection
          const sellerDoc = await db.collection('User').doc(sellerId).get();
          const sellerData = sellerDoc.data();
          // Format seller address - handle both object {city, state} and string formats
          const sellerAddress = formatSellerAddress(sellerData?.address);
          const sellerName = sellerData?.displayName || sellerItems[0]?.sellerName || 'Unknown Seller';
          
          // Get custom platform fee percentage from Seller collection
          const sellerProfileDoc = await db.collection('Seller').doc(sellerId).get();
          const sellerProfileData = sellerProfileDoc.data();
          const platformFeePercentage = sellerProfileData?.Platform_fee_percentage;
          if (platformFeePercentage !== undefined) {
            console.log(`Seller ${sellerId} has custom platform fee: ${platformFeePercentage}%`);
          }
          
          // Calculate cart value for this seller's items
          const sellerCartValue = sellerItems.reduce((sum, item) => sum + item.total, 0);

          // Determine if any item from this seller requires insurance & evaluation
          const sellerInsuranceAndEvaluation = (sellerItems as any[]).some(item => item.insuranceAndEvaluation === true);

          // Validate discount + shipping vouchers in parallel (separate slots).
          const [voucherResult, shippingVoucherResult] = await Promise.all([
            validateAndApplyVoucher(
              sellerId,
              selectedDiscountVouchers[sellerId] || null,
              sellerCartValue,
              db,
            ),
            validateAndApplyShippingVoucher(
              sellerId,
              selectedShippingVouchers[sellerId] || null,
              sellerCartValue,
              db,
            ),
          ]);
          const discountAmount = voucherResult.discountAmount;
          const postDiscountCartValue = sellerCartValue - discountAmount;

          // Pickup short-circuit: skip JRS entirely; no shipping cost / vouchers apply.
          if (sellerPickupSelected[sellerId] === true) {
            console.log(`Seller ${sellerId} is pickup — skipping JRS shipping calculation`);
            return {
              sellerId,
              sellerName,
              shippingCost: 0,
              cartValue: sellerCartValue,
              isFallbackShipping: false,
              platformFeePercentage,
              packagingName: undefined,
              discountAmount,
              postDiscountCartValue,
              voucherCode: voucherResult.voucherCode || undefined,
              voucherDocId: voucherResult.voucherDocId || undefined,
              shippingVoucherCode: undefined,
              shippingVoucherDocId: undefined,
              coversStandard: false,
              coversExpress: false,
              chosenMode: 'pickup' as const,
              expressTotalCost: 0,
              standardTotalCost: 0,
              insuranceAndEvaluation: false,
              insuranceCost: null,
              evaluationCost: null,
            };
          }

          // Same Day Delivery short-circuit: shipping cost is the buyer-paid
          // Lalamove quote supplied by the frontend. Skip JRS and vouchers — no
          // shipping voucher applies to same-day.
          if (sellerSameDaySelected[sellerId] === true) {
            const sameDayCost = sellerShippingCosts[sellerId] ?? 0;
            console.log(`Seller ${sellerId} is same-day (Lalamove) — buyer pays ₱${sameDayCost}`);
            return {
              sellerId,
              sellerName,
              shippingCost: sameDayCost,
              cartValue: sellerCartValue,
              isFallbackShipping: false,
              platformFeePercentage,
              packagingName: undefined,
              discountAmount,
              postDiscountCartValue,
              voucherCode: voucherResult.voucherCode || undefined,
              voucherDocId: voucherResult.voucherDocId || undefined,
              shippingVoucherCode: undefined,
              shippingVoucherDocId: undefined,
              coversStandard: false,
              coversExpress: false,
              chosenMode: 'sameDay' as const,
              expressTotalCost: sameDayCost,
              standardTotalCost: sameDayCost,
              insuranceAndEvaluation: false,
              insuranceCost: null,
              evaluationCost: null,
            };
          }

          const chosenMode: 'express' | 'standard' =
            (sellerExpressShipping[sellerId] ?? true) ? 'express' : 'standard';
          const expressTotalCost = expressSellerTotalShippingCosts[sellerId]
            ?? expressSellerShippingCosts[sellerId]
            ?? 0;
          const standardTotalCost = standardSellerTotalShippingCosts[sellerId]
            ?? standardSellerShippingCosts[sellerId]
            ?? 0;

          console.log(`Seller ${sellerId} voucher: discount=₱${discountAmount}, postDiscount=₱${postDiscountCartValue}, shippingVoucher=${shippingVoucherResult.voucherCode || 'none'} (covers std=${shippingVoucherResult.coversStandard}, exp=${shippingVoucherResult.coversExpress}), chosenMode=${chosenMode}`);

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

          // If no items have dimensions, use fallback shipping
          if (validItems.length === 0) {
            console.warn(`No items have dimensions for seller ${sellerId}, using fallback shipping cost of ₱${DEFAULT_FALLBACK_SHIPPING_COST}`);
            return {
              sellerId,
              sellerName,
              shippingCost: DEFAULT_FALLBACK_SHIPPING_COST,
              cartValue: sellerCartValue,
              isFallbackShipping: true,
              shippingError: 'No items have required dimensions for shipping calculation',
              platformFeePercentage,
              discountAmount,
              postDiscountCartValue,
              voucherCode: voucherResult.voucherCode || undefined,
              voucherDocId: voucherResult.voucherDocId || undefined,
              shippingVoucherCode: shippingVoucherResult.voucherCode || undefined,
              shippingVoucherDocId: shippingVoucherResult.voucherDocId || undefined,
              coversStandard: shippingVoucherResult.coversStandard,
              coversExpress: shippingVoucherResult.coversExpress,
              chosenMode,
              expressTotalCost: expressTotalCost || DEFAULT_FALLBACK_SHIPPING_COST,
              standardTotalCost: standardTotalCost || DEFAULT_FALLBACK_SHIPPING_COST,
              insuranceAndEvaluation: sellerInsuranceAndEvaluation,
              insuranceCost: null,
              evaluationCost: null,
            };
          }
          
          console.log(`Calculating shipping for seller ${sellerId}:`, {
            sellerAddress,
            sellerName,
            cartValue: sellerCartValue,
            itemCount: validItems.length,
            originalItemCount: sellerItems.length
          });
          
          // Observability only — preview which packaging rule would match for this
          // seller's shipment. The actual productName used in the JRS API request is
          // determined inside calculateJRSShippingCost, so this is not passed onward.
          // Items are expanded by quantity to match how calculateJRSShippingCost and
          // determineProductName process them (one ShipmentItem per physical unit).
          const shipmentItemsForLog: Array<{declaredValue: number; length: number; width: number; height: number; weight: number}> = [];
          for (const item of validItems) {
            const qty = (item as any).quantity ?? 1;
            for (let i = 0; i < qty; i++) {
              shipmentItemsForLog.push({
                declaredValue: (item as any).price,
                length: (item as any).length,
                width: (item as any).width,
                height: (item as any).height,
                weight: (item as any).weight
              });
            }
          }
          const resolvedProductName = determineProductName(shipmentItemsForLog);
          
          console.log(`📦 Seller ${sellerId} (${sellerName}) - JRS packaging: ${resolvedProductName ?? 'auto (API determines)'}`, {
            totalWeight: shipmentItemsForLog.reduce((sum: number, i: any) => sum + i.weight, 0),
            maxWidth: Math.max(...shipmentItemsForLog.map((i: any) => i.width)),
            maxLength: Math.max(...shipmentItemsForLog.map((i: any) => i.length)),
            totalHeight: shipmentItemsForLog.reduce((sum: number, i: any) => sum + i.height, 0),
            itemCount: shipmentItemsForLog.length
          });
          
          // If the frontend already calculated this seller's shipping cost, use it
          // directly and skip the redundant JRS API call.
          if (sellerShippingCosts[sellerId] !== undefined) {
            const providedCost = sellerShippingCosts[sellerId];
            const providedPackaging = sellerPackagingSizes[sellerId] || undefined;
            const providedInsurance = sellerInsuranceCostsFromFrontend[sellerId] ?? null;
            const providedEvaluation = sellerEvaluationCostsFromFrontend[sellerId] ?? null;
            const packagingName = isGenericPackagingName(providedPackaging)
              ? resolvedProductName
              : providedPackaging;
            console.log(`Seller ${sellerId} shipping cost: ₱${providedCost} (from frontend, JRS call skipped), packaging: ${providedPackaging ?? 'unknown'}, cart value: ₱${sellerCartValue}`);
            return {
              sellerId,
              sellerName,
              shippingCost: providedCost,
              cartValue: sellerCartValue,
              isFallbackShipping: false,
              platformFeePercentage,
              packagingName,
              discountAmount,
              postDiscountCartValue,
              voucherCode: voucherResult.voucherCode || undefined,
              voucherDocId: voucherResult.voucherDocId || undefined,
              shippingVoucherCode: shippingVoucherResult.voucherCode || undefined,
              shippingVoucherDocId: shippingVoucherResult.voucherDocId || undefined,
              coversStandard: shippingVoucherResult.coversStandard,
              coversExpress: shippingVoucherResult.coversExpress,
              chosenMode,
              expressTotalCost: expressTotalCost || providedCost,
              standardTotalCost: standardTotalCost || providedCost,
              insuranceAndEvaluation: sellerInsuranceAndEvaluation,
              insuranceCost: providedInsurance,
              evaluationCost: providedEvaluation,
            };
          }

          // Calculate shipping cost for this seller's items with fallback support
          // If JRS API fails (500 error, timeout, etc.), use fallback shipping cost
          const shippingResult = await calculateJRSShippingCostWithFallback(
            sellerAddress,
            recipientAddress,
            validItems,
            JRS_API_KEY_SECRET,
            JRS_GETRATE_API_URL,
            DEFAULT_FALLBACK_SHIPPING_COST,
            false,
            chosenMode === 'express',
            sellerInsuranceAndEvaluation,
            sellerInsuranceAndEvaluation
          );

          if (shippingResult.isFallback) {
            console.warn(`JRS API failed for seller ${sellerId}, using fallback shipping cost of ₱${shippingResult.shippingCost}. Error: ${shippingResult.error}`);
          } else {
            console.log(`Seller ${sellerId} shipping cost: ₱${shippingResult.shippingCost}, packaging: ${shippingResult.packagingName ?? 'unknown'}, cart value: ₱${sellerCartValue}`);
          }

          const packagingName = isGenericPackagingName(shippingResult.packagingName)
            ? resolvedProductName
            : shippingResult.packagingName;

          return {
            sellerId,
            sellerName,
            shippingCost: shippingResult.shippingCost,
            cartValue: sellerCartValue,
            isFallbackShipping: shippingResult.isFallback,
            shippingError: shippingResult.error,
            platformFeePercentage,
            packagingName,
            discountAmount,
            postDiscountCartValue,
            voucherCode: voucherResult.voucherCode || undefined,
            voucherDocId: voucherResult.voucherDocId || undefined,
            shippingVoucherCode: shippingVoucherResult.voucherCode || undefined,
            shippingVoucherDocId: shippingVoucherResult.voucherDocId || undefined,
            coversStandard: shippingVoucherResult.coversStandard,
            coversExpress: shippingVoucherResult.coversExpress,
            chosenMode,
            // Fallback path computed only the chosen mode; treat the other as same.
            expressTotalCost: expressTotalCost || shippingResult.shippingCost,
            standardTotalCost: standardTotalCost || shippingResult.shippingCost,
            insuranceAndEvaluation: sellerInsuranceAndEvaluation,
            insuranceCost: shippingResult.insuranceCost ?? null,
            evaluationCost: shippingResult.evaluationCost ?? null,
          };
        });
        
        // Wait for all seller shipping calculations
        const sellerShippingData = await Promise.all(sellerShippingPromises);
        shippingCost = sellerShippingData.reduce((total, seller) => total + seller.shippingCost, 0);
        
        // Check if any seller used fallback shipping
        const sellersWithFallback = sellerShippingData.filter(s => s.isFallbackShipping);
        if (sellersWithFallback.length > 0) {
          console.warn(`${sellersWithFallback.length} seller(s) used fallback shipping cost due to JRS API issues:`, 
            sellersWithFallback.map(s => ({ sellerId: s.sellerId, error: s.shippingError }))
          );
        }
        
        console.log(`Total shipping cost for all sellers: ₱${shippingCost} (${sellersWithFallback.length} using fallback)`);
        
        // Validate final shipping cost - with fallback, this should always be valid
        if (!shippingCost || shippingCost <= 0) {
          // This should never happen now with fallback, but just in case
          console.error('Invalid total shipping cost even with fallback, using default');
          shippingCost = DEFAULT_FALLBACK_SHIPPING_COST * Object.keys(itemsBySeller).length;
        }
        
        // Calculate PER-SELLER fee breakdowns using the multi-seller function
        // This ensures each seller is charged based on THEIR cart value, not the total order
        //
        // Fee Calculation Rules:
        // - Shipping Split: If seller's shipping > 10% of seller's cart value → Buyer pays 100%
        //                   If seller's shipping ≤ 10% of seller's cart value → Seller pays 100%
        // - Payment Fee: Based on buyer's total for this seller (cart + buyer's shipping portion)
        // - Platform Fee: 8.88% of this seller's cart value
        // - Net Payout: Cart Value - Payment Fee - Platform Fee - Seller's Shipping
        // Fees (platformFee, paymentProcessingFee) are intentionally computed on the original
        // pre-discount cartValue so vouchers do not zero out DentPal's fees.
        // totalChargedToBuyer and seller payout are corrected to postDiscountCartValue below.
        const defaultPaymentMethod = paymentMethodTypes[0] || 'card';
        const multiSellerBreakdown = calculateMultiSellerBreakdown(sellerShippingData, defaultPaymentMethod);

        // Post-process: apply shipping voucher coverage rules per seller.
        // Coverage outcomes:
        //   - 'full'             : buyer pays 0; seller pays the chosen-mode total
        //   - 'partial_express'  : voucher covers 'standard' but user picked 'express';
        //                          seller pays standardTotal, buyer pays (expressTotal - standardTotal)
        //   - 'none'             : leave whatever calculateMultiSellerBreakdown decided
        const shippingCoverageTypes: Array<'none' | 'full' | 'partial_express'> = [];
        for (let i = 0; i < sellerShippingData.length; i++) {
          const sd = sellerShippingData[i];
          const breakdown = multiSellerBreakdown.sellerBreakdowns[i];

          // Pickup: no shipping → no voucher coverage to apply. Zero out shipping
          // fields and mark the split rule so downstream consumers know.
          if (sd.chosenMode === 'pickup') {
            breakdown.shippingCost = 0;
            breakdown.buyerShippingCharge = 0;
            breakdown.sellerShippingCharge = 0;
            breakdown.shippingSplitRule = 'pickup' as any;
            breakdown.totalChargedToBuyer = sd.postDiscountCartValue;
            shippingCoverageTypes.push('none');
            continue;
          }

          // Same Day Delivery: buyer always pays the full Lalamove fee; the
          // platform settles with Lalamove, so the seller bears no shipping
          // cost/VAT. No vouchers apply.
          if (sd.chosenMode === 'sameDay') {
            const fee = sd.shippingCost;
            breakdown.shippingCost = fee;
            breakdown.buyerShippingCharge = fee;
            breakdown.sellerShippingCharge = 0;
            breakdown.shippingSplitRule = 'buyer_pays_full';
            breakdown.totalChargedToBuyer = sd.postDiscountCartValue + fee;
            shippingCoverageTypes.push('none');
            continue;
          }

          const stdCost = sd.standardTotalCost ?? sd.shippingCost;
          const expCost = sd.expressTotalCost ?? sd.shippingCost;

          let coverage: 'none' | 'full' | 'partial_express' = 'none';
          let buyerCharge: number | null = null;
          let sellerCharge: number | null = null;
          let splitRule: 'buyer_pays_full' | 'seller_pays_full' | 'shipping_voucher_partial' | null = null;

          if (sd.chosenMode === 'express' && sd.coversExpress) {
            buyerCharge = 0;
            sellerCharge = expCost;
            splitRule = 'seller_pays_full';
            coverage = 'full';
          } else if (sd.chosenMode === 'express' && sd.coversStandard) {
            const diff = Math.max(0, expCost - stdCost);
            buyerCharge = diff;
            sellerCharge = stdCost;
            splitRule = 'shipping_voucher_partial';
            coverage = 'partial_express';
          } else if (sd.chosenMode === 'standard' && sd.coversStandard) {
            buyerCharge = 0;
            sellerCharge = stdCost;
            splitRule = 'seller_pays_full';
            coverage = 'full';
          }

          if (coverage !== 'none' && buyerCharge !== null && sellerCharge !== null && splitRule !== null) {
            breakdown.buyerShippingCharge = buyerCharge;
            breakdown.sellerShippingCharge = sellerCharge;
            breakdown.shippingSplitRule = splitRule;
            breakdown.totalChargedToBuyer = sd.postDiscountCartValue + buyerCharge;
          }
          shippingCoverageTypes.push(coverage);
        }

        // Apply the new gross-up fee model. Each seller-borne base (shipping,
        // paymongo fee, platform fee) is grossed up via base × 1.12 / (1 − rate)
        // so both 12% VAT and the seller's share of the PayMongo cut are absorbed.
        // sellerShippingCharge is redefined: shipping+VAT when seller_pays_full,
        // VAT-only when buyer_pays_full, sellerShipCharge_preVat + full shippingVat
        // when shipping_voucher_partial. Raw unrounded values.
        for (let i = 0; i < multiSellerBreakdown.sellerBreakdowns.length; i++) {
          const breakdown = multiSellerBreakdown.sellerBreakdowns[i];
          const sd = sellerShippingData[i];
          let actualShippingCost: number;
          if (sd.chosenMode === 'pickup' || sd.chosenMode === 'sameDay') {
            // Same-day is a pass-through Lalamove fee paid by the buyer; the
            // seller is not charged shipping VAT or commission on it.
            actualShippingCost = 0;
          } else if (sd.chosenMode === 'express') {
            actualShippingCost = sd.expressTotalCost ?? breakdown.shippingCost;
          } else {
            actualShippingCost = sd.standardTotalCost ?? breakdown.shippingCost;
          }
          const sameDayFee = sd.chosenMode === 'sameDay' ? breakdown.buyerShippingCharge : null;
          applyNewFeeModel(breakdown, {
            actualShippingCost,
            postDiscountCartValue: sd.postDiscountCartValue,
            paymentMethod: defaultPaymentMethod,
          });
          // applyNewFeeModel sets breakdown.shippingCost to actualShippingCost (0
          // for same-day); restore the buyer-facing fee for display/records.
          if (sameDayFee !== null) {
            breakdown.shippingCost = sameDayFee;
          }
        }

        // Recalculate totals from updated per-breakdown values
        const buyerShippingCharge = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.buyerShippingCharge, 0);
        const sellerShippingCharge = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.sellerShippingCharge, 0);
        const totalChargedToBuyer = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.totalChargedToBuyer, 0);
        const paymentProcessingFee = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.paymentProcessingFee, 0);
        const paymentProcessingFeeVat = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.paymentProcessingFeeVat, 0);
        const platformFee = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.platformFee, 0);
        const platformFeeVat = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.platformFeeVat, 0);
        const totalSellerFees = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.totalSellerFees, 0);
        const netPayoutToSeller = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.netPayoutToSeller, 0);
        const totalShippingVat = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.shippingVat, 0);
        const totalDentpalIncome = totalShippingVat + paymentProcessingFeeVat + platformFee + platformFeeVat;

        // Total discount across all sellers
        const totalDiscountAmount = sellerShippingData.reduce((s, d) => s + d.discountAmount, 0);

        // Total insurance & evaluation fees across all sellers (null-safe)
        const totalInsuranceFee = sellerShippingData.reduce((s, d) => s + (d.insuranceCost ?? 0), 0);
        const totalEvaluationFee = sellerShippingData.reduce((s, d) => s + (d.evaluationCost ?? 0), 0);

        // Log minimal breakdown info
        console.log(`Multi-Seller Breakdown: ${multiSellerBreakdown.sellerBreakdowns.length} seller(s), total charged: ₱${totalChargedToBuyer.toFixed(2)}, total discount: ₱${totalDiscountAmount.toFixed(2)}`);

        // Determine overall shipping split rule
        const uniqueRules = [...new Set(multiSellerBreakdown.sellerBreakdowns.map(s => s.shippingSplitRule))];
        const shippingSplitRule = uniqueRules.length === 1 ? uniqueRules[0] : 'per_seller';

        // Total amount to charge buyer
        const totalAmount = totalChargedToBuyer;

        // Get unique seller IDs
        const sellerIds = [...new Set(orderItems.map(item => item.sellerId))];

        // Check if any items are fragile
        const hasFragileItems = orderItems.some(item => item.isFragile);

        // Derive overall packaging label for the order (join unique packaging names across sellers)
        const uniquePackagingNames = [...new Set(
          sellerShippingData.map(s => s.packagingName).filter(Boolean) as string[]
        )];
        const overallPackagingSize = uniquePackagingNames.length > 0 ? uniquePackagingNames.join(', ') : undefined;

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
            total: item.total,
            variationId: item.variationId,
            sellerId: item.sellerId,
            sellerName: item.sellerName,
            length: item.length,
            width: item.width,
            height: item.height,
            weight: item.weight,
            isFragile: item.isFragile,
            insuranceAndEvaluation: item.insuranceAndEvaluation,
          })),
          summary: {
            subtotal: subtotal,
            shippingCost: shippingCost,
            taxAmount: 0,
            discountAmount: totalDiscountAmount,
            total: totalAmount,
            totalItems: orderItems.reduce((sum, item) => sum + item.quantity, 0),
            sellerShippingCharge: sellerShippingCharge,
            buyerShippingCharge: buyerShippingCharge,
            shippingSplitRule: shippingSplitRule,
            // Deprecated top-level mode flag — true if any seller is express. Per-seller
            // mode lives under sellerFeeBreakdowns[].shippingMode.
            isExpressDelivery: sellerShippingData.some(s => s.chosenMode === 'express'),
            usedFallbackShipping: sellersWithFallback.length > 0,
            fallbackShippingSellerCount: sellersWithFallback.length,
            packagingSize: overallPackagingSize,
            totalDentpalIncome: totalDentpalIncome,
          },
          fees: {
            paymentProcessingFee: paymentProcessingFee,
            platformFee: platformFee,
            insuranceFee: totalInsuranceFee,
            evaluationFee: totalEvaluationFee,
            totalSellerFees: totalSellerFees,
            paymentMethod: defaultPaymentMethod, // Will be updated when payment is completed
          },
          // Per-seller fee breakdowns for accurate payout calculation
          sellerFeeBreakdowns: multiSellerBreakdown.sellerBreakdowns.map((s, index) => ({
            sellerId: s.sellerId,
            sellerName: s.sellerName,
            cartValue: sellerShippingData[index].cartValue, // original pre-discount value
            postDiscountCartValue: sellerShippingData[index].postDiscountCartValue,
            discountAmount: sellerShippingData[index].discountAmount,
            voucherCode: sellerShippingData[index].voucherCode || null,
            shippingVoucherCode: sellerShippingData[index].shippingVoucherCode || null,
            shippingVoucherDocId: sellerShippingData[index].shippingVoucherDocId || null,
            shippingCoverageType: shippingCoverageTypes[index],
            shippingMode: sellerShippingData[index].chosenMode,
            freeShippingFromVoucher: shippingCoverageTypes[index] === 'full',
            partialShippingCoverage: shippingCoverageTypes[index] === 'partial_express',
            shippingCost: s.shippingCost,
            shippingVat: s.shippingVat,
            buyerShippingCharge: s.buyerShippingCharge,
            sellerShippingCharge: s.sellerShippingCharge,
            shippingSplitRule: s.shippingSplitRule,
            totalChargedToBuyer: s.totalChargedToBuyer,
            paymentProcessingFee: s.paymentProcessingFee,
            paymentProcessingFeeVat: s.paymentProcessingFeeVat,
            platformFee: s.platformFee,
            platformFeeVat: s.platformFeeVat,
            platformFeePercentage: s.platformFeePercentage,
            totalSellerFees: s.totalSellerFees,
            netPayoutToSeller: s.netPayoutToSeller,
            packagingSize: sellerShippingData[index].packagingName || null,
            hasInsuranceAndEvaluation: sellerShippingData[index].insuranceAndEvaluation,
            insuranceCost: sellerShippingData[index].insuranceCost,
            evaluationCost: sellerShippingData[index].evaluationCost,
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
            isExpress: sellerShippingData.some(s => s.chosenMode === 'express'),
            sellerShippingModes: Object.fromEntries(
              sellerShippingData.map(s => [s.sellerId, s.chosenMode]),
            ),
            packagingSize: overallPackagingSize,
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

        // Increment voucher usage counts (discount + shipping)
        const voucherDocIdsToIncrement: string[] = [];
        for (const seller of sellerShippingData) {
          if (seller.voucherDocId) voucherDocIdsToIncrement.push(seller.voucherDocId);
          if (seller.shippingVoucherDocId) voucherDocIdsToIncrement.push(seller.shippingVoucherDocId);
        }
        if (voucherDocIdsToIncrement.length > 0) {
          await incrementVoucherUsage(voucherDocIdsToIncrement, db);
          console.log(`Incremented usage for ${voucherDocIdsToIncrement.length} voucher(s)`);
        }

        // Build a discount ratio map per seller so item prices reflect the voucher discount.
        // PayMongo does not support negative line item amounts, so we proportionally reduce
        // each item's unit price instead.
        const sellerDiscountRatio: Record<string, number> = {};
        for (const seller of sellerShippingData) {
          if (seller.discountAmount > 0 && seller.cartValue > 0) {
            sellerDiscountRatio[seller.sellerId] = seller.postDiscountCartValue / seller.cartValue;
          } else {
            sellerDiscountRatio[seller.sellerId] = 1;
          }
        }

        // Prepare line items for Paymongo checkout (prices adjusted for voucher discounts)
        const lineItems = orderItems.map(item => {
          const ratio = sellerDiscountRatio[item.sellerId] ?? 1;
          const discountedPrice = item.price * ratio;
          return {
            name: item.productName,
            quantity: item.quantity,
            amount: Math.round(discountedPrice * 100), // Convert to centavos
            currency: 'PHP',
            description: `Product ID: ${item.productId}`,
            images: item.productImage ? [item.productImage] : undefined,
          };
        });

        // Add shipping as a line item (only buyer's portion)
        if (buyerShippingCharge > 0) {
          // Generate shipping description based on split rules
          let shippingDescription: string;
          if (shippingSplitRule === 'per_seller') {
            // Multi-seller with different rules
            shippingDescription = `Shipping for ${sellerIds.length} sellers. Your portion: ₱${buyerShippingCharge.toFixed(2)}`;
          } else if (shippingSplitRule === 'seller_pays_full') {
            shippingDescription = `Shipping covered by seller (Shipping ≤ 10% of cart value)`;
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
                phone: shippingAddress?.phoneNumber
                  ? shippingAddress.phoneNumber.replace(/^\+63/, '')
                  : undefined,
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