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

// ====================================
// CHECKOUT FUNCTIONS
// ====================================

// Create Paymongo Checkout Session (New preferred method)
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

        // TODO: Implement checkout session creation logic
        // This would involve:
        // 1. Fetch cart items from Firestore
        // 2. Calculate totals
        // 3. Create order in Firestore
        // 4. Create Paymongo checkout session
        // 5. Return order and checkout session data

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
            cart_item_ids: cartItemIds,
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

      } catch (error: any) {
        console.error('Error creating checkout session:', error);
        response.status(error.message.includes('authenticated') ? 401 : 500).json({
          success: false,
          error: error.message || 'Failed to create checkout session'
        });
      }
    });
  });

// Create Payment Intent (Legacy method)
export const createPaymentIntent = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '512MB',
    timeoutSeconds: 240
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        const userId = await verifyAuth(request);
        
        // TODO: Implement payment intent creation logic
        response.status(501).json({
          success: false,
          error: 'Payment intent creation not yet implemented'
        });

      } catch (error: any) {
        console.error('Error creating payment intent:', error);
        response.status(error.message.includes('authenticated') ? 401 : 500).json({
          success: false,
          error: error.message || 'Failed to create payment intent'
        });
      }
    });
  });

// Paymongo Webhook Handler
export const handlePaymongoWebhook = functions.https.onRequest(async (req, res) => {
  corsHandler(req, res, async () => {
    try {
      // Log the full webhook payload for debugging
      console.log('📬 Received Paymongo webhook - Full payload:', JSON.stringify(req.body, null, 2));

      const webhookData = req.body?.data;
      
      if (!webhookData) {
        console.error('❌ No webhook data received');
        res.status(400).json({
          success: false,
          error: 'Invalid webhook data'
        });
        return;
      }

      const eventType = webhookData.type;
      const eventAttributes = webhookData.attributes;

      console.log(`📬 Processing webhook event: ${eventType}`);
      console.log(`📬 Event attributes:`, JSON.stringify(eventAttributes, null, 2));

      // Handle different webhook events
      switch (eventType) {
        case 'checkout_session.payment.paid':
          await handlePaymentPaid(eventAttributes);
          break;
        
        case 'checkout_session.payment.failed':
          await handlePaymentFailed(eventAttributes);
          break;
        
        case 'checkout_session':
          // Handle checkout session status changes
          console.log(`📬 Checkout session status: ${eventAttributes.status}`);
          if (eventAttributes.status === 'paid') {
            await handlePaymentPaid(eventAttributes);
          } else if (eventAttributes.status === 'failed' || eventAttributes.status === 'expired') {
            await handlePaymentFailed(eventAttributes);
          } else {
            console.log(`🔄 Unhandled checkout session status: ${eventAttributes.status}`);
          }
          break;
        
        case 'payment.paid':
          await handleDirectPaymentPaid(eventAttributes);
          break;
        
        case 'payment.failed':
          await handleDirectPaymentFailed(eventAttributes);
          break;
        
        default:
          console.log(`🔄 Unhandled webhook event type: ${eventType}`);
      }

      res.status(200).json({
        success: true,
        message: 'Webhook processed successfully'
      });

    } catch (error: any) {
      console.error('❌ Error handling webhook:', error);
      res.status(500).json({
        success: false,
        error: 'Webhook processing failed'
      });
    }
  });
});

// Helper function to handle successful payments
async function handlePaymentPaid(eventAttributes: any) {
  try {
    const checkoutSessionId = eventAttributes.checkout_session_id;
    // Get order_id from the checkout session metadata
    const orderId = eventAttributes.metadata?.order_id;
    const userId = eventAttributes.metadata?.user_id;
    
    console.log(`✅ Payment successful for checkout session: ${checkoutSessionId}, order: ${orderId}`);

    if (!orderId) {
      console.error('❌ No order ID found in payment webhook');
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

    // Determine payment method from checkout session attributes
    let paymentMethod = 'card'; // default
    if (eventAttributes.payment_method_used) {
      switch (eventAttributes.payment_method_used.toLowerCase()) {
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
        default:
          paymentMethod = 'card';
      }
    }

    // Update order with payment success
    const transactionId = eventAttributes.payment_intent_id || 
                         eventAttributes.id || 
                         checkoutSessionId || 
                         `cs_${Date.now()}`;

    await orderRef.update({
      status: 'confirmed',
      'paymentInfo.status': 'paid',
      'paymentInfo.method': paymentMethod,
      'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
      'paymentInfo.transactionId': transactionId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: 'confirmed',
        timestamp: new Date(),
        note: `Payment confirmed via webhook - Method: ${paymentMethod}`,
      }),
    });

    console.log(`✅ Order ${orderId} updated to confirmed status`);

    // Clear cart items only after successful payment
    if (userId && orderData?.metadata?.cart_item_ids) {
      const cartItemIds = orderData.metadata.cart_item_ids;
      const removeCartPromises = cartItemIds.map(async (cartItemId: string) => {
        await db
          .collection('User')
          .doc(userId)
          .collection('Cart')
          .doc(cartItemId)
          .delete();
      });

      await Promise.all(removeCartPromises);
      console.log(`🗑️ Cleared ${cartItemIds.length} cart items for user ${userId}`);
    }

    // Additional logic: Send confirmation email, update inventory, etc.
    // TODO: Add notification logic here

  } catch (error) {
    console.error('❌ Error handling payment paid:', error);
    throw error;
  }
}

