/**
 * Lalamove webhook receiver (Same Day Delivery status updates).
 *
 * Registered once with Lalamove via `PATCH /v3/webhook`. Lalamove POSTs events
 * (ORDER_STATUS_CHANGED, DRIVER_ASSIGNED, POD_STATUS_CHANGED, ...). We resolve
 * the Dentpal order via the LalamoveOrder lookup map written at booking time and
 * update the order's lalamove.<sellerId> sub-record + top-level status. The
 * existing notifyBuyerOnOrderStatusChange Firestore trigger handles buyer
 * notifications off the status write.
 *
 * Must always return HTTP 200 (Lalamove requirement).
 */
import { onRequest } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

/** Map a Lalamove order status onto a Dentpal order status, when terminal. */
function mapToOrderStatus(lalamoveStatus: string): string | null {
  switch (lalamoveStatus) {
    case 'COMPLETED':
      return 'delivered';
    case 'CANCELED':
    case 'EXPIRED':
    case 'REJECTED':
      return 'failed_delivery';
    // ASSIGNING_DRIVER / ON_GOING / PICKED_UP stay under the umbrella 'shipping'.
    default:
      return null;
  }
}

export const lalamoveWebhook = onRequest(
  {
    region: 'asia-southeast1',
    memory: '256MiB',
  },
  async (req, res): Promise<void> => {
    // Acknowledge non-POST quickly.
    if (req.method !== 'POST') {
      res.status(200).send('ok');
      return;
    }

    try {
      const body = req.body || {};
      const eventType: string = body.eventType || body.type || 'UNKNOWN';
      const orderData = body?.data?.order || body?.data || {};
      const lalamoveOrderId: string | undefined = orderData.orderId || body?.data?.orderId;
      const newStatus: string | undefined = orderData.status;
      const driver = body?.data?.driver || orderData?.driver;

      if (!lalamoveOrderId) {
        logger.warn('Lalamove webhook missing orderId', { eventType });
        res.status(200).send('ok');
        return;
      }

      // Resolve the Dentpal order via the lookup map.
      const mapSnap = await db.collection('LalamoveOrder').doc(lalamoveOrderId).get();
      const mapping = mapSnap.data();
      // Fall back to metadata if the lookup is missing.
      const dentpalOrderId: string | undefined =
        mapping?.dentpalOrderId || orderData?.metadata?.dentpalOrderId;
      const sellerId: string | undefined =
        mapping?.sellerId || orderData?.metadata?.dentpalSellerId;

      if (!dentpalOrderId || !sellerId) {
        logger.warn('Lalamove webhook: could not resolve Dentpal order', {
          eventType,
          lalamoveOrderId,
        });
        res.status(200).send('ok');
        return;
      }

      const orderRef = db.collection('Order').doc(dentpalOrderId);
      const update: Record<string, any> = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (newStatus) {
        update[`lalamove.${sellerId}.status`] = newStatus;
      }
      if (driver) {
        update[`lalamove.${sellerId}.driver`] = {
          driverId: driver.driverId || null,
          name: driver.name || null,
          phone: driver.phone || null,
          plateNumber: driver.plateNumber || null,
          photo: driver.photo || null,
        };
        if (driver.driverId) update[`lalamove.${sellerId}.driverId`] = driver.driverId;
      }

      // Map terminal Lalamove states onto the order status (fires buyer notification).
      const mappedOrderStatus = newStatus ? mapToOrderStatus(newStatus) : null;
      if (mappedOrderStatus) {
        update.status = mappedOrderStatus;
        update.statusHistory = admin.firestore.FieldValue.arrayUnion({
          status: mappedOrderStatus,
          timestamp: new Date(),
          note: `Lalamove status: ${newStatus}`,
        });
        if (mappedOrderStatus === 'delivered') update.fulfillmentStage = 'delivered';
      }

      // Must be update(), not set({merge:true}): only update() interprets the
      // dotted keys above as nested field paths. set() would treat them as
      // literal top-level field names ("lalamove.<uid>.status") and the real
      // nested record would never change.
      await orderRef.update(update);
      logger.info('Lalamove webhook processed', {
        eventType,
        dentpalOrderId,
        sellerId,
        newStatus,
      });
    } catch (error: any) {
      // Never fail the webhook — log and 200 so Lalamove does not retry-storm.
      logger.error('Lalamove webhook error', { message: error?.message });
    }

    res.status(200).send('ok');
  },
);
