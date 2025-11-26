import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import cors = require('cors');
import * as logger from 'firebase-functions/logger';
import { 
  calculatePaymentProcessingFee, 
  calculatePlatformFee,
  calculateNetPayout
} from './utils/jrsShippingHelper';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// Rate limiting store (in-memory for demo, use Redis in production)
const rateLimitStore = new Map<string, { count: number; resetTime: number }>();

// Security headers middleware
function setSecurityHeaders(response: any): void {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('X-XSS-Protection', '1; mode=block');
  response.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
}

// Rate limiting function
function checkRateLimit(identifier: string): boolean {
  const now = Date.now();
  const windowMs = 60000; // 1 minute
  const maxRequests = 5;
  
  const userLimit = rateLimitStore.get(identifier);
  
  if (!userLimit || now > userLimit.resetTime) {
    // Reset window
    rateLimitStore.set(identifier, { count: 1, resetTime: now + windowMs });
    return true;
  }
  
  if (userLimit.count >= maxRequests) {
    return false; // Rate limit exceeded
  }
  
  userLimit.count++;
  return true;
}

// Configure CORS
const corsHandler = cors({ 
  origin: [
    'https://dentpal-store.web.app',
    'https://dentpal-store-sandbox-testing.web.app',
    'https://dentpal-161e5.web.app',
    'https://dentpal-161e5.firebaseapp.com',
    // Allow Paymongo webhook endpoints
    'https://api.paymongo.com',
    // Add localhost for development
    'http://localhost:1337',
    // Add common development ports
    'http://localhost:3000',
    'http://127.0.0.1:1337',
    // Add localhost for Flutter web development
    ...(process.env.NODE_ENV === 'development' || process.env.FUNCTIONS_EMULATOR === 'true' ? [
      'http://localhost:1337',
      'http://localhost:3000',
      'http://localhost:8080',
      'http://127.0.0.1:1337'
    ] : [])
  ],
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
  optionsSuccessStatus: 200 // For legacy browser support
});

// Helper function to verify that the order belongs to a valid user
async function verifyOrderUser(orderId: string, userId: string): Promise<boolean> {
  try {
    if (!userId || !orderId) {
      logger.warn('Missing user ID or order ID for verification', { orderId, userId });
      return false;
    }

    // Check if the user exists and is valid
    const userDoc = await db.collection('User').doc(userId).get();
    
    if (!userDoc.exists) {
      logger.warn('User not found during webhook processing', { userId, orderId });
      return false;
    }

    const userData = userDoc.data();
    
    // Additional user validation (you can customize this)
    if (userData?.status === 'disabled' || userData?.status === 'suspended') {
      logger.warn('User account is disabled/suspended', { userId, orderId });
      return false;
    }

    // Verify the order actually belongs to this user
    const orderDoc = await db.collection('Order').doc(orderId).get();
    
    if (!orderDoc.exists) {
      logger.warn('Order not found during user verification', { orderId, userId });
      return false;
    }

    const orderData = orderDoc.data();
    
    if (orderData?.userId !== userId) {
      logger.error('Order user ID mismatch - potential security issue', { 
        orderId, 
        expectedUserId: userId, 
        actualUserId: orderData?.userId 
      });
      return false;
    }

    logger.debug('Order user verification successful', { orderId, userId });
    return true;

  } catch (error) {
    logger.error('Error during order user verification', { 
      error: error instanceof Error ? error.message : String(error),
      orderId,
      userId
    });
    return false;
  }
}