// Helper function to handle failed payments
async function handlePaymentFailed(eventAttributes: any) {
  try {
    const checkoutSessionId = eventAttributes.checkout_session_id;
    // Get order_id from the checkout session metadata
    const orderId = eventAttributes.metadata?.order_id;
    
    console.log(`❌ Payment failed for checkout session: ${checkoutSessionId}, order: ${orderId}`);

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

    // Update order with payment failure
    await orderRef.update({
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
    });

    console.log(`❌ Order ${orderId} updated to payment_failed status`);

  } catch (error) {
    console.error('❌ Error handling payment failed:', error);
    throw error;
  }
}

// Helper function to handle direct payment success (for non-checkout session payments)
async function handleDirectPaymentPaid(eventAttributes: any) {
  try {
    console.log(`✅ Direct payment successful: ${eventAttributes.id}`);
    // Handle direct payment success if needed
    // This is for payments not created through checkout sessions
  } catch (error) {
    console.error('❌ Error handling direct payment paid:', error);
    throw error;
  }
}

// Helper function to handle direct payment failure
async function handleDirectPaymentFailed(eventAttributes: any) {
  try {
    console.log(`❌ Direct payment failed: ${eventAttributes.id}`);
    // Handle direct payment failure if needed
  } catch (error) {
    console.error('❌ Error handling direct payment failed:', error);
    throw error;
  }
}

// ====================================
// PAYMENT VERIFICATION FUNCTION
// ====================================

// Verify payment status by querying Paymongo API
export const verifyPaymentStatus = functions
  .runWith({
    secrets: ['PAYMONGO_SECRET_KEY'],
    memory: '256MB',
    timeoutSeconds: 60
  })
  .https.onRequest(async (request, response) => {
    corsHandler(request, response, async () => {
      try {
        const userId = await verifyAuth(request);
        const { orderId } = request.body;

        if (!orderId) {
          response.status(400).json({
            success: false,
            error: 'Order ID is required'
          });
          return;
        }

        // Get the order
        const orderRef = db.collection('Order').doc(orderId);
        const orderDoc = await orderRef.get();

        if (!orderDoc.exists) {
          response.status(404).json({
            success: false,
            error: 'Order not found'
          });
          return;
        }

        const orderData = orderDoc.data()!;

        // Check if user owns this order
        if (orderData.userId !== userId) {
          response.status(403).json({
            success: false,
            error: 'Access denied'
          });
          return;
        }

        const checkoutSessionId = orderData.checkoutSessionId;
        if (!checkoutSessionId) {
          response.status(400).json({
            success: false,
            error: 'No checkout session found for this order'
          });
          return;
        }

        // Query Paymongo API to get checkout session status
        const PAYMONGO_SECRET_KEY = process.env.PAYMONGO_SECRET_KEY;
        
        try {
          const paymongoResponse = await axios.get(
            `${PAYMONGO_BASE_URL}/checkout_sessions/${checkoutSessionId}`,
            {
              headers: {
                'Authorization': `Basic ${Buffer.from(PAYMONGO_SECRET_KEY + ':').toString('base64')}`,
                'Content-Type': 'application/json',
              },
            }
          );

          const checkoutSession = paymongoResponse.data.data;
          const sessionStatus = checkoutSession.attributes.status;
          const paymentIntentId = checkoutSession.attributes.payment_intent?.id;

          console.log(`🔍 Checkout session ${checkoutSessionId} status: ${sessionStatus}`);

          // If payment is completed but order is still pending, update it
          if (sessionStatus === 'paid' && orderData.status === 'pending') {
            console.log(`🔄 Updating order ${orderId} status from pending to confirmed`);
            
            // Determine payment method
            let paymentMethod = 'card';
            const payments = checkoutSession.attributes.payments || [];
            if (payments.length > 0) {
              const paymentMethodUsed = payments[0].attributes.source?.type;
              switch (paymentMethodUsed) {
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
                default:
                  paymentMethod = 'card';
              }
            }

            await orderRef.update({
              status: 'confirmed',
              'paymentInfo.status': 'paid',
              'paymentInfo.method': paymentMethod,
              'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
              'paymentInfo.transactionId': paymentIntentId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              statusHistory: admin.firestore.FieldValue.arrayUnion({
                status: 'confirmed',
                timestamp: new Date(),
                note: `Payment confirmed via manual verification - Method: ${paymentMethod}`,
              }),
            });

            // Clear cart items
            if (orderData.metadata?.cart_item_ids) {
              const cartItemIds = orderData.metadata.cart_item_ids;
              const removeCartPromises = cartItemIds.map(async (cartItemId: string) => {
                await db
                  .collection('User')
                  .doc(userId)
                  .collection('Cart')
                  .doc(cartItemId)
                  .delete();
              });

              await Promise.all(removeCartPromises);
              console.log(`🗑️ Cleared ${cartItemIds.length} cart items for user ${userId}`);
            }

            response.json({
              success: true,
              message: 'Payment verified and order updated',
              data: {
                orderId,
                status: 'confirmed',
                paymentStatus: 'paid'
              }
            });
          } else {
            response.json({
              success: true,
              message: 'Payment status verified',
              data: {
                orderId,
                status: orderData.status,
                paymentStatus: sessionStatus,
                checkoutSessionStatus: sessionStatus
              }
            });
          }

        } catch (paymongoError: any) {
          console.error('❌ Error querying Paymongo API:', paymongoError);
          response.status(500).json({
            success: false,
            error: 'Failed to verify payment status with Paymongo'
          });
        }

      } catch (error: any) {
        console.error('❌ Error verifying payment status:', error);
        response.status(error.message.includes('authenticated') ? 401 : 500).json({
          success: false,
          error: error.message || 'Failed to verify payment status'
        });
      }
    });
  });

