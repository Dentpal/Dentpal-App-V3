import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import axios from 'axios';
import cors = require('cors');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Configure Firestore to ignore undefined values
db.settings({
  ignoreUndefinedProperties: true
});

// Configure CORS
const corsHandler = cors({ 
  origin: true, // Allow all origins for now
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
});

// Paymongo API configuration
const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';

// Helper function to verify authentication
async function verifyAuth(request: functions.Request): Promise<string> {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('User must be authenticated');
  }

  const idToken = authHeader.replace('Bearer ', '');
  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error) {
    throw new Error('Invalid authentication token');
  }
}

// Country name to ISO code mapping
function getCountryCode(countryName: string): string {
  const countryMap: { [key: string]: string } = {
    'philippines': 'PH',
    'united states': 'US',
    'united states of america': 'US',
    'canada': 'CA',
    'united kingdom': 'GB',
    'australia': 'AU',
    'singapore': 'SG',
    'malaysia': 'MY',
    'thailand': 'TH',
    'vietnam': 'VN',
    'indonesia': 'ID',
    'japan': 'JP',
    'south korea': 'KR',
    'china': 'CN',
    'india': 'IN',
  };

  const normalized = countryName.toLowerCase().trim();
  return countryMap[normalized] || 'PH'; // Default to Philippines
}

// ====================================
// WEBHOOK UTILITY FUNCTIONS
// ====================================

// Log failed webhooks for manual retry
async function logFailedWebhook(webhookData: any, errorMessage: string) {
  try {
    const initialRetryTime = getNextRetryTime(0); // First retry in 5 minutes
    
    await db.collection('FailedWebhooks').add({
      webhookData: webhookData,
      errorMessage: errorMessage,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      retryCount: 0,
      status: 'failed',
      lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
      nextRetryAt: admin.firestore.Timestamp.fromDate(initialRetryTime),
    });
    console.log(`📝 Failed webhook logged for retry. Next retry at: ${initialRetryTime.toISOString()}`);
  } catch (error) {
    console.error('❌ Error logging failed webhook:', error);
  }
}

// Calculate next retry time based on retry count
function getNextRetryTime(retryCount: number): Date {
  const baseDelay = 5; // 5 minutes base
  const delays = [5, 10, 30, 60, 120]; // minutes: 5min, 10min, 30min, 1hr, 2hr
  const delayMinutes = delays[Math.min(retryCount, delays.length - 1)];
  return new Date(Date.now() + delayMinutes * 60 * 1000);
}

// ====================================
// SCHEDULED WEBHOOK RETRY FUNCTION
// ====================================