// Helper function to handle successful checkout session payments
async function handleCheckoutSessionPaymentPaid(eventAttributes: any) {
  try {
    const orderId = eventAttributes.metadata?.order_id;
    const userId = eventAttributes.metadata?.user_id;
    const checkoutSessionId = eventAttributes.id;
    const paymentMethodUsed = eventAttributes.payment_method_used;
    const status = eventAttributes.status;
    
    logger.info('Processing payment event', { 
      sessionId: checkoutSessionId, 
      orderId, 
      status, 
      paymentMethod: paymentMethodUsed 
    });

    // Check if payment is actually completed
    if (status !== 'paid' && status !== 'active') {
      logger.info('Payment not completed yet', { status, orderId });
      return;
    }

    if (!orderId) {
      logger.error('No order ID found in webhook metadata');
      return;
    }

    if (!userId) {
      logger.error('No user ID found in webhook metadata', { orderId });
      return;
    }

    // SECURITY: Verify that the order belongs to a valid user
    const isValidUser = await verifyOrderUser(orderId, userId);
    if (!isValidUser) {
      logger.error('User verification failed for webhook payment', { 
        orderId, 
        userId,
        checkoutSessionId 
      });
      return; // Silently reject the webhook if user verification fails
    }

    logger.info('User verification successful, proceeding with payment processing', { 
      orderId, 
      userId 
    });

    // Update order status
    const orderRef = db.collection('Order').doc(orderId);
    const orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      logger.error('Order not found', { orderId });
      return;
    }

    const orderData = orderDoc.data();

    // Map payment method from Paymongo to our format
    let paymentMethod = 'card'; // default
    
    if (paymentMethodUsed) {
      switch (paymentMethodUsed.toLowerCase()) {
        case 'gcash':
          paymentMethod = 'gcash';
          break;
        case 'grab_pay':
          paymentMethod = 'grab_pay';
          break;
        case 'paymaya':
          paymentMethod = 'paymaya';
          break;
        case 'billease':
          paymentMethod = 'billease';
          break;
        case 'card':
        case 'credit_card':
        case 'debit_card':
          paymentMethod = 'card';
          break;
      }
    }

    // Recalculate fees based on actual payment method used
    const subtotal = orderData?.summary?.subtotal || 0;
    const sellerShippingCharge = orderData?.summary?.sellerShippingCharge || 0;
    const buyerShippingCharge = orderData?.summary?.buyerShippingCharge || 0;
    const totalChargedToBuyer = subtotal + buyerShippingCharge;
    
    // Calculate actual fees based on payment method
    const paymentProcessingFee = calculatePaymentProcessingFee(totalChargedToBuyer, paymentMethod);
    const platformFee = calculatePlatformFee(subtotal);
    const totalSellerFees = paymentProcessingFee + platformFee + sellerShippingCharge;
    const netPayoutToSeller = calculateNetPayout(subtotal, paymentProcessingFee, platformFee, sellerShippingCharge);
    
    logger.info('Recalculated fees with actual payment method', {
      orderId,
      paymentMethod,
      subtotal,
      totalChargedToBuyer,
      paymentProcessingFee,
      platformFee,
      totalSellerFees,
      netPayoutToSeller
    });

    // For active status with a payment method, treat as paid
    const finalStatus = (status === 'active' && paymentMethodUsed) ? 'paid' : status;
    const orderStatus = finalStatus === 'paid' ? 'confirmed' : 'pending';

    // Get both payment ID and payment intent ID
    // Payment ID (pay_xxx) is used for refunds - CRITICAL for refund processing
    // Payment Intent ID (pi_xxx) is for reference
    // PayMongo Checkout Session webhook sends payment ID in payments[0].id (not .data.id)
    const paymentId = eventAttributes.payments?.[0]?.id || eventAttributes.payments?.[0]?.data?.id || null;
    const paymentIntentId = eventAttributes.payment_intent?.id || null;
    const transactionId = paymentId || paymentIntentId || checkoutSessionId;

    logger.info('Extracting payment IDs from webhook', { 
      checkoutSessionId, 
      paymentId,
      paymentIntentId,
      transactionId, 
      orderId,
      finalStatus,
      orderStatus,
      paymentsArray: eventAttributes.payments,
      note: paymentId ? 'Payment ID captured - refunds will work' : 'WARNING: No payment ID - refunds will fail'
    });

    // Get existing paymongo data and merge with new data
    const existingPaymongo = orderData?.paymongo || {};
    const updatedPaymongo: any = {
      ...existingPaymongo,
      paymentStatus: finalStatus,
      paymentMethod: paymentMethod,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Add payment IDs if available
    if (paymentId && paymentId !== '' && paymentId !== null) {
      updatedPaymongo.paymentId = paymentId;
    }
    if (paymentIntentId && paymentIntentId !== '' && paymentIntentId !== null) {
      updatedPaymongo.paymentIntentId = paymentIntentId;
    }
    if (checkoutSessionId && checkoutSessionId !== '' && checkoutSessionId !== null) {
      updatedPaymongo.checkoutSessionId = checkoutSessionId;
    }

    // Get existing fees data and merge with new data
    const existingFees = orderData?.fees || {};
    const updatedFees = {
      ...existingFees,
      paymentProcessingFee: paymentProcessingFee,
      platformFee: platformFee,
      totalSellerFees: totalSellerFees,
      paymentMethod: paymentMethod,
    };

    // Get existing payout data and merge with new data
    const existingPayout = orderData?.payout || {};
    const updatedPayout = {
      ...existingPayout,
      netPayoutToSeller: netPayoutToSeller,
      calculatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Prepare update object - update entire objects atomically
    const updateData: any = {
      status: orderStatus,
      paymongo: updatedPaymongo,
      fees: updatedFees,
      payout: updatedPayout,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: orderStatus,
        timestamp: new Date(),
        note: `Payment ${finalStatus} via ${paymentMethod}`,
      }),
    };

    // Use update instead of set with merge to ensure clean updates
    await orderRef.update(updateData);

    logger.info('Order payment processed successfully', { 
      orderId, 
      orderStatus, 
      paymentStatus: finalStatus,
      feesUpdated: {
        paymentProcessingFee,
        platformFee,
        totalSellerFees,
        netPayoutToSeller
      }
    });

    // Clear cart items after successful payment
    if (userId && (orderData?.metadata?.cart_item_ids || eventAttributes.metadata?.cart_item_ids)) {
      const cartItemIds = orderData?.metadata?.cart_item_ids || eventAttributes.metadata?.cart_item_ids;
      const itemsArray = Array.isArray(cartItemIds) 
        ? cartItemIds 
        : cartItemIds.split(',');
        
      const removeCartPromises = itemsArray.map(async (cartItemId: string) => {
        await db
          .collection('User')
          .doc(userId)
          .collection('Cart')
          .doc(cartItemId.trim())
          .delete();
      });

      await Promise.all(removeCartPromises);
      logger.info('Cart items cleared', { userId, itemCount: itemsArray.length });
    }

  } catch (error) {
    logger.error('Error handling payment paid', { error: error instanceof Error ? error.message : String(error) });
    throw error;
  }
}

