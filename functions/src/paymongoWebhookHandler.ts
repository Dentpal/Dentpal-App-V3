import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import cors = require('cors');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// Configure CORS
const corsHandler = cors({ 
  origin: true,
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
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

    console.log(`� Final update data:`, JSON.stringify(updateData, null, 2));

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

// ====================================
// SCHEDULED ORDER EXPIRATION FUNCTION
// ====================================

export const expirePendingOrders = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 300
  })
  .pubsub.schedule('every 30 minutes')
  .onRun(async (context) => {
    try {
      console.log('🕒 Starting scheduled order expiration job...');

      // Calculate the cutoff time (3 hours ago)
      const threeHoursAgo = new Date();
      threeHoursAgo.setHours(threeHoursAgo.getHours() - 3);

      console.log(`⏰ Checking for pending orders created before: ${threeHoursAgo.toISOString()}`);

      // Query only by status to avoid composite index requirement
      // We'll filter by time in memory
      const pendingOrdersQuery = db.collection('Order')
        .where('status', '==', 'pending')
        .limit(100); // Get more since we'll filter in memory

      const snapshot = await pendingOrdersQuery.get();

      if (snapshot.empty) {
        console.log('📝 No pending orders found');
        return null;
      }

      console.log(`🔍 Found ${snapshot.size} pending orders to check`);

      // Filter in memory for orders older than 3 hours
      const expiredOrders = snapshot.docs.filter(doc => {
        const orderData = doc.data();
        const createdAt = orderData.createdAt?.toDate();
        
        if (!createdAt) {
          console.log(`⚠️ Order ${doc.id} has no createdAt timestamp`);
          return false;
        }
        
        return createdAt < threeHoursAgo;
      });

      if (expiredOrders.length === 0) {
        console.log('📝 No pending orders need to be expired');
        return null;
      }

      console.log(`⏳ Found ${expiredOrders.length} orders to expire`);

      // Process in smaller batches to avoid Firestore limits
      const batchSize = 20;
      let totalExpired = 0;

      for (let i = 0; i < expiredOrders.length; i += batchSize) {
        const batch = db.batch();
        const batchOrders = expiredOrders.slice(i, i + batchSize);
        
        batchOrders.forEach((doc) => {
          const orderId = doc.id;
          console.log(`⏳ Expiring order: ${orderId}`);

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
        console.log(`✅ Processed batch ${Math.floor(i/batchSize) + 1} - expired ${batchOrders.length} orders`);
      }

      if (totalExpired > 0) {
        console.log(`✅ Successfully expired ${totalExpired} pending orders`);
      } else {
        console.log('📝 No orders needed to be expired');
      }

      return null;

    } catch (error) {
      console.error('❌ Error in scheduled order expiration:', error);
      throw error;
    }
  });

export const handlePaymongoWebhook = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 60
  })
  .https.onRequest(async (req, res) => {
    // Log ALL incoming requests - even before CORS
    console.log(`🔍 RAW WEBHOOK REQUEST - Method: ${req.method}, URL: ${req.url}`);
    console.log(`🔍 RAW HEADERS:`, JSON.stringify(req.headers, null, 2));
    console.log(`🔍 RAW BODY:`, JSON.stringify(req.body, null, 2));
    
    corsHandler(req, res, async () => {
      try {
        console.log(`📬 Processing Paymongo webhook - Body keys: ${Object.keys(req.body || {})}`);

        // Handle different webhook formats that Paymongo might send
        let webhookData = req.body?.data;
        
        // If no data field, maybe the whole body IS the webhook data
        if (!webhookData && req.body) {
          console.log(`🔄 No 'data' field found, treating entire body as webhook data`);
          webhookData = req.body;
        }
        
        if (!webhookData) {
          console.error('❌ No webhook data received in any expected format');
          console.error('❌ Request body structure:', JSON.stringify(req.body, null, 2));
          res.status(400).json({
            success: false,
            error: 'Invalid webhook data format'
          });
          return;
        }

        // Extract the actual event data from the webhook
        const eventType = webhookData.type;
        const eventAttributes = webhookData.attributes;

        console.log(`📬 Processing webhook event: ${eventType}`);

        // Only handle payment paid events
        if (eventType === 'event') {
          // For Paymongo webhooks, the actual event data is nested
          const actualEventType = eventAttributes.type;
          const eventData = eventAttributes.data;
          
          console.log(`📬 Actual event type: ${actualEventType}`);
          
          if (actualEventType === 'checkout_session.payment.paid') {
            await handleCheckoutSessionPaymentPaid(eventData.attributes);
          } else if (actualEventType === 'checkout_session') {
            // Handle general checkout session updates - only if payment was completed
            const sessionData = eventData.attributes;
            const sessionStatus = sessionData.status;
            const paymentMethodUsed = sessionData.payment_method_used;
            
            console.log(`📬 Checkout session update - Status: ${sessionStatus}, Payment Method: ${paymentMethodUsed}`);
            
            // If session has a payment method and is active, treat as payment completed
            if (sessionStatus === 'active' && paymentMethodUsed) {
              console.log('🎯 Treating active session with payment method as paid');
              await handleCheckoutSessionPaymentPaid(sessionData);
            } else {
              console.log(`ℹ️ Ignoring checkout session status: ${sessionStatus} (handled on client-side)`);
            }
          } else {
            console.log(`ℹ️ Ignoring webhook event type: ${actualEventType} (not a payment success)`);
          }
        } else if (eventType === 'checkout_session.payment.paid') {
          // Direct event handling (fallback)
          await handleCheckoutSessionPaymentPaid(eventAttributes);
        } else {
          console.log(`ℹ️ Ignoring webhook event type: ${eventType} (not a payment success)`);
        }

        // Always respond with success to Paymongo
        console.log(`✅ Webhook processed successfully`);
        res.status(200).json({
          success: true,
          message: 'Webhook processed successfully'
        });

      } catch (error: any) {
        console.error(`❌ Error handling webhook:`, error);
        
        // Still respond with success to avoid Paymongo retries for non-critical errors
        res.status(200).json({
          success: false,
          error: 'Webhook processing failed but acknowledged',
          details: error.message
        });
      }
    });
  });