export const scheduledWebhookRetry = functions
  .runWith({
    memory: '512MB',
    timeoutSeconds: 300
  })
  .pubsub.schedule('every 15 minutes')
  .onRun(async (context) => {
    try {
      console.log('🔄 Running scheduled webhook retry job...');

      // Get failed webhooks that are ready for retry
      // Using simpler query to avoid composite index requirement
      const maxRetries = 5; // Maximum automatic retries before manual intervention

      const failedWebhooksQuery = db.collection('FailedWebhooks')
        .where('status', '==', 'failed')
        .limit(20); // Get more and filter in memory to avoid index requirements

      const snapshot = await failedWebhooksQuery.get();
      
      if (snapshot.empty) {
        console.log('📝 No failed webhooks found');
        return;
      }

      // Filter in memory to avoid composite index requirements
      const now = Date.now();
      const eligibleWebhooks = snapshot.docs.filter(doc => {
        const data = doc.data();
        const retryCount = data.retryCount || 0;
        const nextRetryAt = data.nextRetryAt?.toDate?.() || new Date(0);
        
        return retryCount < maxRetries && nextRetryAt.getTime() <= now;
      }).slice(0, 10); // Limit to 10 for processing
      
      if (eligibleWebhooks.length === 0) {
        console.log('📝 No webhooks ready for retry at this time');
        return;
      }

      console.log(`🔄 Found ${eligibleWebhooks.length} failed webhooks ready for retry`);

      const retryPromises = eligibleWebhooks.map(async (doc) => {
        const webhookData = doc.data();
        const webhookId = doc.id;
        const currentRetryCount = webhookData.retryCount || 0;

        try {
          console.log(`🔄 Retrying webhook ${webhookId} (attempt ${currentRetryCount + 1})`);

          // Process the webhook using the same logic
          const processResult = await processWebhookData(webhookData.webhookData);

          if (processResult.success) {
            // Mark as resolved
            await doc.ref.update({
              status: 'resolved',
              resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
              retryCount: admin.firestore.FieldValue.increment(1),
              lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`✅ Webhook ${webhookId} resolved on retry`);
          } else {
            // Increment retry count and set next retry time
            const newRetryCount = currentRetryCount + 1;
            const nextRetryTime = getNextRetryTime(newRetryCount);
            
            await doc.ref.update({
              retryCount: admin.firestore.FieldValue.increment(1),
              lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
              nextRetryAt: admin.firestore.Timestamp.fromDate(nextRetryTime),
              lastError: processResult.error,
            });
            console.log(`❌ Webhook ${webhookId} failed retry. Next retry at: ${nextRetryTime.toISOString()}`);
          }
        } catch (error: any) {
          console.error(`❌ Error retrying webhook ${webhookId}:`, error);
          
          // Update retry count and error with next retry time
          const newRetryCount = currentRetryCount + 1;
          const nextRetryTime = getNextRetryTime(newRetryCount);
          
          await doc.ref.update({
            retryCount: admin.firestore.FieldValue.increment(1),
            lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
            nextRetryAt: admin.firestore.Timestamp.fromDate(nextRetryTime),
            lastError: error.message,
          });
        }
      });

      await Promise.all(retryPromises);
      console.log('✅ Scheduled webhook retry job completed');

    } catch (error) {
      console.error('❌ Error in scheduled webhook retry:', error);
    }
  });

// ====================================
// WEBHOOK MANAGEMENT FUNCTIONS
// ====================================

export const listFailedWebhooks = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 60
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        // TODO: Add proper admin authentication here
        
        const limit = parseInt(request.query.limit as string) || 50;
        const status = request.query.status as string || 'failed';

        const failedWebhooksQuery = db.collection('FailedWebhooks')
          .where('status', '==', status)
          .orderBy('timestamp', 'desc')
          .limit(limit);

        const snapshot = await failedWebhooksQuery.get();
        
        const failedWebhooks = snapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
          timestamp: doc.data().timestamp?.toDate?.()?.toISOString() || null,
          lastAttempt: doc.data().lastAttempt?.toDate?.()?.toISOString() || null,
        }));

        response.status(200).json({
          success: true,
          data: failedWebhooks,
          count: failedWebhooks.length,
          total: snapshot.size
        });

      } catch (error: any) {
        console.error('❌ Error listing failed webhooks:', error);
        response.status(500).json({
          success: false,
          error: error.message || 'Failed to list failed webhooks'
        });
      }
    });
  });

// ====================================
// MANUAL WEBHOOK RETRY FUNCTION
// ====================================

