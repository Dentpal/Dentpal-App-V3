import {onDocumentCreated, onDocumentUpdated, onDocumentDeleted} from 'firebase-functions/v2/firestore';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onValueCreated} from 'firebase-functions/v2/database';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin (if not already initialized)
if (admin.apps.length === 0) {
  admin.initializeApp({
    databaseURL: 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app',
  });
}

const db = admin.firestore();
const rtdb = admin.database();
const messaging = admin.messaging();

/**
 * Send notification when a new order is created
 */
export const notifySellerOnNewOrder = onDocumentCreated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    
    const order = snap.data();
    const { sellerId, buyerId, totalAmount } = order;
    const orderId = event.params.orderId;

    try {
      // Get seller's FCM token
      const sellerDoc = await db.collection('User').doc(sellerId).get();
      const sellerData = sellerDoc.data();
      const fcmToken = sellerData?.fcmToken;

      if (!fcmToken) {
        console.log(`No FCM token found for seller: ${sellerId}`);
        return;
      }

      // Get buyer's name
      const buyerDoc = await db.collection('User').doc(buyerId).get();
      const buyerName = buyerDoc.data()?.displayName || 'A customer';

      // Send notification
      const message = {
        token: fcmToken,
        notification: {
          title: 'New Order Received!',
          body: `${buyerName} placed an order worth ₱${totalAmount.toFixed(2)}`,
        },
        data: {
          type: 'order',
          orderId: orderId,
          action: 'view_order',
        },
        android: {
          priority: 'high' as const,
          collapseKey: 'new_orders', // Consolidate new order notifications
          notification: {
            channelId: 'dentpal_channel',
            sound: 'default',
            icon: 'launcher_icon',
            tag: 'new_orders', // Replace previous new order notification
            notificationCount: 1,
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-collapse-id': 'new_orders', // iOS consolidation
          },
          payload: {
            aps: {
              alert: {
                title: 'New Order Received!',
                body: `${buyerName} placed an order worth ₱${totalAmount.toFixed(2)}`,
              },
              sound: 'default',
              badge: 1,
              'content-available': 1,
              'mutable-content': 1,
              'thread-id': 'new_orders', // iOS grouping
            },
          },
        },
      };

      await messaging.send(message);
      console.log(`Notification sent to seller: ${sellerId} for order: ${orderId}`);

      // Save notification to user's subcollection
      await db.collection('User').doc(sellerId).collection('user_notifications').add({
        title: 'New Order Received!',
        body: `${buyerName} placed an order worth ₱${totalAmount.toFixed(2)}`,
        type: 'order',
        data: {
          orderId: orderId,
          action: 'view_order',
        },
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('Error sending notification:', error);
    }
  }
);

/**
 * Send notification when order status changes
 */
