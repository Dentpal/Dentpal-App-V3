import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import axios from 'axios';
import cors = require('cors');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

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
      try {
        console.log('📬 Received Paymongo webhook:', JSON.stringify(req.body, null, 2));

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

    await orderRef.update({
      status: orderStatus,
      'paymentInfo.status': finalStatus,
      'paymentInfo.method': paymentMethod,
      'paymentInfo.paidAt': admin.firestore.FieldValue.serverTimestamp(),
      'paymentInfo.paymentIntentId': transactionId,
      'paymentInfo.checkoutSessionId': checkoutSessionId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusHistory: admin.firestore.FieldValue.arrayUnion({
        status: orderStatus,
        timestamp: new Date(),
        note: `Payment ${finalStatus} via ${paymentMethod}`,
      }),
    });

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
