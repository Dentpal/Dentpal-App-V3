import { onRequest } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import cors from 'cors';
import { deductStockForOrder } from './utils/stockDeductionHelper';

const db = getFirestore();

// Configure CORS
const corsHandler = cors({
  origin: true,
  credentials: true
});

interface CompleteOrderRequest {
  orderId: string;
}

interface CompleteOrderResponse {
  success: boolean;
  message: string;
  orderId?: string;
  error?: string;
}

/**
 * Complete a delivered order manually (customer confirms receipt)
 * This will mark the order as completed and deduct stock
 */
export const completeOrder = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true
  },
  async (request, response) => {
    // Handle CORS
    corsHandler(request, response, async () => {
      try {
        logger.info('Complete order request started', { 
          method: request.method,
          orderId: request.body?.orderId
        });

        // Only allow POST requests
        if (request.method !== 'POST') {
          response.status(405).json({
            success: false,
            error: 'Method not allowed. Use POST.'
          } as CompleteOrderResponse);
          return;
        }

        // Verify authentication
        const authHeader = request.headers.authorization;
        if (!authHeader) {
          response.status(401).json({
            success: false,
            error: 'Missing Authorization header'
          } as CompleteOrderResponse);
          return;
        }

        const token = authHeader.startsWith('Bearer ') 
          ? authHeader.substring(7) 
          : authHeader;

        let decodedToken;
        try {
          decodedToken = await getAuth().verifyIdToken(token);
        } catch (error) {
          logger.error('Token verification failed', { error });
          response.status(401).json({
            success: false,
            error: 'Invalid or expired authentication token'
          } as CompleteOrderResponse);
          return;
        }

        const userId = decodedToken.uid;

        // Parse request body
        const requestData = request.body as CompleteOrderRequest;

        // Validate request data
        if (!requestData.orderId) {
          logger.error('Invalid request: missing orderId', { body: request.body });
          response.status(400).json({
            success: false,
            error: 'Order ID is required'
          } as CompleteOrderResponse);
          return;
        }

        const { orderId } = requestData;

        // Fetch the order
        const orderRef = db.collection('Order').doc(orderId);
        const orderDoc = await orderRef.get();

        if (!orderDoc.exists) {
          logger.error('Order not found', { orderId });
          response.status(404).json({
            success: false,
            error: 'Order not found'
          } as CompleteOrderResponse);
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
            error: 'You do not have permission to complete this order'
          } as CompleteOrderResponse);
          return;
        }

        // Check if order status is 'delivered'
        const currentStatus = orderData?.status;
        if (currentStatus !== 'delivered') {
          logger.error('Order is not delivered, cannot complete', { 
            orderId, 
            currentStatus 
          });
          response.status(400).json({
            success: false,
            error: `Only delivered orders can be completed. Current status: ${currentStatus}`
          } as CompleteOrderResponse);
          return;
        }

        // Check if stock has already been deducted
        if (orderData?.stockDeducted === true) {
          logger.warn(`Stock already deducted for order ${orderId}`);
          response.status(400).json({
            success: false,
            error: 'This order has already been completed'
          } as CompleteOrderResponse);
          return;
        }

        // Get order items
        const orderItems = orderData?.items || [];
        if (orderItems.length === 0) {
          logger.warn(`Order ${orderId} has no items`);
        }

        // Update order status to completed and deduct stock
        await orderRef.update({
          status: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
          statusHistory: FieldValue.arrayUnion({
            status: 'completed',
            timestamp: new Date(),
            note: 'Order manually completed by customer',
          }),
          manuallyCompletedAt: FieldValue.serverTimestamp(),
          stockDeducted: false, // Will be set to true after stock deduction
        });

        // Deduct stock for this order
        try {
          await deductStockForOrder(orderId, orderItems);

          // Mark order as stock deducted
          await orderRef.update({
            stockDeducted: true,
            stockDeductedAt: FieldValue.serverTimestamp(),
          });

          logger.info('Order completed successfully with stock deduction', { 
            orderId, 
            userId,
            itemCount: orderItems.length
          });

          response.status(200).json({
            success: true,
            message: 'Order completed successfully. Stock has been deducted.',
            orderId: orderId
          } as CompleteOrderResponse);

        } catch (stockError) {
          logger.error('Failed to deduct stock after completing order', { 
            orderId,
            error: stockError instanceof Error ? stockError.message : 'Unknown error',
          });

          // Order is already marked as completed, but stock deduction failed
          // Return success but with a warning
          response.status(200).json({
            success: true,
            message: 'Order completed, but some stock updates may have failed. Please contact support.',
            orderId: orderId
          } as CompleteOrderResponse);
        }

      } catch (error: any) {
        logger.error('Error completing order', { 
          error: error.message,
          errorStack: error.stack,
          orderId: request.body?.orderId
        });

        response.status(500).json({
          success: false,
          message: 'An error occurred while completing your order. Please try again later.',
          error: error.message
        } as CompleteOrderResponse);
      }
    });
  }
);
