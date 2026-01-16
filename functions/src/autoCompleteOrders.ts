import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { deductStockForOrder } from './utils/stockDeductionHelper';

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
          stockDeducted: false, // Flag to track if stock has been deducted
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

      // After committing order status updates, deduct stock for each completed order
      logger.info(`Starting stock deduction for ${processedCount} completed orders`);
      
      for (const orderId of ordersToComplete) {
        try {
          // Re-fetch the order to get the items
          const orderDoc = await db.collection('Order').doc(orderId).get();
          const orderData = orderDoc.data();

          if (!orderData) {
            logger.warn(`Order ${orderId} not found for stock deduction`);
            continue;
          }

          // Check if stock has already been deducted to prevent double deduction
          if (orderData.stockDeducted === true) {
            logger.info(`Stock already deducted for order ${orderId}, skipping`);
            continue;
          }

          const orderItems = orderData.items || [];

          if (orderItems.length === 0) {
            logger.warn(`Order ${orderId} has no items, skipping stock deduction`);
            continue;
          }

          // Deduct stock for this order
          await deductStockForOrder(orderId, orderItems);

          // Mark order as stock deducted
          await db.collection('Order').doc(orderId).update({
            stockDeducted: true,
            stockDeductedAt: FieldValue.serverTimestamp(),
          });

        } catch (error) {
          logger.error(`Failed to deduct stock for order ${orderId}`, {
            error: error instanceof Error ? error.message : 'Unknown error',
            stack: error instanceof Error ? error.stack : undefined,
          });
          // Continue with other orders even if one fails
        }
      }

      logger.info(`Stock deduction process completed for ${processedCount} orders`);
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
