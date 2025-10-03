import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import axios from 'axios';
import cors = require('cors');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

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

// Configure CORS
const corsHandler = cors({ 
  origin: true, // Allow all origins for now
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
});

// Paymongo API configuration
const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';

// Simple test function
export const helloWorld = functions.https.onRequest((request, response) => {
  response.send("Hello from DentPal Firebase Functions!");
});

// Create Paymongo Checkout Session (New preferred method)
export const createCheckoutSession = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MB',
    timeoutSeconds: 240
  })
  .https.onRequest(async (request, response) => {
    // Handle CORS
    corsHandler(request, response, async () => {
      try {
    const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
    
    if (!PAYMONGO_SECRET_KEY) {
      response.status(500).json({ error: 'Paymongo secret key not configured' });
      return;
    }

    // Verify user authentication from Authorization header
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      response.status(401).json({ error: 'User must be authenticated' });
      return;
    }

    const idToken = authHeader.replace('Bearer ', '');
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch (error) {
      response.status(401).json({ error: 'Invalid authentication token' });
      return;
    }

    const userId = decodedToken.uid;
    
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
      response.status(400).json({ error: 'Cart items are required' });
      return;
    }

    if (!addressId) {
      response.status(400).json({ error: 'Shipping address is required' });
      return;
    }

    // Get user's cart items with detailed debugging
    console.log(`🛒 Checking ${cartItemIds.length} cart items for user ${userId}:`, cartItemIds);
    
    const cartPromises = cartItemIds.map(async (cartItemId: string) => {
      const cartDoc = await db
        .collection('User')
        .doc(userId)
        .collection('Cart')
        .doc(cartItemId)
        .get();

      if (!cartDoc.exists) {
        console.error(`❌ Cart item ${cartItemId} not found in database`);
        
        // Debug: Check what cart items actually exist for this user
        const allCartItems = await db
          .collection('User')
          .doc(userId)
          .collection('Cart')
          .get();
        
        const existingCartIds = allCartItems.docs.map(doc => doc.id);
        console.log(`🔍 User ${userId} has ${existingCartIds.length} cart items:`, existingCartIds);
        
        throw new Error(`Cart item ${cartItemId} not found`);
      }

      console.log(`✅ Found cart item ${cartItemId}:`, cartDoc.data());
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
      
      // Get variation details from the Variation subcollection
      let variationPrice = 0;
      let variationName = '';
      
      if (cartItem.variationId) {
        console.log(`🔍 Fetching variation ${cartItem.variationId} for product ${cartItem.productId}`);
        
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
          console.log(`✅ Found variation: ${variationName} with price: ${variationPrice}`);
        } else {
          console.error(`❌ Variation ${cartItem.variationId} not found for product ${cartItem.productId}`);
          throw new Error(`Variation ${cartItem.variationId} not found`);
        }
      } else {
        // Fallback to product base price if no variation
        variationPrice = product?.price || 0;
        console.log(`📦 Using product base price: ${variationPrice}`);
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

    // Create order document with new structure
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
    });

    // Create a subcollection for the address
    if (shippingAddress) {
      await orderRef.collection('Address').doc('shipping').set(shippingAddress);
    }

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
          success_url: successUrl || `https://dentpal-store.web.app/payment-success?session_id={CHECKOUT_SESSION_ID}`,
          cancel_url: cancelUrl || `https://dentpal-store.web.app/payment-failed?session_id={CHECKOUT_SESSION_ID}`,
          send_email_receipt: true, // Enable automatic email receipt
          metadata: {
            order_id: orderRef.id,
            user_id: userId,
            seller_ids: sellerIds.join(','),
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

    // Remove cart items after successful order creation
    const removeCartPromises = cartItemIds.map(async (cartItemId: string) => {
      await db
        .collection('User')
        .doc(userId)
        .collection('Cart')
        .doc(cartItemId)
        .delete();
    });

    await Promise.all(removeCartPromises);

    const responseData = {
      success: true,
      data: {
        order_id: orderRef.id,
        checkout_session: checkoutSession,
        total_amount: totalAmount,
        currency: 'PHP',
      },
    };

    response.status(200).json(responseData);

    } catch (error) {
      console.error('Error creating checkout session:', error);
      
      // Log detailed error information
      if (error.response) {
        console.error('Paymongo API Error Response:', {
          status: error.response.status,
          statusText: error.response.statusText,
          data: error.response.data,
          headers: error.response.headers
        });
      }
      
      response.status(500).json({ 
        error: 'Failed to create checkout session',
        details: error.response?.data || (error instanceof Error ? error.message : 'Unknown error')
      });
    }
    }); // Close CORS handler
  }); // Close HTTPS function