export const retryFailedWebhook = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 120
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        // Verify admin authentication (you may want to add proper auth)
        const { webhook_id: webhookId } = request.body;

        if (!webhookId) {
          response.status(400).json({
            success: false,
            error: 'Webhook ID is required'
          });
          return;
        }

        // Get the failed webhook
        const webhookDoc = await db.collection('FailedWebhooks').doc(webhookId).get();

        if (!webhookDoc.exists) {
          response.status(404).json({
            success: false,
            error: 'Failed webhook not found'
          });
          return;
        }

        const webhookData = webhookDoc.data();
        const originalWebhookBody = webhookData?.webhookData;

        if (!originalWebhookBody) {
          response.status(400).json({
            success: false,
            error: 'Invalid webhook data'
          });
          return;
        }

        console.log(`🔄 Retrying failed webhook: ${webhookId}`);

        // Process the webhook using the same logic
        const processResult = await processWebhookData(originalWebhookBody);

        if (processResult.success) {
          // Update the failed webhook record
          await db.collection('FailedWebhooks').doc(webhookId).update({
            status: 'resolved',
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
            retryCount: admin.firestore.FieldValue.increment(1),
            lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
          });

          response.status(200).json({
            success: true,
            message: 'Webhook processed successfully on retry',
            result: processResult
          });
        } else {
          // Update retry count but keep as failed
          await db.collection('FailedWebhooks').doc(webhookId).update({
            retryCount: admin.firestore.FieldValue.increment(1),
            lastAttempt: admin.firestore.FieldValue.serverTimestamp(),
            lastError: processResult.error,
          });

          response.status(500).json({
            success: false,
            error: 'Webhook retry failed',
            details: processResult.error
          });
        }

      } catch (error: any) {
        console.error('❌ Error retrying webhook:', error);
        response.status(500).json({
          success: false,
          error: error.message || 'Failed to retry webhook'
        });
      }
    });
  });

// ====================================
// ORDER RECOVERY FUNCTION
// ====================================

export const recoverOrderStatus = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MB',
    timeoutSeconds: 240
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
        
        if (!PAYMONGO_SECRET_KEY) {
          response.status(500).json({ 
            success: false, 
            error: 'Paymongo secret key not configured' 
          });
          return;
        }

        const { order_id: orderId } = request.body;

        if (!orderId) {
          response.status(400).json({
            success: false,
            error: 'Order ID is required'
          });
          return;
        }

        // Get the order
        const orderDoc = await db.collection('Order').doc(orderId).get();

        if (!orderDoc.exists) {
          response.status(404).json({
            success: false,
            error: 'Order not found'
          });
          return;
        }

        const orderData = orderDoc.data();
        const checkoutSessionId = orderData?.checkoutSessionId;

        if (!checkoutSessionId) {
          response.status(400).json({
            success: false,
            error: 'No checkout session ID found for this order'
          });
          return;
        }

        console.log(`🔍 Recovering order status for order: ${orderId}, session: ${checkoutSessionId}`);

        // Fetch the checkout session from Paymongo
        const sessionResponse = await axios.get(
          `${PAYMONGO_BASE_URL}/checkout_sessions/${checkoutSessionId}`,
          {
            headers: {
              'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY + ':').toString('base64')}`,
            },
          }
        );

        const sessionData = sessionResponse.data.data.attributes;
        const sessionStatus = sessionData.status;
        const paymentMethodUsed = sessionData.payment_method_used;
        const payments = sessionData.payments;

        console.log(`📊 Session status: ${sessionStatus}, Payment method: ${paymentMethodUsed}`);

        // Determine the correct order status based on session data
        let shouldUpdate = false;
        let newStatus = orderData?.status;
        let paymentStatus = orderData?.paymentInfo?.status;

        if (sessionStatus === 'paid' || (sessionStatus === 'active' && paymentMethodUsed)) {
          if (orderData?.status !== 'confirmed') {
            shouldUpdate = true;
            newStatus = 'confirmed';
            paymentStatus = 'paid';
          }
        } else if (sessionStatus === 'expired' || sessionStatus === 'cancelled') {
          if (orderData?.status !== 'payment_failed') {
            shouldUpdate = true;
            newStatus = 'payment_failed';
            paymentStatus = 'failed';
          }
        }

        if (shouldUpdate) {
          // Update the order with the correct status
          const updateData: any = {
            status: newStatus,
            'paymentInfo.status': paymentStatus,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            statusHistory: admin.firestore.FieldValue.arrayUnion({
              status: newStatus,
              timestamp: new Date(),
              note: `Status recovered from Paymongo session - ${sessionStatus}`,
            }),
          };

          if (paymentMethodUsed) {
            updateData['paymentInfo.method'] = paymentMethodUsed;
          }

          if (paymentStatus === 'paid') {
            updateData['paymentInfo.paidAt'] = admin.firestore.FieldValue.serverTimestamp();
          }

          // Add payment info if available
          if (payments && payments.length > 0) {
            updateData['paymentInfo.paymentIntentId'] = payments[0].data.id;
          }

          await db.collection('Order').doc(orderId).update(updateData);

          console.log(`✅ Order ${orderId} status recovered: ${newStatus}`);

          response.status(200).json({
            success: true,
            message: 'Order status recovered successfully',
            previousStatus: orderData?.status,
            newStatus: newStatus,
            sessionStatus: sessionStatus
          });
        } else {
          response.status(200).json({
            success: true,
            message: 'Order status is already correct',
            currentStatus: orderData?.status,
            sessionStatus: sessionStatus
          });
        }

      } catch (error: any) {
        console.error('❌ Error recovering order status:', error);
        response.status(500).json({
          success: false,
          error: error.message || 'Failed to recover order status'
        });
      }
    });
  });