// ====================================
// HANDLE REFUND WEBHOOK
// ====================================

async function handleRefundWebhook(eventAttributes: any) {
  try {  
    logger.info('Processing refund webhook', { 
      refundId: eventAttributes.id,
      status: eventAttributes.status
    });

    const refundId = eventAttributes.id;
    const refundStatus = eventAttributes.status; // pending, succeeded, failed
    const paymentId = eventAttributes.payment_id;
    const amount = eventAttributes.amount;

    if (!refundId || !paymentId) {
      logger.error('Missing refund ID or payment ID in webhook');
      return;
    }

    // Find the order with this refund ID
    const ordersQuery = await db
      .collection('Order')
      .where('refundInfo.refundId', '==', refundId)
      .limit(1)
      .get();

    if (ordersQuery.empty) {
      logger.warn('No order found for refund ID', { refundId });
      return;
    }

    const orderDoc = ordersQuery.docs[0];
    const orderId = orderDoc.id;
    const orderRef = db.collection('Order').doc(orderId);
    const orderData = orderDoc.data();

    // Get existing refundInfo and merge with new data
    const existingRefundInfo = orderData?.refundInfo || {};
    const updatedRefundInfo: any = {
      ...existingRefundInfo,
      refundStatus: refundStatus,
      refundUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    // If refund succeeded, add completion timestamp
    if (refundStatus === 'succeeded') {
      updatedRefundInfo.refundCompletedAt = admin.firestore.FieldValue.serverTimestamp();
      
      // Update refund status atomically
      await orderRef.update({
        refundInfo: updatedRefundInfo,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'cancelled',
          timestamp: new Date(),
          note: `Refund completed successfully. Refund ID: ${refundId}, Amount: ₱${(amount / 100).toFixed(2)}`
        })
      });

      logger.info('Refund succeeded', { orderId, refundId, amount });
    } else if (refundStatus === 'failed') {
      // Update refund status atomically
      await orderRef.update({
        refundInfo: updatedRefundInfo,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'cancelled',
          timestamp: new Date(),
          note: `Refund failed. Refund ID: ${refundId}. Please contact support.`
        })
      });

      logger.error('Refund failed', { orderId, refundId });
    } else {
      // For pending or other statuses, just update refund info
      await orderRef.update({
        refundInfo: updatedRefundInfo,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    logger.info('Order refund status updated', { 
      orderId, 
      refundId,
      refundStatus 
    });

  } catch (error) {
    logger.error('Error handling refund webhook', { 
      error: error instanceof Error ? error.message : String(error) 
    });
    throw error;
  }
}

// ====================================
// SCHEDULED ORDER EXPIRATION FUNCTION
// ====================================

export const expirePendingOrders = onSchedule(
  {
    schedule: '*/30 * * * *',  // Every 30 minutes using cron syntax
    timeZone: 'Asia/Manila',
    region: 'asia-southeast1',
    memory: '256MiB',
    timeoutSeconds: 300
  },
  async (event) => {
    try {
      logger.info('Starting scheduled order expiration job');

      // Calculate the cutoff time (3 hours ago)
      const threeHoursAgo = new Date();
      threeHoursAgo.setHours(threeHoursAgo.getHours() - 3);

      logger.info('Checking for pending orders', { 
        cutoffTime: threeHoursAgo.toISOString() 
      });

      // Query only by status to avoid composite index requirement
      // We'll filter by time in memory
      const pendingOrdersQuery = db.collection('Order')
        .where('status', '==', 'pending')
        .limit(100); // Get more since we'll filter in memory

      const snapshot = await pendingOrdersQuery.get();

      if (snapshot.empty) {
        logger.info('No pending orders found');
        return null;
      }

      logger.info('Found pending orders to check', { count: snapshot.size });

      // Filter in memory for orders older than 3 hours
      const expiredOrders = snapshot.docs.filter(doc => {
        const orderData = doc.data();
        const createdAt = orderData.createdAt?.toDate();
        
        if (!createdAt) {
          logger.warn('Order missing createdAt timestamp', { orderId: doc.id });
          return false;
        }
        
        return createdAt < threeHoursAgo;
      });

      if (expiredOrders.length === 0) {
        logger.info('No pending orders need to be expired');
        return null;
      }

      logger.info('Found orders to expire', { count: expiredOrders.length });

      // Process in smaller batches to avoid Firestore limits
      const batchSize = 20;
      let totalExpired = 0;

      for (let i = 0; i < expiredOrders.length; i += batchSize) {
        const batch = db.batch();
        const batchOrders = expiredOrders.slice(i, i + batchSize);
        
        batchOrders.forEach((doc) => {
          const orderId = doc.id;
          logger.debug('Expiring order', { orderId });

          // Update the order to expired status
          const orderRef = db.collection('Order').doc(orderId);
          batch.update(orderRef, {
            status: 'expired',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: 'expired',
              timestamp: new Date(),
              note: 'Order expired after 3 hours of no payment',
            }),
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            expiredReason: 'Payment timeout - 3 hours elapsed'
          });

          totalExpired++;
        });

        await batch.commit();
        logger.debug('Processed batch', { 
          batchNumber: Math.floor(i/batchSize) + 1,
          expiredInBatch: batchOrders.length
        });
      }

      if (totalExpired > 0) {
        logger.info('Successfully expired pending orders', { totalExpired });
      } else {
        logger.info('No orders needed to be expired');
      }

      return null;

    } catch (error) {
      logger.error('Error in scheduled order expiration', { 
        error: error instanceof Error ? error.message : String(error) 
      });
      throw error;
    }
  });

