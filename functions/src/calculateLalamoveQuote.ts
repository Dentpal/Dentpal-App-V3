/**
 * Same Day Delivery quote (Lalamove MOTORCYCLE, Metro Manila only).
 *
 * Called from the checkout page when the buyer selects "Same Day Delivery" for a
 * seller. Returns a price + quotationId the UI displays as the buyer-paid
 * shipping cost. The quote is informational only — the order is actually booked
 * later (with a fresh quote) when the seller marks it ready-to-ship.
 *
 * Mirrors calculateJRSShipping (region, auth via verifyIdToken).
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import * as admin from 'firebase-admin';
import { getQuotation } from './utils/lalamoveClient';
import { resolveBuyerStop, resolveSellerStop } from './utils/lalamoveAddress';
import { isMetroManila } from './utils/metroManila';

if (!admin.apps.length) {
  admin.initializeApp();
}

interface LalamoveQuoteRequest {
  sellerId: string;
  addressId: string;
}

interface LalamoveQuoteResponse {
  success: boolean;
  reason?: 'out_of_coverage' | 'not_serviceable' | 'error';
  total?: number;
  currency?: string;
  quotationId?: string;
  expiresAt?: string;
  distance?: { value: string; unit: string };
}

async function verifyAuthToken(authorizationHeader: string | undefined): Promise<string> {
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
    const decoded = await getAuth().verifyIdToken(token);
    return decoded.uid;
  } catch (error) {
    logger.error('Token verification failed', { error });
    throw new HttpsError('unauthenticated', 'Invalid or expired authentication token');
  }
}

export const calculateLalamoveQuote = onCall(
  {
    region: 'asia-southeast1',
    cors: true,
    enforceAppCheck: false,
    // Sensitive keys come from Secret Manager in prod, .env.local in the emulator.
    // LALAMOVE_ENV is non-secret config and lives in .env (process.env).
    secrets: ['LALAMOVE_API_KEY', 'LALAMOVE_API_SECRET', 'GOOGLE_MAPS_API_KEY'],
  },
  async (request: CallableRequest<LalamoveQuoteRequest>): Promise<LalamoveQuoteResponse> => {
    const uid = await verifyAuthToken(request.rawRequest.headers.authorization);

    const { sellerId, addressId } = request.data || ({} as LalamoveQuoteRequest);
    if (!sellerId || !addressId) {
      throw new HttpsError('invalid-argument', 'sellerId and addressId are required');
    }

    const db = admin.firestore();

    try {
      // Resolve both stops (coordinates + coverage info). Buyer first so an
      // invalid address fails fast.
      const buyer = await resolveBuyerStop(db, uid, addressId);
      const seller = await resolveSellerStop(db, sellerId);

      // Metro Manila gating — both ends must be in NCR.
      if (!isMetroManila(buyer.city, buyer.state) || !isMetroManila(seller.city, seller.state)) {
        logger.info('Same-day quote rejected: out of coverage', {
          buyer: { city: buyer.city, state: buyer.state },
          seller: { city: seller.city, state: seller.state },
        });
        return { success: false, reason: 'out_of_coverage' };
      }

      const quote = await getQuotation({
        pickup: { coordinates: seller.coordinates, address: seller.address },
        dropoff: { coordinates: buyer.coordinates, address: buyer.address },
        serviceType: 'MOTORCYCLE',
      });

      const total = parseFloat(quote.priceBreakdown?.total ?? '0');
      return {
        success: true,
        total: Number.isFinite(total) ? total : 0,
        currency: quote.priceBreakdown?.currency || 'PHP',
        quotationId: quote.quotationId,
        expiresAt: quote.expiresAt,
        distance: quote.distance,
      };
    } catch (error: any) {
      logger.error('Lalamove quote failed', { sellerId, message: error?.message });
      // Surface a graceful "not serviceable" so the UI can hide the option
      // rather than blocking checkout.
      return { success: false, reason: 'not_serviceable' };
    }
  },
);