export const notifyBuyerOnOrderStatusChange = onDocumentUpdated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const newSnap = event.data?.after;
    const oldSnap = event.data?.before;
    
    if (!newSnap || !oldSnap) return;
    
    const newData = newSnap.data();
    const oldData = oldSnap.data();
    const orderId = event.params.orderId;

    console.log(`Order update detected for ${orderId}:`, {
      oldStatus: oldData.status,
      newStatus: newData.status,
      oldFulfillmentStage: oldData.fulfillmentStage,
      newFulfillmentStage: newData.fulfillmentStage,
    });

    // Check if either status or fulfillmentStage changed
    const statusChanged = newData.status !== oldData.status;
    const fulfillmentStageChanged = newData.fulfillmentStage !== oldData.fulfillmentStage;

    if (!statusChanged && !fulfillmentStageChanged) {
      console.log(`No status or fulfillment stage change for order ${orderId}, skipping notification`);
      return;
    }

    const { buyerId, userId, status, fulfillmentStage } = newData;
    const actualBuyerId = buyerId || userId;

    if (!actualBuyerId) {
      console.log(`No buyer ID found for order ${orderId}`);
      return;
    }

    try {
      // Get buyer's FCM token
      const buyerDoc = await db.collection('User').doc(actualBuyerId).get();
      const buyerData = buyerDoc.data();
      const fcmToken = buyerData?.fcmToken;

      if (!fcmToken) {
        console.log(`No FCM token found for buyer: ${actualBuyerId}`);
        return;
      }

      // Create status-specific message
      let title = 'Order Update';
      let body = `Your order status has been updated`;

      // First check if fulfillmentStage changed (for to_ship status)
      if (fulfillmentStageChanged && status === 'to_ship') {
        switch (fulfillmentStage) {
          case 'to-pack':
            title = 'Order Being Prepared';
            body = 'Your order is being packed and prepared for shipment';
            break;
          case 'to-arrangement':
            title = 'Order Arranged';
            body = 'Your order has been arranged and is almost ready to ship';
            break;
          case 'to-hand-over':
            title = 'Order Ready for Pickup';
            body = 'Your order is ready to be handed over to the courier';
            break;
        }
      }
      // Then check if main status changed
      else if (statusChanged) {
        switch (status) {
        case 'confirmed':
          title = 'Order Confirmed';
          body = 'Your order has been confirmed and is being prepared';
          break;
        case 'to_ship':
          title = 'Order Ready to Ship';
          body = 'Your order is being prepared for shipment';
          break;
        case 'processing':
        case 'shipping':
        case 'shipped':
          title = 'Order Shipped';
          body = 'Your order is on its way! You will receive it soon.';
          break;
        case 'delivered':
          title = 'Order Delivered';
          body = 'Your order has been delivered. Enjoy your products!';
          break;
        case 'completed':
          title = 'Order Completed';
          body = 'Thank you for confirming receipt of your order!';
          break;
        case 'cancelled':
          title = 'Order Cancelled';
          body = 'Your order has been cancelled';
          break;
        case 'return_requested':
          title = 'Return Requested';
          body = 'Your return request has been received and is being reviewed';
          break;
        case 'return_approved':
          title = 'Return Approved';
          body = 'Your return request has been approved';
          break;
        case 'return_rejected':
          title = 'Return Rejected';
          body = 'Your return request has been rejected';
          break;
        case 'returned':
          title = 'Order Returned';
          body = 'Your order has been returned';
          break;
        case 'refunded':
          title = 'Order Refunded';
          body = 'Your refund has been processed';
          break;
        case 'failed-delivery':
          title = 'Delivery Failed';
          body = 'There was an issue delivering your order. Please contact support.';
          break;
        }
      }

      // Send notification
      const message = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          type: 'order',
          orderId: orderId,
          status,
          action: 'view_order',
        },
        android: {
          priority: 'high' as const,
          collapseKey: 'order_updates', // Consolidate notifications with same key
          notification: {
            channelId: 'dentpal_channel',
            sound: 'default',
            tag: `order_${orderId}`, // Replace previous notifications for same order
            notificationCount: 1,
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-collapse-id': 'order_updates', // iOS consolidation
          },
          payload: {
            aps: {
              alert: {
                title,
                body,
              },
              sound: 'default',
              badge: 1,
              'content-available': 1,
              'mutable-content': 1,
              'thread-id': 'dentpal_orders', // iOS grouping
            },
          },
        },
      };

      await messaging.send(message);
      console.log(`Status update notification sent to buyer: ${actualBuyerId}`);

      // Save notification to user's subcollection
      await db.collection('User').doc(actualBuyerId).collection('user_notifications').add({
        title,
        body,
        type: 'order',
        data: {
          orderId: orderId,
          status,
          action: 'view_order',
        },
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('Error sending notification:', error);
    }
  }
);

/**
 * Send notification when a new message is received in chat
 * Listens to Realtime Database: chatRooms/{chatRoomId}/messages/{messageId}
 */
