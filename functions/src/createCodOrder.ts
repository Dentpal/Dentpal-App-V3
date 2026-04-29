import { onRequest, Request, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import {
  calculateJRSShippingCostWithFallback,
  calculateMultiSellerBreakdown,
  calculatePaymentProcessingFee,
  calculatePlatformFee,
  determineProductName,
} from './utils/jrsShippingHelper';
import {
  validateAndApplyVoucher,
  validateAndApplyShippingVoucher,
  incrementVoucherUsage,
} from './utils/voucherHelper';
import { deductStockForOrder } from './utils/stockDeductionHelper';
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

function isGenericPackagingName(name?: string | null): boolean {
  if (!name) return true;
  return name.trim().toLowerCase() === 'general cargo';
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

        // Extract pre-calculated per-seller shipping costs from frontend (optional)
        const sellerShippingCosts: Record<string, number> =
          (request.body.seller_shipping_costs && typeof request.body.seller_shipping_costs === 'object')
            ? request.body.seller_shipping_costs
            : {};

        // Packaging names as determined by the JRS API on the frontend (optional)
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
        const sellerExpressShipping: Record<string, boolean> =
          (request.body.seller_express_shipping && typeof request.body.seller_express_shipping === 'object')
            ? request.body.seller_express_shipping
            : {};

        // Both modes' costs from the frontend, needed for partial-coverage math.
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

        // Selected discount and shipping vouchers per seller.
        const selectedDiscountVouchers: Record<string, { code: string; seller_id: string; discount_type: string } | null> =
          (request.body.selected_discount_vouchers && typeof request.body.selected_discount_vouchers === 'object')
            ? request.body.selected_discount_vouchers
            : {};
        const selectedShippingVouchers: Record<string, { code: string; seller_id: string; discount_type: string; shipping_option?: unknown } | null> =
          (request.body.selected_shipping_vouchers && typeof request.body.selected_shipping_vouchers === 'object')
            ? request.body.selected_shipping_vouchers
            : {};

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
            insuranceAndEvaluation: product?.insuranceAndEvaluation === true,
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
          platformFeePercentage?: number;
          packagingName?: string;
          // Discount voucher fields
          discountAmount: number;
          postDiscountCartValue: number;
          voucherCode?: string;
          voucherDocId?: string;
          // Shipping voucher fields
          shippingVoucherCode?: string;
          shippingVoucherDocId?: string;
          coversStandard: boolean;
          coversExpress: boolean;
          // Per-seller shipping mode and both modes' costs
          chosenMode: 'express' | 'standard';
          expressTotalCost: number;
          standardTotalCost: number;
          // Insurance & evaluation
          insuranceAndEvaluation: boolean;
          insuranceCost: number | null;
          evaluationCost: number | null;
        }
        
        const sellerShippingPromises: Promise<SellerShippingData>[] = Object.entries(itemsBySeller).map(async ([sellerId, sellerItems]) => {
          // Get seller address and name from User collection
          const sellerDoc = await db.collection('User').doc(sellerId).get();
          const sellerData = sellerDoc.data();
          const sellerAddress = `${sellerData?.address?.city || 'Makati'}, ${sellerData?.address?.state || 'Metro Manila'}`;
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

          // Validate discount + shipping vouchers in parallel.
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

          const chosenMode: 'express' | 'standard' =
            (sellerExpressShipping[sellerId] ?? true) ? 'express' : 'standard';
          const expressTotalCost = expressSellerTotalShippingCosts[sellerId]
            ?? expressSellerShippingCosts[sellerId]
            ?? 0;
          const standardTotalCost = standardSellerTotalShippingCosts[sellerId]
            ?? standardSellerShippingCosts[sellerId]
            ?? 0;

          console.log(`Seller ${sellerId} voucher: discount=₱${discountAmount}, postDiscount=₱${postDiscountCartValue}, shippingVoucher=${shippingVoucherResult.voucherCode || 'none'} (covers std=${shippingVoucherResult.coversStandard}, exp=${shippingVoucherResult.coversExpress}), chosenMode=${chosenMode}`);

          console.log(`Calculating shipping for seller ${sellerId}:`, {
            sellerAddress,
            sellerName,
            cartValue: sellerCartValue,
            itemCount: sellerItems.length
          });

          const shipmentItemsForName = sellerItems
            .filter(item => item.length && item.width && item.height && item.weight)
            .flatMap(item => {
              const qty = item.quantity ?? 1;
              return Array.from({ length: qty }, () => ({
                declaredValue: item.price,
                length: item.length!,
                width: item.width!,
                height: item.height!,
                weight: item.weight!,
              }));
            });
          const resolvedProductName = determineProductName(shipmentItemsForName);
          
          // Use the pre-calculated shipping cost provided by the frontend (from JRS API).
          // Fall back to 200 only if the frontend did not supply a cost for this seller.
          const shippingCost = (sellerShippingCosts[sellerId] !== undefined)
            ? sellerShippingCosts[sellerId]
            : 200;
          const providedPackaging = sellerPackagingSizes[sellerId] || undefined;
          const packagingName = isGenericPackagingName(providedPackaging)
            ? resolvedProductName
            : providedPackaging;

          console.log(`Seller ${sellerId} shipping cost: ₱${shippingCost} (${sellerShippingCosts[sellerId] !== undefined ? 'from frontend' : 'fallback'}), packaging: ${packagingName ?? 'unknown'}`);

          return {
            sellerId,
            sellerName,
            shippingCost,
            cartValue: sellerCartValue,
            isFallbackShipping: sellerShippingCosts[sellerId] === undefined,
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
            expressTotalCost: expressTotalCost || shippingCost,
            standardTotalCost: standardTotalCost || shippingCost,
            insuranceAndEvaluation: sellerInsuranceAndEvaluation,
            insuranceCost: sellerInsuranceCostsFromFrontend[sellerId] ?? null,
            evaluationCost: sellerEvaluationCostsFromFrontend[sellerId] ?? null,
          };
        });
        
        // Wait for all seller shipping calculations
        const sellerShippingData = await Promise.all(sellerShippingPromises);
        
        // Pass postDiscountCartValue as cartValue so the 10% shipping threshold
        // and platform fee use the discounted amount.
        const adjustedSellerData = sellerShippingData.map(s => ({
          ...s,
          cartValue: s.postDiscountCartValue,
        }));

        // Calculate multi-seller breakdown
        const multiSellerBreakdown = calculateMultiSellerBreakdown(adjustedSellerData, 'cash_on_delivery');

        // Post-process: apply shipping voucher coverage rules per seller.
        // COD has no payment processing fee, so recalc only platform fee + shipping.
        const round2 = (n: number) => Math.round(n * 100) / 100;
        const shippingCoverageTypes: Array<'none' | 'full' | 'partial_express'> = [];
        for (let i = 0; i < sellerShippingData.length; i++) {
          const sd = sellerShippingData[i];
          const breakdown = multiSellerBreakdown.sellerBreakdowns[i];
          const stdCost = sd.standardTotalCost ?? sd.shippingCost;
          const expCost = sd.expressTotalCost ?? sd.shippingCost;

          let coverage: 'none' | 'full' | 'partial_express' = 'none';
          let buyerCharge: number | null = null;
          let sellerCharge: number | null = null;
          let splitRule: 'buyer_pays_full' | 'seller_pays_full' | 'shipping_voucher_partial' | null = null;

          if (sd.chosenMode === 'express' && sd.coversExpress) {
            buyerCharge = 0;
            sellerCharge = round2(expCost);
            splitRule = 'seller_pays_full';
            coverage = 'full';
          } else if (sd.chosenMode === 'express' && sd.coversStandard) {
            const diff = round2(Math.max(0, expCost - stdCost));
            buyerCharge = diff;
            sellerCharge = round2(stdCost);
            splitRule = 'shipping_voucher_partial';
            coverage = 'partial_express';
          } else if (sd.chosenMode === 'standard' && sd.coversStandard) {
            buyerCharge = 0;
            sellerCharge = round2(stdCost);
            splitRule = 'seller_pays_full';
            coverage = 'full';
          }

          if (coverage !== 'none' && buyerCharge !== null && sellerCharge !== null && splitRule !== null) {
            breakdown.buyerShippingCharge = buyerCharge;
            breakdown.sellerShippingCharge = sellerCharge;
            breakdown.shippingSplitRule = splitRule;
            breakdown.totalChargedToBuyer = round2(breakdown.cartValue + buyerCharge);
            breakdown.totalSellerFees = round2(breakdown.platformFee + breakdown.sellerShippingCharge);
            breakdown.netPayoutToSeller = round2(
              breakdown.cartValue - breakdown.platformFee - breakdown.sellerShippingCharge,
            );
          }
          shippingCoverageTypes.push(coverage);
        }

        const shippingCost = multiSellerBreakdown.totalShippingCost;
        const buyerShippingCharge = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.buyerShippingCharge, 0);
        const sellerShippingCharge = multiSellerBreakdown.sellerBreakdowns.reduce((s, b) => s + b.sellerShippingCharge, 0);

        // Total discount across all sellers
        const totalDiscountAmount = sellerShippingData.reduce((s, d) => s + d.discountAmount, 0);
        const postDiscountSubtotal = subtotal - totalDiscountAmount;

        // Total insurance & evaluation fees across all sellers (COD always null, sum = 0)
        const totalInsuranceFee = sellerShippingData.reduce((s, d) => s + (d.insuranceCost ?? 0), 0);
        const totalEvaluationFee = sellerShippingData.reduce((s, d) => s + (d.evaluationCost ?? 0), 0);

        // Determine overall shipping split rule based on seller breakdowns
        const shippingSplitRules = multiSellerBreakdown.sellerBreakdowns.map(s => s.shippingSplitRule);
        const shippingSplitRule = shippingSplitRules.includes('seller_pays_full') ? 'seller_pays_full' :
                                  (shippingSplitRules.length > 1 ? 'per_seller' : shippingSplitRules[0] || 'buyer_pays_full');

        // Calculate fees (COD typically has no payment processing fee, but keep platform fee)
        const totalAmount = postDiscountSubtotal + buyerShippingCharge;
        const paymentProcessingFee = 0; // No processing fee for COD
        const platformFee = calculatePlatformFee(postDiscountSubtotal);
        const totalSellerFees = paymentProcessingFee + platformFee + sellerShippingCharge;
        const netPayoutToSeller = postDiscountSubtotal - totalSellerFees;

        // Derive overall packaging label for the order (join unique packaging names across sellers)
        const uniquePackagingNames = [...new Set(
          sellerShippingData.map(s => s.packagingName).filter(Boolean) as string[]
        )];
        const overallPackagingSize = uniquePackagingNames.length > 0 ? uniquePackagingNames.join(', ') : undefined;

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
            discountAmount: totalDiscountAmount,
            total: totalAmount,
            totalItems: orderItems.reduce((sum, item) => sum + item.quantity, 0),
            sellerShippingCharge: sellerShippingCharge,
            buyerShippingCharge: buyerShippingCharge,
            shippingSplitRule: shippingSplitRule,
            // Deprecated top-level mode flag — true if any seller is express. Per-seller
            // mode lives under sellerFeeBreakdowns[].shippingMode.
            isExpressDelivery: sellerShippingData.some(s => s.chosenMode === 'express'),
            usedFallbackShipping: false,
            fallbackShippingSellerCount: 0,
            packagingSize: overallPackagingSize,
          },
          fees: {
            paymentProcessingFee: paymentProcessingFee,
            platformFee: platformFee,
            insuranceFee: totalInsuranceFee,
            evaluationFee: totalEvaluationFee,
            totalSellerFees: totalSellerFees,
            paymentMethod: 'cash_on_delivery',
          },
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
            buyerShippingCharge: s.buyerShippingCharge,
            sellerShippingCharge: s.sellerShippingCharge,
            shippingSplitRule: s.shippingSplitRule,
            totalChargedToBuyer: s.totalChargedToBuyer,
            paymentProcessingFee: 0, // No processing fee for COD
            platformFee: s.platformFee,
            platformFeePercentage: s.platformFeePercentage,
            totalSellerFees: s.platformFee + s.sellerShippingCharge,
            netPayoutToSeller: s.cartValue - (s.platformFee + s.sellerShippingCharge),
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
          status: 'to_ship',
          fulfillmentStage: 'to-pack',
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
            },
            {
              status: 'to_ship',
              timestamp: new Date(),
              note: 'Order ready to be packed and shipped',
            },
          ],
          metadata: {
            cart_item_ids: cartItemIds,
            hasFragileItems: hasFragileItems,
            paymentMethod: 'cash_on_delivery',
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

        // Deduct stock immediately — COD orders are committed at creation.
        try {
          await deductStockForOrder(orderRef.id, orderItems);
          await orderRef.update({
            stockDeducted: true,
            stockDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (stockError: any) {
          console.error(`COD order ${orderRef.id}: stock deduction failed`, {
            error: stockError?.message || stockError,
          });
        }

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
