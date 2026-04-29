import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

const db = getFirestore();

/**
 * Scheduled function that runs every hour to auto-complete orders
 * that have been delivered for 7 days or longer
 */
export const autoCompleteOrders = onSchedule({
  schedule: 'every 1 hours',
  timeZone: 'Asia/Manila',
  region: 'asia-southeast1',
}, async (event) => {
  logger.info('Starting auto-complete orders job');

  try {
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - (7 * 24 * 60 * 60 * 1000));

    // Query orders that are in 'delivered' status
    const deliveredOrdersSnapshot = await db.collection('Order')
      .where('status', '==', 'delivered')
      .get();

    if (deliveredOrdersSnapshot.empty) {
      logger.info('No delivered orders found');
      return;
    }

    logger.info(`Found ${deliveredOrdersSnapshot.size} delivered orders to check`);

    const ordersToComplete: string[] = [];
    const batch = db.batch();
    let processedCount = 0;

    for (const doc of deliveredOrdersSnapshot.docs) {
      const orderData = doc.data();
      const orderId = doc.id;

      // Find delivery date from status history
      let deliveryDate: Date | null = null;

      if (orderData.statusHistory && Array.isArray(orderData.statusHistory)) {
        for (const statusUpdate of orderData.statusHistory) {
          if (statusUpdate.status === 'delivered') {
            // Handle both Timestamp and Date objects
            if (statusUpdate.timestamp?.toDate) {
              deliveryDate = statusUpdate.timestamp.toDate();
            } else if (statusUpdate.timestamp instanceof Date) {
              deliveryDate = statusUpdate.timestamp;
            } else if (typeof statusUpdate.timestamp === 'string') {
              deliveryDate = new Date(statusUpdate.timestamp);
            }
            break;
          }
        }
      }

      // If no delivery date in status history, use updatedAt
      if (!deliveryDate && orderData.updatedAt) {
        if (orderData.updatedAt.toDate) {
          deliveryDate = orderData.updatedAt.toDate();
        } else if (orderData.updatedAt instanceof Date) {
          deliveryDate = orderData.updatedAt;
        } else if (typeof orderData.updatedAt === 'string') {
          deliveryDate = new Date(orderData.updatedAt);
        }
      }

      // Check if delivery date is 7 days or older
      if (deliveryDate && deliveryDate <= sevenDaysAgo) {
        ordersToComplete.push(orderId);
        
        // Update order status to completed
        const orderRef = db.collection('Order').doc(orderId);
        batch.update(orderRef, {
          status: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
          statusHistory: FieldValue.arrayUnion({
            status: 'completed',
            timestamp: new Date(),
            note: 'Order automatically completed after 7 days',
          }),
          autoCompletedAt: FieldValue.serverTimestamp(),
        });

        processedCount++;

        logger.info(`Marked order ${orderId} as completed (delivered on ${deliveryDate.toISOString()})`);
      }
    }

    // Commit all updates in batch
    if (processedCount > 0) {
      await batch.commit();
      logger.info(`Successfully auto-completed ${processedCount} orders`, {
        ordersProcessed: processedCount,
        orderIds: ordersToComplete,
      });
    } else {
      logger.info('No orders eligible for auto-completion');
    }

  } catch (error) {
    logger.error('Error in auto-complete orders job', {
      error: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined,
    });
  }
});