// ====================================
// ORDER MANAGEMENT FUNCTIONS
// ====================================

// Update order status (for sellers/admins)
export const updateOrderStatus = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      const { orderId, status, note } = request.body;

      if (!orderId || !status) {
        response.status(400).json({
          success: false,
          error: 'Order ID and status are required'
        });
        return;
      }

      // Get the order to verify permissions
      const orderRef = db.collection('Order').doc(orderId);
      const orderDoc = await orderRef.get();

      if (!orderDoc.exists) {
        response.status(404).json({
          success: false,
          error: 'Order not found'
        });
        return;
      }

      const orderData = orderDoc.data()!;

      // Check if user has permission to update this order
      // Either the customer or one of the sellers
      if (orderData.userId !== userId && !orderData.sellerIds.includes(userId)) {
        response.status(403).json({
          success: false,
          error: 'Access denied: Cannot update this order'
        });
        return;
      }

      // Update order status
      await orderRef.update({
        status: status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: status,
          timestamp: new Date(),
          note: note || `Status updated to ${status}`,
          updatedBy: userId,
        }),
      });

      response.json({
        success: true,
        message: 'Order status updated successfully'
      });

    } catch (error: any) {
      console.error('Error updating order status:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to update order status'
      });
    }
  });
});

// Cancel order (for customers)
export const cancelOrder = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      const { orderId, reason } = request.body;

      if (!orderId) {
        response.status(400).json({
          success: false,
          error: 'Order ID is required'
        });
        return;
      }

      // Get the order to verify ownership
      const orderRef = db.collection('Order').doc(orderId);
      const orderDoc = await orderRef.get();

      if (!orderDoc.exists) {
        response.status(404).json({
          success: false,
          error: 'Order not found'
        });
        return;
      }

      const orderData = orderDoc.data()!;

      // Check if user owns this order
      if (orderData.userId !== userId) {
        response.status(403).json({
          success: false,
          error: 'Access denied: Cannot cancel this order'
        });
        return;
      }

      // Check if order can be cancelled (only pending and processing orders)
      const currentStatus = orderData.status;
      if (!['pending', 'processing'].includes(currentStatus)) {
        response.status(400).json({
          success: false,
          error: `Cannot cancel order with status: ${currentStatus}`
        });
        return;
      }

      // Update order status to cancelled
      await orderRef.update({
        status: 'cancelled',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        statusHistory: admin.firestore.FieldValue.arrayUnion({
          status: 'cancelled',
          timestamp: new Date(),
          note: reason || 'Order cancelled by customer',
          updatedBy: userId,
        }),
        cancellationInfo: {
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelledBy: userId,
          reason: reason || 'Customer requested cancellation',
        },
      });

      // TODO: Handle refund logic if payment was already processed
      // TODO: Restore inventory if needed
      // TODO: Send cancellation notifications

      response.json({
        success: true,
        message: 'Order cancelled successfully'
      });

    } catch (error: any) {
      console.error('Error cancelling order:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to cancel order'
      });
    }
  });
});