// Helper function to process webhook data
async function processWebhookData(webhookBody: any): Promise<{ success: boolean; error?: string }> {
  try {
    const webhookData = webhookBody?.data;
    
    if (!webhookData) {
      return { success: false, error: 'Invalid webhook data' };
    }

    const eventType = webhookData.type;
    const eventAttributes = webhookData.attributes;

    if (eventType === 'event') {
      const actualEventType = eventAttributes.type;
      const eventData = eventAttributes.data;
      
      switch (actualEventType) {
        case 'checkout_session.payment.paid':
          await handleCheckoutSessionPaymentPaid(eventData.attributes);
          break;
        
        case 'checkout_session.payment.failed':
          await handleCheckoutSessionPaymentFailed(eventData.attributes);
          break;
          
        case 'checkout_session':
          const sessionData = eventData.attributes;
          const sessionStatus = sessionData.status;
          const paymentMethodUsed = sessionData.payment_method_used;
          
          if (sessionStatus === 'active' && paymentMethodUsed) {
            await handleCheckoutSessionPaymentPaid(sessionData);
          } else if (sessionStatus === 'expired' || sessionStatus === 'cancelled') {
            await handleCheckoutSessionPaymentFailed(sessionData);
          }
          break;
      }
    } else {
      switch (eventType) {
        case 'checkout_session.payment.paid':
          await handleCheckoutSessionPaymentPaid(eventAttributes);
          break;
        
        case 'checkout_session.payment.failed':
          await handleCheckoutSessionPaymentFailed(eventAttributes);
          break;
      }
    }

    return { success: true };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

// ====================================
// PAYMONGO CHECKOUT SESSION FUNCTION
// ====================================

export const createCheckoutSession = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MB',
    timeoutSeconds: 240
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
        
        if (!PAYMONGO_SECRET_KEY) {
          response.status(500).json({ 
            success: false, 
            error: 'Paymongo secret key not configured' 
          });
          return;
        }

        // Verify user authentication
        const userId = await verifyAuth(request);
        
        // Parse request body
        const data = request.body;
        const {
          cart_item_ids: cartItemIds,
          address_id: addressId,
          notes,
          payment_method_types: paymentMethodTypes = ['card', 'gcash', 'grab_pay', 'paymaya'],
          success_url: successUrl,
          cancel_url: cancelUrl
        } = data;

        // Validate required fields
        if (!cartItemIds || !Array.isArray(cartItemIds) || cartItemIds.length === 0) {
          response.status(400).json({ 
            success: false, 
            error: 'Cart items are required' 
          });
          return;
        }

        if (!addressId) {
          response.status(400).json({ 
            success: false, 
            error: 'Address ID is required' 
          });
          return;
        }

        console.log(`🛒 Creating checkout session for user ${userId} with ${cartItemIds.length} cart items`);
        
        // Get user's cart items
        const cartPromises = cartItemIds.map(async (cartItemId: string) => {
          const cartDoc = await db
            .collection('User')
            .doc(userId)
            .collection('Cart')
            .doc(cartItemId)
            .get();

          if (!cartDoc.exists) {
            console.error(`❌ Cart item ${cartItemId} not found`);
            throw new Error(`Cart item ${cartItemId} not found`);
          }

          return { id: cartDoc.id, ...cartDoc.data() };
        });

        const cartItems = await Promise.all(cartPromises);

        // Get shipping address
        const addressDoc = await db
          .collection('User')
          .doc(userId)
          .collection('Address')
          .doc(addressId)
          .get();

        if (!addressDoc.exists) {
          throw new Error('Shipping address not found');
        }

        const shippingAddress = addressDoc.data();

        // Get user info for billing
        const userDoc = await db.collection('User').doc(userId).get();
        const userData = userDoc.data();

        // Get product details for each cart item
        const orderItemsPromises = cartItems.map(async (cartItem: any) => {
          const productDoc = await db.collection('Product').doc(cartItem.productId).get();
          
          if (!productDoc.exists) {
            throw new Error(`Product ${cartItem.productId} not found`);
          }

          const product = productDoc.data();
          
          let variationPrice = 0;
          let variationName = '';
          
          if (cartItem.variationId) {
            const variationDoc = await db
              .collection('Product')
              .doc(cartItem.productId)
              .collection('Variation')
              .doc(cartItem.variationId)
              .get();
            
            if (variationDoc.exists) {
              const variationData = variationDoc.data();
              variationPrice = variationData?.price || 0;
              variationName = variationData?.name || '';
            } else {
              console.error(`❌ Variation ${cartItem.variationId} not found for product ${cartItem.productId}`);
              // Fallback to base product price instead of throwing error
              variationPrice = product?.price || 0;
              variationName = 'Default';
            }
          } else {
            variationPrice = product?.price || 0;
          }

          // Get seller info
          const sellerDoc = await db.collection('User').doc(product?.sellerId).get();
          const sellerData = sellerDoc.data();

          return {
            productId: cartItem.productId,
            productName: `${product?.name || ''}${variationName ? ` - ${variationName}` : ''}`,
            productImage: product?.imageURL || '',
            price: variationPrice,
            quantity: cartItem.quantity,
            variationId: cartItem.variationId,
            sellerId: product?.sellerId,
            sellerName: sellerData?.displayName || 'Unknown Seller',
            total: variationPrice * cartItem.quantity,
          };
        });

        const orderItems = await Promise.all(orderItemsPromises);

        // Calculate totals
        const subtotal = orderItems.reduce((sum, item) => sum + item.total, 0);
        const shippingCost = 50; // Fixed shipping cost for now
        const totalAmount = subtotal + shippingCost;

        // Get unique seller IDs
        const sellerIds = [...new Set(orderItems.map(item => item.sellerId))];

        // Create order document
        const orderRef = await db.collection('Order').add({
          userId: userId,
          sellerIds: sellerIds,
          items: orderItems.map(item => ({
            productId: item.productId,
            productName: item.productName,
            productImage: item.productImage,
            price: item.price,
            quantity: item.quantity,
            variationId: item.variationId,
            sellerId: item.sellerId,
            sellerName: item.sellerName,
          })),
          summary: {
            subtotal: subtotal,
            shippingCost: shippingCost,
            taxAmount: 0,
            discountAmount: 0,
            total: totalAmount,
            totalItems: orderItems.reduce((sum, item) => sum + item.quantity, 0),
          },
          shippingInfo: {
            addressId: addressId,
            fullName: shippingAddress?.fullName,
            addressLine1: shippingAddress?.addressLine1,
            addressLine2: shippingAddress?.addressLine2,
            city: shippingAddress?.city,
            state: shippingAddress?.state,
            postalCode: shippingAddress?.postalCode,
            country: shippingAddress?.country,
            phoneNumber: shippingAddress?.phoneNumber,
            notes: notes,
          },
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          statusHistory: [{
            status: 'pending',
            timestamp: new Date(),
            note: 'Order created',
          }],
          metadata: {
            cart_item_ids: cartItemIds,
          },
        });

        // Prepare line items for Paymongo checkout
        const lineItems = orderItems.map(item => ({
          name: item.productName,
          quantity: item.quantity,
          amount: Math.round(item.price * 100), // Convert to centavos
          currency: 'PHP',
          description: `Product ID: ${item.productId}`,
          images: item.productImage ? [item.productImage] : undefined,
        }));

        // Add shipping as a line item
        if (shippingCost > 0) {
          lineItems.push({
            name: 'Shipping Fee',
            quantity: 1,
            amount: Math.round(shippingCost * 100),
            currency: 'PHP',
            description: 'Standard shipping',
            images: undefined,
          });
        }

        // Create Paymongo Checkout Session
        const checkoutSessionData = {
          data: {
            attributes: {
              description: `DentPal Order #${orderRef.id}`,
              line_items: lineItems,
              payment_method_types: paymentMethodTypes,
              success_url: successUrl || `${process.env.APP_URL}/order-success?session_id={CHECKOUT_SESSION_ID}`,
              cancel_url: cancelUrl || `${process.env.APP_URL}/checkout?cancelled=true`,
              metadata: {
                order_id: orderRef.id,
                user_id: userId,
                seller_ids: sellerIds.join(','),
                cart_item_ids: cartItemIds.join(','),
              },
              billing: {
                name: userData?.displayName || shippingAddress?.fullName,
                email: userData?.email,
                phone: shippingAddress?.phoneNumber,
                address: {
                  line1: shippingAddress?.addressLine1,
                  line2: shippingAddress?.addressLine2,
                  city: shippingAddress?.city,
                  state: shippingAddress?.state,
                  postal_code: shippingAddress?.postalCode,
                  country: getCountryCode(shippingAddress?.country || 'Philippines'),
                },
              },
            },
          },
        };

        const checkoutResponse = await axios.post(
          `${PAYMONGO_BASE_URL}/checkout_sessions`,
          checkoutSessionData,
          {
            headers: {
              'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY + ':').toString('base64')}`,
              'Content-Type': 'application/json',
            },
          }
        );

        const checkoutSession = checkoutResponse.data.data;

        // Update order with checkout session ID
        await orderRef.update({
          checkoutSessionId: checkoutSession.id,
          paymentInfo: {
            checkoutSessionId: checkoutSession.id,
            method: 'card', // Will be updated when payment is completed
            status: 'pending',
            amount: totalAmount,
            currency: 'PHP',
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Checkout session created: ${checkoutSession.id} for order: ${orderRef.id}`);

        response.status(200).json({
          success: true,
          data: {
            order_id: orderRef.id,
            checkout_session: checkoutSession,
            total_amount: totalAmount,
            currency: 'PHP',
          },
        });

      } catch (error: any) {
        console.error('❌ Error creating checkout session:', error);
        response.status(error.message.includes('authenticated') ? 401 : 500).json({
          success: false,
          error: error.message || 'Failed to create checkout session'
        });
      }
    });
  });

// ====================================
// PAYMONGO WEBHOOK HANDLER
// ====================================

export const handlePaymongoWebhook = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 60
  })
  .https.onRequest(async (req, res) => {
    corsHandler(req, res, async () => {
      const maxRetries = 3;
      let retryCount = 0;
      
      while (retryCount <= maxRetries) {
        try {
          console.log(`📬 Received Paymongo webhook (attempt ${retryCount + 1}):`, JSON.stringify(req.body, null, 2));

          const webhookData = req.body?.data;
          
          if (!webhookData) {
            console.error('❌ No webhook data received');
            res.status(400).json({
              success: false,
              error: 'Invalid webhook data'
            });
            return;
          }

          // Extract the actual event data from the webhook
          const eventType = webhookData.type;
          const eventAttributes = webhookData.attributes;

          console.log(`📬 Processing webhook event: ${eventType}`);
          console.log('📬 Event attributes:', JSON.stringify(eventAttributes, null, 2));

          // Handle checkout session events
          if (eventType === 'event') {
            // For Paymongo webhooks, the actual event data is nested
            const actualEventType = eventAttributes.type;
            const eventData = eventAttributes.data;
            
            console.log(`📬 Actual event type: ${actualEventType}`);
            
            switch (actualEventType) {
              case 'checkout_session.payment.paid':
                await handleCheckoutSessionPaymentPaid(eventData.attributes);
                break;
              
              case 'checkout_session.payment.failed':
                await handleCheckoutSessionPaymentFailed(eventData.attributes);
                break;
                
              case 'checkout_session':
                // Handle general checkout session updates - check if payment was completed
                const sessionData = eventData.attributes;
                const sessionStatus = sessionData.status;
                const paymentMethodUsed = sessionData.payment_method_used;
                
                console.log(`📬 Checkout session update - Status: ${sessionStatus}, Payment Method: ${paymentMethodUsed}`);
                
                // If session has a payment method and is active, treat as payment completed
                if (sessionStatus === 'active' && paymentMethodUsed) {
                  console.log('🎯 Treating active session with payment method as paid');
                  await handleCheckoutSessionPaymentPaid(sessionData);
                } else if (sessionStatus === 'expired' || sessionStatus === 'cancelled') {
                  console.log('❌ Session expired or cancelled');
                  await handleCheckoutSessionPaymentFailed(sessionData);
                }
                break;
              
              default:
                console.log(`🔄 Unhandled webhook event type: ${actualEventType}`);
            }
          } else {
            // Direct event handling (fallback)
            switch (eventType) {
              case 'checkout_session.payment.paid':
                await handleCheckoutSessionPaymentPaid(eventAttributes);
                break;
              
              case 'checkout_session.payment.failed':
                await handleCheckoutSessionPaymentFailed(eventAttributes);
                break;
              
              default:
                console.log(`🔄 Unhandled webhook event type: ${eventType}`);
            }
          }

          // If we reach here, the webhook was processed successfully
          console.log(`✅ Webhook processed successfully on attempt ${retryCount + 1}`);
          res.status(200).json({
            success: true,
            message: 'Webhook processed successfully',
            attempt: retryCount + 1
          });
          return;

        } catch (error: any) {
          retryCount++;
          console.error(`❌ Error handling webhook (attempt ${retryCount}):`, error);
          
          if (retryCount > maxRetries) {
            // Log the failed webhook for manual retry
            await logFailedWebhook(req.body, error.message);
            
            res.status(500).json({
              success: false,
              error: 'Webhook processing failed after retries',
              attempts: retryCount
            });
            return;
          }
          
          // Wait before retrying (exponential backoff)
          const delay = Math.pow(2, retryCount - 1) * 1000; // 1s, 2s, 4s
          console.log(`⏳ Retrying in ${delay}ms...`);
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    });
  });

// Helper function to handle successful checkout session payments
async function handleCheckoutSessionPaymentPaid(eventAttributes: any) {
  try {
    const orderId = eventAttributes.metadata?.order_id;
    const userId = eventAttributes.metadata?.user_id;
    const checkoutSessionId = eventAttributes.id;
    const paymentMethodUsed = eventAttributes.payment_method_used;
    const status = eventAttributes.status;
    
    console.log(`✅ Processing payment event - Session: ${checkoutSessionId}, Order: ${orderId}, Status: ${status}, Payment Method: ${paymentMethodUsed}`);

    // Check if payment is actually completed
    if (status !== 'paid' && status !== 'active') {
      console.log(`⚠️ Payment not completed yet. Status: ${status}`);
      return;
    }

    if (!orderId) {
      console.error('❌ No order ID found in webhook metadata');
      return;
    }

    // Update order status
    const orderRef = db.collection('Order').doc(orderId);
    const orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      console.error(`❌ Order ${orderId} not found`);
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
          paymentMethod = 'grabpay';
          break;
        case 'paymaya':
          paymentMethod = 'paymaya';
          break;
        case 'billease':
          paymentMethod = 'billEase';
          break;
        case 'card':
        case 'credit_card':
        case 'debit_card':
          paymentMethod = 'card';
          break;
        default:
          paymentMethod = 'card';
      }
    }

    // For active status with a payment method, treat as paid
    const finalStatus = (status === 'active' && paymentMethodUsed) ? 'paid' : status;
    const orderStatus = finalStatus === 'paid' ? 'confirmed' : 'pending';

    // Get transaction ID
    const transactionId = eventAttributes.payments?.[0]?.data?.id || 
                         eventAttributes.payment_intent?.id || 
                         checkoutSessionId;

    console.log(`🔍 Debug values - checkoutSessionId: ${checkoutSessionId}, transactionId: ${transactionId}, orderId: ${orderId}`);

    // Prepare update object with only defined values
    const updateData: any = {
      status: orderStatus,
      'paymentInfo.status': finalStatus,
      'paymentInfo.method': paymentMethod,
      'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: orderStatus,
        timestamp: new Date(),
        note: `Payment ${finalStatus} via ${paymentMethod}`,
      }),
    };

    // Only add these fields if they are defined and not empty
    if (transactionId && transactionId !== '' && transactionId !== null) {
      updateData['paymentInfo.paymentIntentId'] = transactionId;
      console.log(`✅ Adding paymentIntentId: ${transactionId}`);
    }
    if (checkoutSessionId && checkoutSessionId !== '' && checkoutSessionId !== null) {
      updateData['paymentInfo.checkoutSessionId'] = checkoutSessionId;
      console.log(`✅ Adding checkoutSessionId: ${checkoutSessionId}`);
    }

    console.log(`🔍 Final update data:`, JSON.stringify(updateData, null, 2));

    await orderRef.update(updateData);

    console.log(`✅ Order ${orderId} updated to ${orderStatus} status with payment ${finalStatus}`);

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
      console.log(`🗑️ Cleared ${itemsArray.length} cart items for user ${userId}`);
    }

  } catch (error) {
    console.error('❌ Error handling payment paid:', error);
    throw error;
  }
}

// Helper function to handle failed checkout session payments
async function handleCheckoutSessionPaymentFailed(eventAttributes: any) {
  try {
    const orderId = eventAttributes.metadata?.order_id;
    const checkoutSessionId = eventAttributes.id;
    
    console.log(`❌ Payment failed - Session: ${checkoutSessionId}, Order: ${orderId}`);

    if (!orderId) {
      console.error('❌ No order ID found in payment failure webhook');
      return;
    }

    // Update order status
    const orderRef = db.collection('Order').doc(orderId);
    const orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      console.error(`❌ Order ${orderId} not found`);
      return;
    }

    // Prepare update object with only defined values
    const updateData: any = {
      status: 'payment_failed',
      'paymentInfo.status': 'failed',
      'paymentInfo.failedAt': admin.firestore.FieldValue.serverTimestamp(),
      'paymentInfo.failureReason': eventAttributes.failure_reason || 'Payment failed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: 'payment_failed',
        timestamp: new Date(),
        note: `Payment failed: ${eventAttributes.failure_reason || 'Unknown reason'}`,
      }),
    };

    await orderRef.update(updateData);

    console.log(`❌ Order ${orderId} updated to payment_failed status`);

  } catch (error) {
    console.error('❌ Error handling payment failed:', error);
    throw error;
  }
}
