import { onRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { DecodedIdToken } from 'firebase-admin/lib/auth/token-verifier';
import * as admin from 'firebase-admin';
import cors = require('cors');

const db = admin.firestore();

// Configure CORS
const corsHandler = cors({
  origin: true,
  credentials: true
});

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
 * Cancel an order and update its status with cancellation reason
 */
export const cancelOrder = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true
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

        // Prepare the update data
        const timestamp = admin.firestore.Timestamp.now();
        const statusHistory = orderData?.statusHistory || [];
        
        // Add cancellation entry to status history
        statusHistory.push({
          status: 'cancelled',
          timestamp: timestamp,
          note: `Order cancelled: ${reason}`
        });

        // Update the order document
        await orderRef.update({
          status: 'cancelled',
          statusHistory: statusHistory,
          cancelledAt: timestamp,
          cancellationReason: reason,
          updatedAt: timestamp
        });

        logger.info('Order cancelled successfully', { 
          orderId, 
          userId,
          reason 
        });

        response.status(200).json({
          success: true,
          message: 'Order cancelled successfully',
          orderId: orderId
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
