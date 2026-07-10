/**
 * Books a Lalamove rider for a seller's Same Day Delivery portion of an order.
 *
 * Called by the seller when they mark the order ready-to-ship (NOT at checkout).
 * Quotations expire after 5 minutes, so this re-quotes fresh before placing the
 * order, then stores the Lalamove order info on the order doc (keyed by sellerId,
 * since an order may contain multiple sellers) and advances the order status.
 *
 * Idempotent: if the seller already has a booked Lalamove order, returns it.
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import * as admin from 'firebase-admin';
import { getQuotation, placeOrder } from './utils/lalamoveClient';
import { resolveBuyerStop, resolveSellerStop } from './utils/lalamoveAddress';
import { isMetroManila } from './utils/metroManila';

if (!admin.apps.length) {
  admin.initializeApp();
}

interface BookRequest {
  orderId: string;
  sellerId: string;
}

interface BookResponse {
  success: boolean;
  reason?: 'out_of_coverage' | 'not_serviceable' | 'already_booked' | 'error';
  lalamoveOrderId?: string;
  shareLink?: string;
  status?: string;
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

/** Returns the per-seller shipping mode recorded on the order. */
function sellerShippingMode(order: any, sellerId: string): string | undefined {
  const fromMap = order?.shippingInfo?.sellerShippingModes?.[sellerId];
  if (fromMap) return fromMap;
  const breakdown = (order?.sellerFeeBreakdowns || []).find((b: any) => b.sellerId === sellerId);
  return breakdown?.shippingMode;
}

export const bookLalamoveDelivery = onCall(
  {
    region: 'asia-southeast1',
    cors: true,
    enforceAppCheck: false,
    // Sensitive keys come from Secret Manager in prod, .env.local in the emulator.
    // LALAMOVE_ENV is non-secret config and lives in .env (process.env).
    secrets: ['LALAMOVE_API_KEY', 'LALAMOVE_API_SECRET', 'GOOGLE_MAPS_API_KEY'],
  },
  async (request: CallableRequest<BookRequest>): Promise<BookResponse> => {
    const uid = await verifyAuthToken(request.rawRequest.headers.authorization);

    const { orderId, sellerId } = request.data || ({} as BookRequest);
    if (!orderId || !sellerId) {
      throw new HttpsError('invalid-argument', 'orderId and sellerId are required');
    }
    // The caller must be the seller booking their own portion.
    if (uid !== sellerId) {
      throw new HttpsError('permission-denied', 'Only the seller may book delivery for their items');
    }

    const db = admin.firestore();
    const orderRef = db.collection('Order').doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }
    const order = orderSnap.data() as any;

    if (!Array.isArray(order.sellerIds) || !order.sellerIds.includes(sellerId)) {
      throw new HttpsError('permission-denied', 'Seller is not part of this order');
    }
    if (sellerShippingMode(order, sellerId) !== 'sameDay') {
      throw new HttpsError('failed-precondition', 'This order is not set for Same Day Delivery');
    }

    // Idempotency — return any existing booking for this seller.
    const existing = order?.lalamove?.[sellerId];
    if (existing?.orderId) {
      return {
        success: true,
        reason: 'already_booked',
        lalamoveOrderId: existing.orderId,
        shareLink: existing.shareLink,
        status: existing.status,
      };
    }

    const addressId = order?.shippingInfo?.addressId;
    if (!addressId) {
      throw new HttpsError('failed-precondition', 'Order has no shipping address');
    }

    try {
      const buyer = await resolveBuyerStop(db, order.userId, addressId);
      const seller = await resolveSellerStop(db, sellerId);

      if (!isMetroManila(buyer.city, buyer.state) || !isMetroManila(seller.city, seller.state)) {
        return { success: false, reason: 'out_of_coverage' };
      }

      // Fresh quote (the checkout quote has long expired).
      const quote = await getQuotation({
        pickup: { coordinates: seller.coordinates, address: seller.address },
        dropoff: { coordinates: buyer.coordinates, address: buyer.address },
        serviceType: 'MOTORCYCLE',
      });

      const pickupStopId = quote.stops?.[0]?.stopId;
      const dropoffStopId = quote.stops?.[1]?.stopId;
      if (!pickupStopId || !dropoffStopId) {
        throw new Error('Quotation did not return stop IDs');
      }

      const placed = await placeOrder({
        quotationId: quote.quotationId,
        sender: {
          stopId: pickupStopId,
          name: seller.name,
          phone: seller.phone,
        },
        recipients: [
          {
            stopId: dropoffStopId,
            name: buyer.name,
            phone: buyer.phone,
            remarks: order?.shippingInfo?.notes || undefined,
          },
        ],
        metadata: { dentpalOrderId: orderId, dentpalSellerId: sellerId },
      });

      const lalamoveRecord = {
        orderId: placed.orderId,
        quotationId: quote.quotationId,
        status: placed.status || 'ASSIGNING_DRIVER',
        shareLink: placed.shareLink || null,
        driverId: placed.driverId || null,
        priceBreakdown: placed.priceBreakdown || null,
        serviceType: 'MOTORCYCLE',
        bookedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await orderRef.update({
        [`lalamove.${sellerId}`]: lalamoveRecord,
        status: 'shipping',
        fulfillmentStage: 'in-transit',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'shipping',
          timestamp: new Date(),
          note: `Lalamove same-day rider booked (order ${placed.orderId})`,
        }),
      });

      // Lookup map so the webhook can resolve the Dentpal order from a
      // Lalamove orderId (the lalamove field is a dynamic-keyed map and is not
      // directly queryable).
      await db.collection('LalamoveOrder').doc(placed.orderId).set({
        dentpalOrderId: orderId,
        sellerId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info('Lalamove order booked', { orderId, sellerId, lalamoveOrderId: placed.orderId });

      return {
        success: true,
        lalamoveOrderId: placed.orderId,
        shareLink: placed.shareLink,
        status: placed.status,
      };
    } catch (error: any) {
      logger.error('Lalamove booking failed', { orderId, sellerId, message: error?.message });
      throw new HttpsError('internal', `Failed to book Lalamove delivery: ${error?.message || 'unknown error'}`);
    }
  },
);
