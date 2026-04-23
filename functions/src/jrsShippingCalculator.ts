import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import * as admin from 'firebase-admin';
import {
  calculateJRSShippingCostWithFallback,
  DEFAULT_FALLBACK_SHIPPING_COST,
  determineProductName,
} from './utils/jrsShippingHelper';

if (!admin.apps.length) {
  admin.initializeApp();
}

interface CartItemData {
  productId: string;
  quantity: number;
  price: number;
  sellerId: string;
  weight?: number;
  length?: number;
  width?: number;
  height?: number;
}

interface CalculateShippingRequest {
  sellerAddress: string;
  recipientAddress: string;
  cartItems: CartItemData[];
  express?: boolean;
  insurance?: boolean;
  valuation?: boolean;
}

interface JRSShippingResponse {
  success: boolean;
  data: {
    shippingCost?: number;
    packagingSize?: string | null;
    insuranceCost?: number | null;
    evaluationCost?: number | null;
    isFallback?: boolean;
    fallbackError?: string | null;
  };
  error?: string;
}

function formatAddress(address: string): string {
  const clean = address.trim();
  if (!clean.includes(',')) return `${clean}, Metro Manila`;
  const [city, province] = clean.split(',').map(p => p.trim());
  return province ? `${city}, ${province}` : clean;
}

async function verifyAuthToken(authorizationHeader: string | undefined): Promise<void> {
  if (!authorizationHeader) {
    throw new HttpsError('unauthenticated', 'Missing Authorization header');
  }
  const token = authorizationHeader.startsWith('Bearer ')
    ? authorizationHeader.substring(7)
    : authorizationHeader;
  if (!token) {
    throw new HttpsError('unauthenticated', 'Invalid Authorization header format');
  }
  try {
    await getAuth().verifyIdToken(token);
  } catch (error) {
    logger.error('Token verification failed', { error });
    throw new HttpsError('unauthenticated', 'Invalid or expired authentication token');
  }
}

/**
 * Calculates JRS shipping cost for a single seller's cart items.
 *
 * The frontend calls this once per seller (see cart_service.dart), passing:
 * - express: user's delivery preference from the checkout page
 * - insurance/valuation: true only if any item in the seller group has
 *   product.insuranceAndEvaluation === true (checked on the frontend)
 */
export const calculateJRSShipping = onCall(
  {
    region: 'asia-southeast1',
    cors: true,
    enforceAppCheck: false,
    secrets: ['JRS_API_KEY', 'JRS_GETRATE_API_URL'],
  },
  async (request: CallableRequest<CalculateShippingRequest>): Promise<JRSShippingResponse> => {
    try {
      await verifyAuthToken(request.rawRequest.headers.authorization);

      const { sellerAddress, recipientAddress, cartItems } = request.data;
      const express = typeof request.data.express === 'boolean' ? request.data.express : true;
      const insurance = typeof request.data.insurance === 'boolean' ? request.data.insurance : false;
      const valuation = typeof request.data.valuation === 'boolean' ? request.data.valuation : false;

      if (!sellerAddress || !recipientAddress || !cartItems || cartItems.length === 0) {
        throw new HttpsError('invalid-argument', 'Missing required shipping data');
      }

      const formattedRecipient = formatAddress(recipientAddress);

      // Preview the locally-matched packaging rule for logging/response.
      // productName is NOT sent to JRS — the API picks the packaging itself.
      const shipmentItemsForName = cartItems
        .filter(i => i.length && i.width && i.height && i.weight)
        .flatMap(i => Array.from({ length: i.quantity }, () => ({
          declaredValue: i.price,
          length: i.length!,
          width: i.width!,
          height: i.height!,
          weight: i.weight!,
        })));
      const resolvedProductName = determineProductName(shipmentItemsForName);

      logger.info('JRS shipping calculation', {
        itemCount: cartItems.length,
        express,
        insurance,
        valuation,
        packaging: resolvedProductName ?? 'auto',
      });

      const result = await calculateJRSShippingCostWithFallback(
        sellerAddress,
        formattedRecipient,
        cartItems,
        process.env.JRS_API_KEY,
        process.env.JRS_GETRATE_API_URL,
        DEFAULT_FALLBACK_SHIPPING_COST,
        false,
        express,
        insurance,
        valuation,
      );

      if (result.isFallback) {
        logger.warn('JRS API failed, using fallback', {
          fallbackCost: result.shippingCost,
          error: result.error,
        });
      }

      // Prefer our local packaging rule; fall back to JRS-reported name.
      const packagingSize = resolvedProductName ?? result.packagingName ?? null;

      return {
        success: true,
        data: {
          shippingCost: result.shippingCost,
          packagingSize,
          insuranceCost: result.insuranceCost ?? null,
          evaluationCost: result.evaluationCost ?? null,
          isFallback: result.isFallback,
          fallbackError: result.error ?? null,
        },
      };
    } catch (error: any) {
      logger.error('Error calculating JRS shipping', error);
      if (error instanceof HttpsError) throw error;
      return {
        success: false,
        error: error.message || 'Failed to calculate shipping cost',
        data: { shippingCost: DEFAULT_FALLBACK_SHIPPING_COST, isFallback: true },
      };
    }
  },
);
