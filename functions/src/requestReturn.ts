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

// Return request window in days (orders can only be returned within this period after delivery)
const RETURN_WINDOW_DAYS = 7;

interface RequestReturnRequest {
  orderId: string;
  reason: string;
  customReason?: string;
  itemsToReturn?: string[]; // Optional: specific item IDs to return (for partial returns)
}

interface RequestReturnResponse {
  success: boolean;
  message: string;
  orderId?: string;
  returnRequestId?: string;
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
 * Get the delivery date from order status history or JRS shipping info
 */
function getDeliveryDate(order: any): Date | null {
  // First, try to get delivery date from JRS shipping info
  // This is the most accurate source as it comes directly from the courier
  const jrsDeliveryDate = getJRSDeliveryDate(order);
  if (jrsDeliveryDate) {
    logger.info('Using JRS delivery date', { deliveryDate: jrsDeliveryDate.toISOString() });
    return jrsDeliveryDate;
  }

  // Fallback: Check status history for when order was marked as delivered
  const statusHistory = order.statusHistory || [];
  
  // Find the status update when order was marked as delivered
  for (const status of statusHistory) {
    const statusValue = status.status?.toLowerCase();
    if (statusValue === 'delivered') {
      // Handle both Firestore Timestamp and ISO string
      if (status.timestamp?._seconds) {
        return new Date(status.timestamp._seconds * 1000);
      } else if (status.timestamp?.toDate) {
        return status.timestamp.toDate();
      } else if (typeof status.timestamp === 'string') {
        return new Date(status.timestamp);
      }
    }
  }
  
  // If no delivery date found in history, check updatedAt for delivered orders
  if (order.status === 'delivered') {
    if (order.updatedAt?._seconds) {
      return new Date(order.updatedAt._seconds * 1000);
    } else if (order.updatedAt?.toDate) {
      return order.updatedAt.toDate();
    }
  }
  
  return null;
}

/**
 * Extract delivery date from JRS shipping response
 * JRS provides CurrentDeliveryStatusDate when the package is delivered
 */
function getJRSDeliveryDate(order: any): Date | null {
  try {
    const jrsData = order.shippingInfo?.jrs;
    if (!jrsData) {
      return null;
    }

    // Check the JRS response for delivery status date
    const jrsResponse = jrsData.response?.ShippingRequestEntityDto;
    if (jrsResponse) {
      // Check if CurrentDeliveryStatus indicates delivery
      const deliveryStatus = jrsResponse.CurrentDeliveryStatus?.toLowerCase();
      const isDelivered = deliveryStatus && (
        deliveryStatus.includes('delivered') ||
        deliveryStatus.includes('claimed') ||
        deliveryStatus === 'delivered'
      );

      // Get the CurrentDeliveryStatusDate if available
      if (jrsResponse.CurrentDeliveryStatusDate) {
        const deliveryDate = new Date(jrsResponse.CurrentDeliveryStatusDate);
        if (!isNaN(deliveryDate.getTime())) {
          logger.info('Found JRS CurrentDeliveryStatusDate', { 
            deliveryDate: deliveryDate.toISOString(),
            deliveryStatus: jrsResponse.CurrentDeliveryStatus
          });
          return deliveryDate;
        }
      }

      // If status is delivered but no date, try other date fields
      if (isDelivered) {
        // Try PickupDate or other relevant dates as fallback
        const fallbackDates = [
          jrsResponse.PickupDate,
          jrsResponse.DateCreated,
        ];

        for (const dateStr of fallbackDates) {
          if (dateStr) {
            const date = new Date(dateStr);
            if (!isNaN(date.getTime())) {
              logger.info('Using JRS fallback date for delivery', { 
                date: date.toISOString(),
                source: 'fallback'
              });
              return date;
            }
          }
        }
      }
    }

    // Also check if there's a deliveredAt field in jrs data
    if (jrsData.deliveredAt) {
      if (jrsData.deliveredAt._seconds) {
        return new Date(jrsData.deliveredAt._seconds * 1000);
      } else if (jrsData.deliveredAt.toDate) {
        return jrsData.deliveredAt.toDate();
      } else if (typeof jrsData.deliveredAt === 'string') {
        const date = new Date(jrsData.deliveredAt);
        if (!isNaN(date.getTime())) {
          return date;
        }
      }
    }

    return null;
  } catch (error) {
    logger.error('Error extracting JRS delivery date', { error });
    return null;
  }
}

/**
 * Check if the order is within the return window
 */
function isWithinReturnWindow(deliveryDate: Date): boolean {
  const now = new Date();
  const diffTime = Math.abs(now.getTime() - deliveryDate.getTime());
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  
  return diffDays <= RETURN_WINDOW_DAYS;
}

/**
 * Request a return for a delivered order
 * Validates that:
 * 1. Order exists and belongs to the user
 * 2. Order status is 'delivered'
 * 3. Order was delivered within the last 7 days
 */
export const requestReturn = onRequest(
  { 
    region: 'asia-southeast1',
    cors: true
  },
  async (request, response) => {
    // Handle CORS
    corsHandler(request, response, async () => {
      let decodedToken: DecodedIdToken | null = null;
      try {
        logger.info('Return request started', { 
          method: request.method,
          orderId: request.body?.orderId
        });

        // Only allow POST requests
        if (request.method !== 'POST') {
          response.status(405).json({
            success: false,
            error: 'Method not allowed. Use POST.'
          } as RequestReturnResponse);
          return;
        }

        // Verify authentication
        const authHeader = request.headers.authorization;
        decodedToken = await verifyAuthToken(authHeader);
        const userId = decodedToken.uid;

        // Parse request body
        const requestData = request.body as RequestReturnRequest;

        // Validate request data
        if (!requestData.orderId) {
          logger.error('Invalid request: missing orderId', { body: request.body });
          response.status(400).json({
            success: false,
            error: 'Order ID is required'
          } as RequestReturnResponse);
          return;
        }

        if (!requestData.reason) {
          logger.error('Invalid request: missing reason', { body: request.body });
          response.status(400).json({
            success: false,
            error: 'Return reason is required'
          } as RequestReturnResponse);
          return;
        }

        const { orderId, reason, customReason, itemsToReturn } = requestData;

        // Fetch the order
        const orderRef = db.collection('Order').doc(orderId);
        const orderDoc = await orderRef.get();

        if (!orderDoc.exists) {
          logger.error('Order not found', { orderId });
          response.status(404).json({
            success: false,
            error: 'Order not found'
          } as RequestReturnResponse);
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
            error: 'You do not have permission to request a return for this order'
          } as RequestReturnResponse);
          return;
        }

        // Check if order status is 'delivered'
        const currentStatus = orderData?.status;
        if (currentStatus !== 'delivered') {
          logger.error('Order is not delivered, cannot request return', { 
            orderId, 
            currentStatus 
          });
          response.status(400).json({
            success: false,
            error: `Only delivered orders can be returned. Current status: ${currentStatus}`
          } as RequestReturnResponse);
          return;
        }

        // Get delivery date and check if within return window
        const deliveryDate = getDeliveryDate(orderData);
        
        if (!deliveryDate) {
          logger.error('Could not determine delivery date', { orderId });
          response.status(400).json({
            success: false,
            error: 'Could not determine when the order was delivered. Please contact support.'
          } as RequestReturnResponse);
          return;
        }

        if (!isWithinReturnWindow(deliveryDate)) {
          const daysSinceDelivery = Math.ceil(
            Math.abs(new Date().getTime() - deliveryDate.getTime()) / (1000 * 60 * 60 * 24)
          );
          
          logger.error('Order is outside return window', { 
            orderId, 
            deliveryDate: deliveryDate.toISOString(),
            daysSinceDelivery,
            returnWindowDays: RETURN_WINDOW_DAYS
          });
          
          response.status(400).json({
            success: false,
            error: `Return window has expired. Orders can only be returned within ${RETURN_WINDOW_DAYS} days of delivery. This order was delivered ${daysSinceDelivery} days ago.`
          } as RequestReturnResponse);
          return;
        }

        // Check if a return has already been requested
        if (currentStatus === 'return_requested' || 
            currentStatus === 'return_approved' || 
            currentStatus === 'returned' ||
            currentStatus === 'refunded') {
          logger.error('Return already requested or processed', { 
            orderId, 
            currentStatus 
          });
          response.status(400).json({
            success: false,
            error: 'A return has already been requested or processed for this order'
          } as RequestReturnResponse);
          return;
        }

        // Build return note
        const returnNote = customReason && customReason.trim().length > 0
          ? `${reason}: ${customReason}`
          : reason;

        // Create return request record
        const returnRequest = {
          orderId: orderId,
          userId: userId,
          reason: reason,
          customReason: customReason || null,
          itemsToReturn: itemsToReturn || null, // null means all items
          status: 'pending', // pending, approved, rejected, completed
          requestedAt: admin.firestore.FieldValue.serverTimestamp(),
          deliveryDate: admin.firestore.Timestamp.fromDate(deliveryDate),
          orderTotal: orderData?.summary?.total || 0,
          items: orderData?.items || [],
        };

        // Use a transaction to update order and create return request
        const returnRequestRef = db.collection('ReturnRequest').doc();
        
        await db.runTransaction(async (transaction) => {
          // Create return request document
          transaction.set(returnRequestRef, returnRequest);
          
          // Update order status to return_requested
          // Note: Use regular Date for timestamp in array elements (serverTimestamp not allowed in arrays)
          const statusUpdate = {
            status: 'return_requested',
            timestamp: new Date(),
            note: `Return requested: ${returnNote}`,
            updatedBy: userId
          };
          
          transaction.update(orderRef, {
            status: 'return_requested',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusHistory: admin.firestore.FieldValue.arrayUnion(statusUpdate),
            returnRequestId: returnRequestRef.id
          });
        });

        logger.info('Return request created successfully', { 
          orderId, 
          returnRequestId: returnRequestRef.id,
          userId,
          reason: returnNote
        });

        response.status(200).json({
          success: true,
          message: 'Return request submitted successfully. Our team will review your request and get back to you within 1-2 business days.',
          orderId: orderId,
          returnRequestId: returnRequestRef.id
        } as RequestReturnResponse);

      } catch (error: any) {
        logger.error('Error processing return request', { 
          error: error.message,
          errorStack: error.stack,
          errorName: error.name,
          fullError: error,
          orderId: request.body?.orderId,
          userId: decodedToken?.uid
        });

        if (error.message?.includes('authentication') || error.message?.includes('Authorization')) {
          response.status(401).json({
            success: false,
            error: error.message
          } as RequestReturnResponse);
          return;
        }

        response.status(500).json({
          success: false,
          message: 'An error occurred while processing your return request. Please try again later.',
          error: error.message // Include actual error details
        } as RequestReturnResponse);
      }
    });
  }
);