export const handlePaymongoWebhook = onRequest(
  {
    memory: '256MiB',
    timeoutSeconds: 60,
    region: 'asia-southeast1'
  },
  async (req, res) => {
    // Set security headers
    setSecurityHeaders(res);
    
    corsHandler(req, res, async () => {
      const clientIp = (req.ip || 
                       (Array.isArray(req.headers['x-forwarded-for']) 
                         ? req.headers['x-forwarded-for'][0] 
                         : req.headers['x-forwarded-for']) || 
                       'unknown') as string;
      
      try {
        // Check rate limit based on IP
        if (!checkRateLimit(clientIp)) {
          logger.warn('Rate limit exceeded for webhook', { clientIp });
          res.status(429).json({
            success: false,
            error: 'Too many requests'
          });
          return;
        }

        logger.info('Processing Paymongo webhook', { 
          method: req.method,
          contentType: req.headers['content-type'],
          clientIp,
          userAgent: req.headers['user-agent']
        });

        // Log the complete request body for debugging
        logger.info('Webhook Request Body - FULL PAYLOAD', {
          eventType: req.body?.data?.type,
          orderId: req.body?.data?.attributes?.data?.attributes?.metadata?.order_id
        });

        // Additional security check: Verify the request is actually from Paymongo
        const userAgent = req.headers['user-agent'] as string;
        if (userAgent && !userAgent.toLowerCase().includes('paymongo')) {
          logger.warn('Suspicious webhook request - non-Paymongo user agent', { 
            userAgent, 
            clientIp 
          });
          // Continue processing but log the suspicious activity
        }

        // Note: Paymongo webhooks don't require signature verification
        // They rely on the webhook URL endpoint security and HTTPS
        logger.debug('Processing webhook without signature verification (Paymongo standard)');

        // Handle different webhook formats that Paymongo might send
        let webhookData = req.body?.data;
        
        // If no data field, maybe the whole body IS the webhook data
        if (!webhookData && req.body) {
          logger.debug('No data field found, treating entire body as webhook data');
          webhookData = req.body;
        }
        
        if (!webhookData) {
          logger.error('No webhook data received in any expected format');
          res.status(400).json({
            success: false,
            error: 'Invalid webhook data format'
          });
          return;
        }

        // Extract the actual event data from the webhook
        const eventType = webhookData.type;
        const eventAttributes = webhookData.attributes;

        logger.info('Processing webhook event', { eventType });

        // Only handle payment paid events
        if (eventType === 'event') {
          // For Paymongo webhooks, the actual event data is nested
          const actualEventType = eventAttributes.type;
          const eventData = eventAttributes.data;
          
          logger.info('Processing nested event', { actualEventType });
          
          if (actualEventType === 'checkout_session.payment.paid') {
            await handleCheckoutSessionPaymentPaid(eventData.attributes);
          } else if (actualEventType === 'payment.refunded' || actualEventType === 'refund.updated') {
            // Handle refund webhooks
            await handleRefundWebhook(eventData.attributes);
          } else if (actualEventType === 'checkout_session') {
            // Handle general checkout session updates - only if payment was completed
            const sessionData = eventData.attributes;
            const sessionStatus = sessionData.status;
            const paymentMethodUsed = sessionData.payment_method_used;
            
            logger.info('Checkout session update', { sessionStatus, paymentMethodUsed });
            
            // If session has a payment method and is active, treat as payment completed
            if (sessionStatus === 'active' && paymentMethodUsed) {
              logger.info('Treating active session with payment method as paid');
              await handleCheckoutSessionPaymentPaid(sessionData);
            } else {
              logger.debug('Ignoring checkout session status', { sessionStatus });
            }
          } else {
            logger.debug('Ignoring webhook event type', { actualEventType });
          }
        } else if (eventType === 'checkout_session.payment.paid') {
          // Direct event handling (fallback)
          await handleCheckoutSessionPaymentPaid(eventAttributes);
        } else {
          logger.debug('Ignoring webhook event type', { eventType });
        }

        // Always respond with success to Paymongo
        logger.info('Webhook processed successfully');
        
        const successResponse = {
          success: true,
          message: 'Webhook processed successfully'
        };
        
        // Log the response we're sending back
        logger.info('Sending webhook response', {
          statusCode: 200,
          response: JSON.stringify(successResponse)
        });
        
        res.status(200).json(successResponse);

      } catch (error: any) {
        logger.error('Error handling webhook', { 
          error: error instanceof Error ? error.message : String(error),
          clientIp
        });
        
        // Return generic error to avoid information disclosure
        res.status(200).json({
          success: false,
          error: 'Webhook processing failed but acknowledged'
        });
      }
    });
  });