// Create Paymongo Payment Intent (Legacy method - kept for backward compatibility)
export const createPaymentIntent = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MB',
    timeoutSeconds: 540
  })
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
  try {
    const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
    
    if (!PAYMONGO_SECRET_KEY) {
      throw new functions.https.HttpsError('failed-precondition', 'Paymongo secret key not configured');
    }

    // Verify user authentication
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = context.auth.uid;
    const {
      cartItemIds,
      addressId,
      notes,
      paymentMethodAllowed = ['card', 'gcash', 'grab_pay', 'paymaya']
    } = data;

    // Validate required fields
    if (!cartItemIds || !Array.isArray(cartItemIds) || cartItemIds.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'Cart items are required');
    }

    if (!addressId) {
      throw new functions.https.HttpsError('invalid-argument', 'Shipping address is required');
    }

    // Get user's cart items
    const cartPromises = cartItemIds.map(async (cartItemId: string) => {
      const cartDoc = await db
        .collection('User')
        .doc(userId)
        .collection('Cart')
        .doc(cartItemId)
        .get();

      if (!cartDoc.exists) {
        throw new functions.https.HttpsError('not-found', `Cart item ${cartItemId} not found`);
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
      throw new functions.https.HttpsError('not-found', 'Shipping address not found');
    }

    const shippingAddress = addressDoc.data();

    // Get product details for each cart item
    const orderItemsPromises = cartItems.map(async (cartItem: any) => {
      const productDoc = await db.collection('Product').doc(cartItem.productId).get();
      
      if (!productDoc.exists) {
        throw new functions.https.HttpsError('not-found', `Product ${cartItem.productId} not found`);
      }

      const product = productDoc.data();
      const price = product?.variations?.find((v: any) => v.variationId === cartItem.variationId)?.price || product?.price || 0;

      return {
        productId: cartItem.productId,
        productName: product?.name || '',
        productImage: product?.imageURL || '',
        price: price,
        quantity: cartItem.quantity,
        variationId: cartItem.variationId,
        sellerId: product?.sellerId,
        total: price * cartItem.quantity,
      };
    });

    const orderItems = await Promise.all(orderItemsPromises);

    // Group items by seller
    const sellerGroups: { [sellerId: string]: any[] } = {};
    orderItems.forEach(item => {
      if (!sellerGroups[item.sellerId]) {
        sellerGroups[item.sellerId] = [];
      }
      sellerGroups[item.sellerId].push(item);
    });

    // Create orders for each seller
    const orderPromises = Object.entries(sellerGroups).map(async ([sellerId, items]) => {
      // Get seller information
      const sellerDoc = await db.collection('User').doc(sellerId).get();
      const sellerData = sellerDoc.data();

      const subtotal = items.reduce((sum, item) => sum + item.total, 0);
      const shippingCost = 50; // Fixed shipping cost for now
      const total = subtotal + shippingCost;

      // Create order document
      const orderRef = await db.collection('Order').add({
        userId: userId,
        sellerIds: [sellerId],
        items: items.map(item => ({
          productId: item.productId,
          productName: item.productName,
          productImage: item.productImage,
          price: item.price,
          quantity: item.quantity,
          variationId: item.variationId,
          sellerId: item.sellerId,
          sellerName: sellerData?.displayName || 'Unknown Seller',
        })),
        summary: {
          subtotal: subtotal,
          shippingCost: shippingCost,
          taxAmount: 0,
          discountAmount: 0,
          total: total,
          totalItems: items.reduce((sum, item) => sum + item.quantity, 0),
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
      });

      return {
        orderId: orderRef.id,
        sellerId: sellerId,
        sellerName: sellerData?.displayName || 'Unknown Seller',
        total: total,
        items: items,
      };
    });

    const orders = await Promise.all(orderPromises);
    const totalAmount = orders.reduce((sum, order) => sum + order.total, 0);

    // Create Paymongo Payment Intent
    const paymentIntentData = {
      data: {
        attributes: {
          amount: Math.round(totalAmount * 100), // Convert to centavos
          currency: 'PHP',
          description: `DentPal Order - ${orders.length} order(s)`,
          payment_method_allowed: paymentMethodAllowed,
          metadata: {
            user_id: userId,
            order_ids: orders.map(o => o.orderId).join(','),
            order_count: orders.length.toString(),
          },
        },
      },
    };

    const paymentIntentResponse = await axios.post(
      `${PAYMONGO_BASE_URL}/payment_intents`,
      paymentIntentData,
      {
        headers: {
          'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY + ':').toString('base64')}`,
          'Content-Type': 'application/json',
        },
      }
    );

    const paymentIntent = paymentIntentResponse.data.data;

    // Update orders with payment intent ID
    const updatePromises = orders.map(async (order) => {
      await db.collection('Order').doc(order.orderId).update({
        paymentInfo: {
          paymentIntentId: paymentIntent.id,
          method: 'card', // Will be updated when payment is completed
          status: 'pending',
          amount: order.total,
          currency: 'PHP',
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await Promise.all(updatePromises);

    // Remove cart items after successful order creation
    const removeCartPromises = cartItemIds.map(async (cartItemId: string) => {
      await db
        .collection('User')
        .doc(userId)
        .collection('Cart')
        .doc(cartItemId)
        .delete();
    });

    await Promise.all(removeCartPromises);

    return {
      success: true,
      data: {
        orders: orders,
        paymentIntent: paymentIntent,
        totalAmount: totalAmount,
        currency: 'PHP',
      },
    };

  } catch (error) {
    console.error('Error creating payment intent:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError(
      'internal',
      'Failed to create payment intent',
      error
    );
  }
});

// Handle Paymongo Webhooks
export const handlePaymongoWebhook = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const event = req.body;
    
    // Verify webhook signature (implement signature verification based on Paymongo docs)
    // const signature = req.headers['paymongo-signature'];
    // if (!verifyWebhookSignature(req.body, signature)) {
    //   res.status(401).send('Unauthorized');
    //   return;
    // }

    console.log('Webhook event received:', event.data.type);

    switch (event.data.type) {
      case 'payment_intent.payment.paid':
        await handlePaymentPaid(event.data);
        break;
      
      case 'payment_intent.payment.failed':
        await handlePaymentFailed(event.data);
        break;
      
      case 'checkout_session.payment.paid':
        await handleCheckoutSessionPaid(event.data);
        break;
      
      case 'checkout_session.payment.failed':
        await handleCheckoutSessionFailed(event.data);
        break;
      
      default:
        console.log('Unhandled webhook event type:', event.data.type);
    }

    res.status(200).send('OK');

  } catch (error) {
    console.error('Error handling webhook:', error);
    res.status(500).send('Internal Server Error');
  }
});

// Handle successful payment
async function handlePaymentPaid(eventData: any) {
  try {
    const paymentIntentId = eventData.attributes.payment_intent_id;
    const paymentMethodType = eventData.attributes.payment_method?.type || 'card';
    
    // Find orders with this payment intent ID
    const ordersQuery = await db
      .collection('Order')
      .where('paymentInfo.paymentIntentId', '==', paymentIntentId)
      .get();

    if (ordersQuery.empty) {
      console.error('No orders found for payment intent:', paymentIntentId);
      return;
    }

    // Update all orders to paid status
    const updatePromises = ordersQuery.docs.map(async (orderDoc) => {
      await orderDoc.ref.update({
        'paymentInfo.status': 'paid',
        'paymentInfo.method': paymentMethodType,
        'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
        status: 'processing',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'processing',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          note: 'Payment received',
        }),
      });

      // Send notification to seller
      // TODO: Implement notification system
      console.log(`Order ${orderDoc.id} marked as paid`);
    });

    await Promise.all(updatePromises);

  } catch (error) {
    console.error('Error handling payment paid:', error);
  }
}

