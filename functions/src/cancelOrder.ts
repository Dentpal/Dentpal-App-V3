import { onRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import * as admin from 'firebase-admin';
import cors = require('cors');
import axios from 'axios';

const db = admin.firestore();

// Configure CORS
const corsHandler = cors({
  origin: true,
  credentials: true
});

// PayMongo API configuration
const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';

interface CancelOrderRequest {
  orderId: string;
  reason: string;
}

interface CancelOrderResponse {
  success: boolean;
  message: string;
  orderId?: string;
  error?: string;
}

const verifyAuthToken = async (authorizationHeader: string | undefined): Promise<DecodedIdToken> => {
  if (!authorizationHeader) {
    throw new Error("Missing Authorization header");
  }

  const token = authorizationHeader.startsWith("Bearer ") 
    ? authorizationHeader.substring(7) 
    : authorizationHeader;

  if (!token) {
    throw new Error("Invalid Authorization header format");
  }

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    return decodedToken;
  } catch (error) {
    logger.error("Token verification failed", { error });
    throw new Error("Invalid or expired authentication token");
  }
};

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
  paymentId: string, // pay_xxx format - Required by PayMongo for refunds
  amount: number, 
  reason: string,
  secretKey: string
): Promise<{ success: boolean; refundId?: string; error?: string }> {
  try {
    logger.info('Creating PayMongo refund', { 
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
          payment_id: paymentId, // Must be payment ID (pay_xxx), not payment intent ID
          reason: 'requested_by_customer', // PayMongo requires one of their predefined values
          notes: `Order cancellation - Customer reason: ${reason}`
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
        refundId: refundId
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
 * Cancel an order and update its status with cancellation reason
 * Also processes refund if payment was made
 */
export const cancelOrder = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true,
    secrets: ['PAYMONGO_SECRET_KEY']
  },
  async (request, response) => {
    // Handle CORS
    corsHandler(request, response, async () => {
      try {
        logger.info('Cancel order request started', { 
          method: request.method,
          headers: request.headers,
          body: request.body
        });

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
        const decodedToken = await verifyAuthToken(authHeader);
        const userId = decodedToken.uid;

        // Parse request body
        const requestData = request.body as CancelOrderRequest;

        // Validate request data
        if (!requestData.orderId || !requestData.reason) {
          logger.error('Invalid request: missing orderId or reason', { body: request.body });
          response.status(400).json({
            success: false,
            error: 'Order ID and cancellation reason are required'
          });
          return;
        }

        const { orderId, reason } = requestData;

        // Get the order document
        const orderRef = db.collection('Order').doc(orderId);
        const orderDoc = await orderRef.get();

        if (!orderDoc.exists) {
          logger.error('Order not found', { orderId });
          response.status(404).json({
            success: false,
            error: 'Order not found'
          });
          return;
        }

        const orderData = orderDoc.data();
        
        // Verify that the order belongs to the authenticated user
        if (orderData?.userId !== userId) {
          logger.error('Unauthorized: user does not own this order', { 
            orderId, 
            userId, 
            orderUserId: orderData?.userId 
          });
          response.status(403).json({
            success: false,
            error: 'You do not have permission to cancel this order'
          });
          return;
        }

        // Check if the order can be cancelled (must be pending, confirmed, or to_ship)
        const currentStatus = orderData?.status;
        const cancellableStatuses = ['pending', 'confirmed', 'to_ship'];
        
        if (!cancellableStatuses.includes(currentStatus)) {
          logger.error('Order cannot be cancelled in current status', { 
            orderId, 
            currentStatus 
          });
          response.status(400).json({
            success: false,
            error: `Order cannot be cancelled. Current status: ${currentStatus}`
          });
          return;
        }

        // Check if payment was made and needs refund
        const paymongo = orderData?.paymongo;
        const paymentStatus = paymongo?.paymentStatus;
        const paymentId = paymongo?.paymentId; // pay_xxx - Required for refunds
        const paymentIntentId = paymongo?.paymentIntentId; // pi_xxx - For reference
        const orderTotal = orderData?.summary?.total || 0;
        
        let refundResult: { success: boolean; refundId?: string; error?: string } | null = null;

        // Process refund if payment was completed
        // PayMongo requires paymentId (pay_xxx) for refunds, not paymentIntentId
        if (paymentStatus === 'paid') {
          if (!paymentId) {
            logger.error('Cannot process refund: paymentId missing from order', { 
              orderId, 
              paymentIntentId,
              note: 'This happens when webhook did not capture payment ID. Order was paid but cannot be refunded automatically.'
            });
            response.status(500).json({
              success: false,
              error: 'Cannot process refund: Payment ID is missing. Please contact support for manual refund processing.',
              details: {
                orderId,
                paymentIntentId,
                note: 'This order requires manual refund processing through PayMongo dashboard'
              }
            });
            return;
          }

          logger.info('Payment was made, processing refund', { 
            orderId, 
            paymentId,
            paymentIntentId,
            amount: orderTotal
          });

          const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
          
          if (!PAYMONGO_SECRET_KEY) {
            logger.error('PayMongo secret key not configured');
            response.status(500).json({
              success: false,
              error: 'Payment refund service not configured'
            });
            return;
          }

          refundResult = await createPayMongoRefund(
            paymentId, // Use paymentId (pay_xxx) for refunds
            orderTotal,
            reason,
            PAYMONGO_SECRET_KEY
          );

          if (!refundResult.success) {
            logger.error('Refund failed, not cancelling order', { 
              orderId,
              paymentId,
              refundError: refundResult.error 
            });
            response.status(500).json({
              success: false,
              error: `Failed to process refund: ${refundResult.error}`
            });
            return;
          }

          logger.info('Refund processed successfully', { 
            orderId, 
            refundId: refundResult.refundId 
          });
        } else {
          logger.info('No payment to refund', { 
            orderId, 
            paymentStatus,
            hasPaymentId: !!paymentId,
            hasPaymentIntentId: !!paymentIntentId
          });
        }

        // Prepare the update data
        const timestamp = admin.firestore.Timestamp.now();
        const statusHistory = orderData?.statusHistory || [];
        
        // Add cancellation entry to status history
        const cancellationNote = refundResult?.refundId
          ? `Order cancelled: ${reason}. Refund ID: ${refundResult.refundId}`
          : `Order cancelled: ${reason}`;
        
        statusHistory.push({
          status: 'cancelled',
          timestamp: timestamp,
          note: cancellationNote
        });

        // Prepare update object
        const updateData: any = {
          status: 'cancelled',
          statusHistory: statusHistory,
          cancelledAt: timestamp,
          cancellationReason: reason,
          updatedAt: timestamp
        };

        // Add refund information if refund was processed
        if (refundResult?.refundId) {
          updateData.refundInfo = {
            refundId: refundResult.refundId,
            refundAmount: orderTotal,
            refundStatus: 'pending', // PayMongo refunds are initially pending
            refundRequestedAt: timestamp,
            refundReason: reason
          };
        }

        // Update the order document
        await orderRef.update(updateData);

        logger.info('Order cancelled successfully', { 
          orderId, 
          userId,
          reason,
          refundProcessed: !!refundResult?.refundId,
          refundId: refundResult?.refundId
        });

        const responseMessage = refundResult?.refundId
          ? 'Order cancelled successfully. Refund has been initiated and will be processed within 5-10 business days.'
          : 'Order cancelled successfully';

        response.status(200).json({
          success: true,
          message: responseMessage,
          orderId: orderId,
          refund: refundResult?.refundId ? {
            refundId: refundResult.refundId,
            amount: orderTotal,
            status: 'pending'
          } : null
        });

      } catch (error: any) {
        logger.error('Error cancelling order', { 
          error: error.message || error,
          orderId: request.body?.orderId
        });
        
        response.status(500).json({
          success: false,
          error: error.message || 'Failed to cancel order'
        });
      }
    });
  }
);