// Get all orders for authenticated user
export const getUserOrders = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      
      // Parse query parameters
      const statusFilter = request.query.status as string;
      const limit = parseInt(request.query.limit as string || '20');
      const offset = parseInt(request.query.offset as string || '0');

      let query = db
        .collection('Order')
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc');

      // Apply status filter if provided
      if (statusFilter) {
        query = query.where('status', '==', statusFilter);
      }

      // Apply pagination
      const ordersSnapshot = await query.limit(limit).offset(offset).get();
      
      const orders = ordersSnapshot.docs.map(doc => ({
        id: doc.id,
        data: doc.data(),
      }));

      response.json({
        success: true,
        data: orders
      });

    } catch (error: any) {
      console.error('Error getting user orders:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to get orders'
      });
    }
  });
});

// Get specific order by ID
export const getOrder = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      
      // Extract order ID from URL path
      const urlParts = request.url.split('/');
      const orderId = urlParts[urlParts.length - 1];

      if (!orderId) {
        response.status(400).json({
          success: false,
          error: 'Order ID is required'
        });
        return;
      }

      const orderDoc = await db.collection('Order').doc(orderId).get();
      
      if (!orderDoc.exists) {
        response.status(404).json({
          success: false,
          error: 'Order not found'
        });
        return;
      }

      const orderData = orderDoc.data();
      
      // Verify order belongs to the authenticated user
      if (orderData?.userId !== userId) {
        response.status(403).json({
          success: false,
          error: 'Access denied: Order does not belong to current user'
        });
        return;
      }

      response.json({
        success: true,
        data: {
          id: orderDoc.id,
          data: orderData
        }
      });

    } catch (error: any) {
      console.error('Error getting order:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to get order'
      });
    }
  });
});

// Get order statistics for authenticated user
export const getOrderStatistics = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      
      // Get all orders for the user
      const ordersSnapshot = await db
        .collection('Order')
        .where('userId', '==', userId)
        .get();

      let totalOrders = 0;
      let totalSpent = 0;
      let deliveredOrders = 0;
      let pendingOrders = 0;
      let processingOrders = 0;
      let shippedOrders = 0;
      let cancelledOrders = 0;

      ordersSnapshot.docs.forEach(doc => {
        const orderData = doc.data();
        totalOrders++;
        
        // Add to total spent
        if (orderData.summary?.total) {
          totalSpent += orderData.summary.total;
        }

        // Count by status
        switch (orderData.status) {
          case 'delivered':
            deliveredOrders++;
            break;
          case 'pending':
            pendingOrders++;
            break;
          case 'processing':
            processingOrders++;
            break;
          case 'shipped':
            shippedOrders++;
            break;
          case 'cancelled':
            cancelledOrders++;
            break;
        }
      });

      response.json({
        success: true,
        data: {
          totalOrders,
          totalSpent,
          deliveredOrders,
          pendingOrders,
          processingOrders,
          shippedOrders,
          cancelledOrders
        }
      });

    } catch (error: any) {
      console.error('Error getting order statistics:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to get order statistics'
      });
    }
  });
});

// Search orders by query
export const searchOrders = functions.https.onRequest(async (request, response) => {
  corsHandler(request, response, async () => {
    try {
      const userId = await verifyAuth(request);
      
      const query = request.query.q as string;
      
      if (!query || query.trim().length === 0) {
        response.status(400).json({
          success: false,
          error: 'Search query is required'
        });
        return;
      }

      // Get all orders for the user
      const ordersSnapshot = await db
        .collection('Order')
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .get();

      const searchTerm = query.toLowerCase().trim();
      const matchingOrders: any[] = [];

      ordersSnapshot.docs.forEach(doc => {
        const orderData = doc.data();
        const orderId = doc.id.toLowerCase();
        
        // Search in order ID
        if (orderId.includes(searchTerm)) {
          matchingOrders.push({
            id: doc.id,
            data: orderData
          });
          return;
        }

        // Search in order items (product names)
        if (orderData.items && Array.isArray(orderData.items)) {
          const hasMatchingItem = orderData.items.some((item: any) => 
            item.productName && item.productName.toLowerCase().includes(searchTerm)
          );
          
          if (hasMatchingItem) {
            matchingOrders.push({
              id: doc.id,
              data: orderData
            });
          }
        }
      });

      response.json({
        success: true,
        data: matchingOrders
      });

    } catch (error: any) {
      console.error('Error searching orders:', error);
      response.status(error.message.includes('authenticated') ? 401 : 500).json({
        success: false,
        error: error.message || 'Failed to search orders'
      });
    }
  });
});