// Handle failed payment
async function handlePaymentFailed(eventData: any) {
  try {
    const paymentIntentId = eventData.attributes.payment_intent_id;
    const failureReason = eventData.attributes.failure_reason || 'Payment failed';
    
    // Find orders with this payment intent ID
    const ordersQuery = await db
      .collection('Order')
      .where('paymentInfo.paymentIntentId', '==', paymentIntentId)
      .get();

    if (ordersQuery.empty) {
      console.error('No orders found for payment intent:', paymentIntentId);
      return;
    }

    // Update all orders to failed status
    const updatePromises = ordersQuery.docs.map(async (orderDoc) => {
      await orderDoc.ref.update({
        'paymentInfo.status': 'failed',
        'paymentInfo.failureReason': failureReason,
        status: 'cancelled',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'cancelled',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          note: `Payment failed: ${failureReason}`,
        }),
      });

      console.log(`Order ${orderDoc.id} marked as failed`);
    });

    await Promise.all(updatePromises);

  } catch (error) {
    console.error('Error handling payment failed:', error);
  }
}

// Handle successful checkout session payment
async function handleCheckoutSessionPaid(eventData: any) {
  try {
    const checkoutSessionId = eventData.id;
    const paymentMethodType = eventData.attributes.payment_method_used?.type || 'card';
    
    // Find order with this checkout session ID
    const ordersQuery = await db
      .collection('Order')
      .where('checkoutSessionId', '==', checkoutSessionId)
      .get();

    if (ordersQuery.empty) {
      console.error('No order found for checkout session:', checkoutSessionId);
      return;
    }

    // Update order to paid status
    const orderDoc = ordersQuery.docs[0];
    await orderDoc.ref.update({
      status: 'processing',
      'paymentInfo.status': 'paid',
      'paymentInfo.method': paymentMethodType,
      'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: 'processing',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        note: 'Payment confirmed via checkout session',
      }),
    });

    console.log(`Order ${orderDoc.id} marked as paid via checkout session ${checkoutSessionId}`);

  } catch (error) {
    console.error('Error handling checkout session payment:', error);
  }
}

