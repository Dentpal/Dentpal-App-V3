import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

/**
 * Scheduled migration function to update all 'confirmed' orders to 'to_ship' status
 * 
 * This function runs automatically once a day to migrate any orders that are stuck
 * in 'confirmed' status to the new workflow where orders go directly to 'to_ship'.
 * 
 * Schedule: Runs daily at 2:00 AM Manila time
 * Timezone: Asia/Manila
 * 
 * This handles edge cases where:
 * - Webhook failed to update order status
 * - Orders were manually set to 'confirmed' status
 * - Legacy orders that need migration
 */
export const migrateConfirmedOrders = onSchedule(
  {
    schedule: '0 2 * * *', // Every day at 2:00 AM (cron format)
    timeZone: 'Asia/Manila',
    region: 'asia-southeast1',
    memory: '512MiB',
    timeoutSeconds: 540 // 9 minutes max
  },
  async (event) => {
    try {
      logger.info('Starting scheduled migration of confirmed orders to to_ship status');

      // Query all orders with 'confirmed' status
      const confirmedOrdersQuery = await db
        .collection('Order')
        .where('status', '==', 'confirmed')
        .get();

      if (confirmedOrdersQuery.empty) {
        logger.info('No confirmed orders found to migrate');
        return null;
      }

      const totalOrders = confirmedOrdersQuery.size;
      logger.info('Found confirmed orders to migrate', { count: totalOrders });

      // Process orders in batches (Firestore batch limit is 500 operations)
      const batchSize = 100;
      let migratedCount = 0;
      const migratedOrders: string[] = [];
      const errors: Array<{ orderId: string; error: string }> = [];

      for (let i = 0; i < confirmedOrdersQuery.docs.length; i += batchSize) {
        const batch = db.batch();
        const batchDocs = confirmedOrdersQuery.docs.slice(i, i + batchSize);
        
        batchDocs.forEach((doc) => {
          const orderId = doc.id;
          const orderData = doc.data();
          
          logger.debug('Migrating order', { 
            orderId, 
            currentStatus: orderData.status,
            currentFulfillmentStage: orderData.fulfillmentStage 
          });

          const orderRef = db.collection('Order').doc(orderId);
          
          // Update the order
          batch.update(orderRef, {
            status: 'to_ship',
            fulfillmentStage: 'to-pack',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: 'to_ship',
              timestamp: new Date(),
              note: 'Order confirmed and ready to be processed',
            }),
          });

          migratedOrders.push(orderId);
        });

        try {
          await batch.commit();
          migratedCount += batchDocs.length;
          logger.info('Batch migrated successfully', { 
            batchNumber: Math.floor(i / batchSize) + 1,
            ordersInBatch: batchDocs.length,
            totalMigrated: migratedCount
          });
        } catch (error) {
          logger.error('Error migrating batch', { 
            batchNumber: Math.floor(i / batchSize) + 1,
            error: error instanceof Error ? error.message : String(error)
          });
          
          // Track errors for this batch
          batchDocs.forEach(doc => {
            errors.push({
              orderId: doc.id,
              error: error instanceof Error ? error.message : String(error)
            });
          });
        }
      }

      logger.info('Scheduled migration completed', { 
        totalOrders,
        migratedCount,
        errorCount: errors.length,
        migratedOrderIds: migratedOrders,
        errors: errors.length > 0 ? errors : undefined
      });

      return null;

    } catch (error) {
      logger.error('Fatal error during scheduled migration', { 
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined
      });
      throw error;
    }
  });
