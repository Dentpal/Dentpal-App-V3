import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';
import axios from 'axios';

const db = admin.firestore();

// PayMongo API configuration
const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';

/**
 * Create a refund via PayMongo API
 * 
 * PayMongo only accepts these specific reason values:
 * - duplicate
 * - fraudulent
 * - requested_by_customer
 * - others
 */
async function createPayMongoRefund(
  paymentId: string,
  amount: number,
  reason: string,
  secretKey: string
): Promise<{ success: boolean; refundId?: string; status?: string; error?: string }> {
  try {
    logger.info('Creating PayMongo refund (retry)', { 
      paymentId, 
      amount, 
      userReason: reason 
    });

    // PayMongo expects amount in cents
    const amountInCents = Math.round(amount * 100);

    // PayMongo only accepts specific reason codes
    // We use 'requested_by_customer' for all customer cancellations
    // The actual user reason goes in the notes field
    const refundData = {
      data: {
        attributes: {
          amount: amountInCents,
          payment_id: paymentId,
          reason: 'requested_by_customer', // PayMongo requires one of their predefined values
          notes: `Automated refund retry - Customer reason: ${reason}`
        }
      }
    };

    const response = await axios.post(
      `${PAYMONGO_BASE_URL}/refunds`,
      refundData,
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Basic ${Buffer.from(secretKey + ':').toString('base64')}`
        },
        timeout: 30000
      }
    );

    if (response.status === 200 || response.status === 201) {
      const refundId = response.data?.data?.id;
      const refundStatus = response.data?.data?.attributes?.status;
      
      logger.info('PayMongo refund created successfully', { 
        refundId, 
        refundStatus,
        paymentId 
      });

      return {
        success: true,
        refundId: refundId,
        status: refundStatus
      };
    } else {
      logger.error('PayMongo refund failed', { 
        status: response.status,
        data: response.data
      });
      
      return {
        success: false,
        error: `Refund failed with status ${response.status}`
      };
    }
  } catch (error: any) {
    logger.error('Error creating PayMongo refund', { 
      error: error.message,
      response: error.response?.data,
      paymentId
    });

    return {
      success: false,
      error: error.response?.data?.errors?.[0]?.detail || error.message || 'Failed to create refund'
    };
  }
}

/**
 * Scheduled function that runs every 3 hours to retry refunds for cancelled orders
 * This handles the race condition where an order is cancelled before the payment webhook updates the status
 */
export const retryPendingRefunds = onSchedule(
  {
    schedule: 'every 3 hours',
    timeZone: 'Asia/Manila',
    region: 'asia-southeast1',
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MiB',
    timeoutSeconds: 300
  },
  async (event) => {
    try {
      logger.info('Starting retry pending refunds job');

      const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
      
      if (!PAYMONGO_SECRET_KEY) {
        logger.error('PayMongo secret key not configured');
        return;
      }

      // Find cancelled orders that:
      // 1. Have status = 'cancelled'
      // 2. Have paymongo.paymentStatus = 'paid'
      // 3. Do NOT have refundInfo.refundId (no refund was processed)
      // 4. cancelledAt is within the last 7 days (to avoid processing old orders)
      // 5. refundRetryCount is less than 10 (to prevent infinite retries)

      const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
      );

      const ordersSnapshot = await db.collection('Order')
        .where('status', '==', 'cancelled')
        .where('paymongo.paymentStatus', '==', 'paid')
        .where('cancelledAt', '>=', sevenDaysAgo)
        .get();

      logger.info('Found cancelled orders with paid status', { 
        count: ordersSnapshot.size 
      });

      if (ordersSnapshot.empty) {
        logger.info('No cancelled orders with paid status found');
        return;
      }

      let processedCount = 0;
      let successCount = 0;
      let skippedCount = 0;
      let failedCount = 0;

      for (const orderDoc of ordersSnapshot.docs) {
        const orderData = orderDoc.data();
        const orderId = orderDoc.id;

        // Skip if refund already exists
        if (orderData.refundInfo?.refundId) {
          logger.info('Order already has refund, skipping', { 
            orderId,
            refundId: orderData.refundInfo.refundId 
          });
          skippedCount++;
          continue;
        }

        // Skip if retry count exceeded
        const retryCount = orderData.refundRetryCount || 0;
        if (retryCount >= 10) {
          logger.warn('Order exceeded max retry attempts', { 
            orderId,
            retryCount 
          });
          skippedCount++;
          continue;
        }

        // Check if paymentId exists
        const paymentId = orderData.paymongo?.paymentId;
        if (!paymentId) {
          logger.warn('Order missing paymentId, cannot process refund', { 
            orderId,
            paymentIntentId: orderData.paymongo?.paymentIntentId,
            note: 'This is an older order format before we started storing paymentId'
          });
          
          // Mark as unable to refund using atomic update
          const existingRefundInfo = orderData.refundInfo || {};
          await orderDoc.ref.update({
            refundInfo: {
              ...existingRefundInfo,
              error: 'Missing paymentId - order created before dual ID storage was implemented',
              cannotRefund: true,
              checkedAt: admin.firestore.Timestamp.now()
            }
          });
          
          skippedCount++;
          continue;
        }

        processedCount++;
        
        logger.info('Processing refund for cancelled order', { 
          orderId,
          paymentId,
          cancellationReason: orderData.cancellationReason,
          orderTotal: orderData.summary?.total,
          retryAttempt: retryCount + 1
        });

        // Attempt to create refund
        const refundResult = await createPayMongoRefund(
          paymentId,
          orderData.summary?.total || 0,
          orderData.cancellationReason || 'Order cancelled',
          PAYMONGO_SECRET_KEY
        );

        const timestamp = admin.firestore.Timestamp.now();

        if (refundResult.success && refundResult.refundId) {
          // Get existing refundInfo and merge with new data
          const existingRefundInfo = orderData.refundInfo || {};
          const updatedRefundInfo = {
            ...existingRefundInfo,
            refundId: refundResult.refundId,
            refundAmount: orderData.summary?.total || 0,
            refundStatus: refundResult.status || 'pending',
            refundRequestedAt: timestamp,
            refundReason: orderData.cancellationReason || 'Order cancelled',
            processedBy: 'automated_retry'
          };

          // Update order with atomic refundInfo update
          await orderDoc.ref.update({
            refundInfo: updatedRefundInfo,
            refundRetryCount: retryCount + 1,
            refundRetryLastAttempt: timestamp,
            updatedAt: timestamp,
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: 'cancelled',
              timestamp: timestamp,
              note: `Refund processed (automated retry): ${refundResult.refundId}`
            })
          });

          logger.info('Refund processed successfully', { 
            orderId,
            refundId: refundResult.refundId,
            retryAttempt: retryCount + 1
          });

          successCount++;
        } else {
          // Update retry count and last error
          await orderDoc.ref.update({
            refundRetryCount: retryCount + 1,
            refundRetryLastAttempt: timestamp,
            refundRetryLastError: refundResult.error || 'Unknown error',
            updatedAt: timestamp
          });

          logger.error('Failed to process refund', { 
            orderId,
            error: refundResult.error,
            retryAttempt: retryCount + 1
          });

          failedCount++;
        }

        // Add a small delay between API calls to avoid rate limiting
        await new Promise(resolve => setTimeout(resolve, 1000));
      }

      logger.info('Retry pending refunds job completed', {
        totalFound: ordersSnapshot.size,
        processed: processedCount,
        successful: successCount,
        failed: failedCount,
        skipped: skippedCount
      });

    } catch (error: any) {
      logger.error('Error in retry pending refunds job', { 
        error: error.message || error 
      });
      throw error;
    }
  }
);