// Handle failed checkout session payment
async function handleCheckoutSessionFailed(eventData: any) {
  try {
    const checkoutSessionId = eventData.id;
    const failureReason = eventData.attributes.failure_reason || 'Payment failed';
    
    // Find order with this checkout session ID
    const ordersQuery = await db
      .collection('Order')
      .where('checkoutSessionId', '==', checkoutSessionId)
      .get();

    if (ordersQuery.empty) {
      console.error('No order found for checkout session:', checkoutSessionId);
      return;
    }

    // Update order to failed status
    const orderDoc = ordersQuery.docs[0];
    await orderDoc.ref.update({
      status: 'cancelled',
      'paymentInfo.status': 'failed',
      'paymentInfo.failureReason': failureReason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: 'cancelled',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        note: `Payment failed via checkout session: ${failureReason}`,
      }),
    });

    console.log(`Order ${orderDoc.id} marked as failed due to checkout session payment failure`);

  } catch (error) {
    console.error('Error handling checkout session failure:', error);
  }
}

// Get order details
export const getOrder = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { orderId } = data;
    
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'Order ID is required');
    }

    const orderDoc = await db.collection('Order').doc(orderId).get();
    
    if (!orderDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }

    const orderData = orderDoc.data();
    const userId = context.auth.uid;

    // Check if user is authorized to view this order
    if (orderData?.userId !== userId && !orderData?.sellerIds?.includes(userId)) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to view this order');
    }

    return {
      success: true,
      data: {
        id: orderDoc.id,
        ...orderData,
      },
    };

  } catch (error) {
    console.error('Error getting order:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError('internal', 'Failed to get order', error);
  }
});

// Get user's orders with pagination
export const getUserOrders = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = context.auth.uid;
    const { limit = 20, startAfter } = data;

    let query = db
      .collection('Order')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit);

    if (startAfter) {
      const startAfterDoc = await db.collection('Order').doc(startAfter).get();
      query = query.startAfter(startAfterDoc);
    }

    const ordersSnapshot = await query.get();
    
    const orders = ordersSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    }));

    return {
      success: true,
      data: {
        orders: orders,
        hasMore: ordersSnapshot.docs.length === limit,
        lastOrderId: ordersSnapshot.docs.length > 0 
          ? ordersSnapshot.docs[ordersSnapshot.docs.length - 1].id 
          : null,
      },
    };

  } catch (error) {
    console.error('Error getting user orders:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    throw new functions.https.HttpsError('internal', 'Failed to get orders', error);
  }
});
