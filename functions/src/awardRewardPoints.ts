import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp({
    databaseURL: 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app',
  });
}

const db = admin.firestore();

// One point per peso the buyer actually paid. Kept here so the tier ladder in
// the app (Silver at 25,000, Gold at 50,000, Platinum at 100,000) stays
// readable as pesos spent.
const POINTS_PER_PESO = 1;

const toNumber = (value: unknown): number | null => {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
};

/**
 * The peso amount an order earns points on: what the buyer paid, minus any
 * part of it that was itself settled with reward points.
 *
 * `summary.total` is the buyer-facing total written by both order creators
 * (post-discount subtotal + the shipping the buyer is charged); the older
 * `paymongo.amount` / `totalAmount` shapes are read as fallbacks so orders
 * written before the summary block still earn.
 *
 * `summary.rewardPointsDiscount` is the redemption hook: points are not earned
 * on value that came from points. Nothing writes that field yet — redemption
 * is still to be built — so today it is always 0.
 */
export const earnableAmountForOrder = (order: FirebaseFirestore.DocumentData): number => {
  const summary = (order.summary ?? {}) as FirebaseFirestore.DocumentData;
  const paid =
    toNumber(summary.total) ??
    toNumber(order.paymongo?.amount) ??
    toNumber(order.totalAmount) ??
    0;
  const paidWithPoints = toNumber(summary.rewardPointsDiscount) ?? 0;
  return Math.max(0, paid - Math.max(0, paidWithPoints));
};

/**
 * Which User document the points belong to.
 *
 * Assistants sign in with their own Auth account, so an order they place
 * carries their uid — but every points surface in the app reads the clinic's
 * document (`SubAccountSessionManager.getEffectiveUserId()`). Resolve the
 * parent here so a clinic's balance counts what its assistants ordered.
 */
const resolveEarningUserId = async (orderUserId: string): Promise<string> => {
  try {
    const lookup = await db.collection('SubAccountLookup').doc(orderUserId).get();
    const parentUserId = lookup.data()?.parentUserId;
    if (typeof parentUserId === 'string' && parentUserId.length > 0) {
      return parentUserId;
    }
  } catch (error) {
    logger.error('Failed to resolve sub account parent for reward points', {
      orderUserId,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
  return orderUserId;
};

/**
 * Credit the buyer with reward points once an order reaches 'completed'.
 *
 * A trigger rather than a step inside completeOrder, because an order reaches
 * 'completed' from three places — the buyer confirming receipt, the 7-day
 * auto-complete job, and the seller dashboard writing the status directly —
 * and all three should earn the same points.
 *
 * The award is written in the same transaction that stamps
 * `rewardPoints.awardedAt` on the order, so a retried or duplicated trigger
 * delivery cannot pay twice.
 */
export const awardRewardPointsOnOrderCompletion = onDocumentUpdated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // Only the transition into 'completed'.
    if (before.status === 'completed' || after.status !== 'completed') return;

    const orderId = event.params.orderId;
    const orderUserId = after.userId;

    if (typeof orderUserId !== 'string' || orderUserId.length === 0) {
      logger.error('Completed order has no userId; cannot award reward points', { orderId });
      return;
    }

    const points = Math.floor(earnableAmountForOrder(after) * POINTS_PER_PESO);
    const earningUserId = await resolveEarningUserId(orderUserId);

    const orderRef = db.collection('Order').doc(orderId);
    const userRef = db.collection('User').doc(earningUserId);

    try {
      const awarded = await db.runTransaction(async (transaction) => {
        const orderSnap = await transaction.get(orderRef);
        const orderData = orderSnap.data();
        if (!orderData) return false;

        // Someone else already paid this order out, or it moved on from
        // 'completed' between the trigger firing and this transaction.
        if (orderData.rewardPoints?.awardedAt) return false;
        if (orderData.status !== 'completed') return false;

        const userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          logger.error('No User document to credit reward points to', {
            orderId,
            orderUserId,
            earningUserId,
          });
          return false;
        }

        // Stamp the order either way: an order worth 0 points is settled, not
        // pending, and should not be retried.
        transaction.update(orderRef, {
          rewardPoints: {
            points,
            userId: earningUserId,
            awardedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        });

        if (points > 0) {
          transaction.update(userRef, {
            rewardPoints: admin.firestore.FieldValue.increment(points),
          });
        }

        return true;
      });

      if (awarded) {
        logger.info('Awarded reward points for completed order', {
          orderId,
          earningUserId,
          points,
        });
      } else {
        logger.info('Skipped reward points for completed order', {
          orderId,
          earningUserId,
          points,
        });
      }
    } catch (error) {
      logger.error('Failed to award reward points for completed order', {
        orderId,
        earningUserId,
        points,
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);