export const notifyOnNewMessage = onValueCreated(
  {
    ref: 'chatRooms/{chatRoomId}/messages/{messageId}',
    region: 'asia-southeast1',
    instance: 'dentpal-161e5-default-rtdb',
  },
  async (event) => {
    const message = event.data.val();
    if (!message) {
      console.log('No message data found in event');
      return;
    }
    
    console.log('Message data received:', JSON.stringify(message));
    
    const { senderId, receiverId, message: text, messageType } = message;
    const chatRoomId = event.params.chatRoomId;
    
    console.log(`Processing message in chat ${chatRoomId} from ${senderId} to ${receiverId}`);

    // Don't send notification if message is from system or no text
    if (!senderId || !receiverId || !text) {
      console.log('Skipping notification - missing required fields');
      return;
    }

    // Don't send notification to sender
    const currentUserId = senderId;
    if (currentUserId === receiverId) {
      console.log('Skipping notification - sender is receiver');
      return;
    }

    try {
      // Get receiver's FCM token from Firestore
      const receiverDoc = await db.collection('User').doc(receiverId).get();
      const receiverData = receiverDoc.data();
      const fcmToken = receiverData?.fcmToken;

      if (!fcmToken) {
        console.log(`No FCM token found for receiver: ${receiverId}`);
        return;
      }

      // Get sender's name from Firestore
      const senderDoc = await db.collection('User').doc(senderId).get();
      const senderData = senderDoc.data();
      
      // Try multiple possible name fields for different user types:
      // - Sellers with shopName field (direct shop name)
      // - Sellers with vendor.company.storeName (vendor structure)
      // - Regular users with displayName/fullName
      const senderName = senderData?.shopName || 
                         senderData?.vendor?.company?.storeName ||
                         senderData?.vendor?.company?.name ||
                         senderData?.displayName || 
                         senderData?.fullName || 
                         senderData?.name || 
                         senderData?.firstName || 
                         senderData?.username ||
                         'Someone';
      
      console.log(`Sender name resolved to: ${senderName} for senderId: ${senderId}`);

      // Get chat room data to retrieve other user info
      const chatRoomSnapshot = await rtdb.ref(`chatRooms/${chatRoomId}`).once('value');
      const chatRoomData = chatRoomSnapshot.val();
      
      // Determine other user's name and ID for navigation
      const otherUserId = chatRoomData?.user1Id === receiverId ? chatRoomData?.user2Id : chatRoomData?.user1Id;
      const otherUserName = chatRoomData?.user1Id === receiverId ? chatRoomData?.user2Name : chatRoomData?.user1Name;

      // Format message body: "[Name] sent: [message]" with max 2 lines
      let messageBody = text;
      
      // Handle image messages
      if (messageType === 'image') {
        messageBody = '📷 Photo';
      }
      
      // Truncate to approximately 2 lines (about 80-100 characters)
      const maxLength = 90;
      if (messageBody.length > maxLength) {
        messageBody = messageBody.substring(0, maxLength).trim() + '...';
      }

      // Format: "sent: [message]"
      const notificationBody = `sent: ${messageBody}`;

      // Create a short hash for iOS collapse ID (max 64 bytes)
      // Use only first 32 chars of chatRoomId to stay well under 64 bytes limit
      const shortChatId = chatRoomId.substring(0, 32);
      
      // Send notification
      const fcmMessage = {
        token: fcmToken,
        notification: {
          title: senderName,
          body: notificationBody,
        },
        data: {
          type: 'message',
          chatRoomId: chatRoomId,
          chatId: chatRoomId, // Keep for backward compatibility
          senderId: senderId,
          otherUserId: otherUserId || senderId,
          otherUserName: otherUserName || senderName,
          action: 'open_chat',
        },
        android: {
          priority: 'high' as const,
          collapseKey: `chat_${shortChatId}`, // Consolidate messages from same chat
          notification: {
            channelId: 'dentpal_channel',
            sound: 'default',
            tag: `chat_${shortChatId}`, // Replace previous messages from same chat
            notificationCount: 1,
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            // Use short chat ID to ensure under 64 bytes (chat_ = 5 bytes + 32 = 37 bytes max)
            'apns-collapse-id': `chat_${shortChatId}`,
          },
          payload: {
            aps: {
              alert: {
                title: senderName,
                body: notificationBody,
              },
              sound: 'default',
              badge: 1,
              'content-available': 1,
              'mutable-content': 1,
              'thread-id': `chat_${shortChatId}`,
            },
          },
        },
      };

      await messaging.send(fcmMessage);
      console.log(`Message notification sent to: ${receiverId} for chat: ${chatRoomId}`);

      // Save notification to user's subcollection
      await db.collection('User').doc(receiverId).collection('user_notifications').add({
        title: senderName,
        body: notificationBody,
        type: 'message',
        data: {
          chatRoomId: chatRoomId,
          chatId: chatRoomId,
          senderId: senderId,
          otherUserId: otherUserId || senderId,
          otherUserName: otherUserName || senderName,
          action: 'open_chat',
        },
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('Error sending message notification:', error);
    }
  }
);

/**
 * Send promotional notification to all users (topic)
 */
export const sendPromotionalNotification = onCall(
  {
    region: 'asia-southeast1',
  },
  async (request) => {
    // Check if user is admin
    if (!request.auth?.token.admin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can send promotional notifications'
      );
    }

    const { title, body, topic = 'all_users' } = request.data;

    try {
      const message = {
        topic,
        notification: {
          title,
          body,
        },
        data: {
          type: 'promotion',
          action: 'view_products',
        },
        android: {
          priority: 'normal' as const,
          notification: {
            channelId: 'dentpal_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      };

      await messaging.send(message);
      console.log(`Promotional notification sent to topic: ${topic}`);

      return { success: true, message: 'Notification sent successfully' };
    } catch (error) {
      console.error('Error sending promotional notification:', error);
      throw new HttpsError(
        'internal',
        'Failed to send notification'
      );
    }
  }
);

/**
 * Clean up old FCM tokens on user deletion
 */
export const cleanupFCMTokenOnUserDelete = onDocumentDeleted(
  {
    document: 'users/{userId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    
    const userData = snap.data();
    const fcmToken = userData?.fcmToken;

    if (fcmToken) {
      try {
        // Note: You can't delete tokens via Admin SDK
        // They will expire naturally or be updated when user logs in again
        console.log(`User ${event.params.userId} deleted, FCM token will expire naturally`);
      } catch (error) {
        console.error('Error during FCM cleanup:', error);
      }
    }
  }
);
