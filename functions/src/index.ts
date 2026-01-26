// Firebase Functions entry point
// This file exports all functions from separate module files

// Export the createCheckoutSession function
export { createCheckoutSession } from './createCheckoutSession';

// Export the Cash on Delivery order creation function
export { createCodOrder } from './createCodOrder';

// Export the Paymongo webhook handler and order expiration scheduler
export { handlePaymongoWebhook, expirePendingOrders } from './paymongoWebhookHandler';

// Export the JRS shipping calculator functions
export { calculateJRSShipping } from './jrsShippingCalculator';

// Export the JRS tracking function
export { trackJRSShipping } from './trackJRSShipping';

// Export the cancel order function
export { cancelOrder } from './cancelOrder';

// Export the request return function
export { requestReturn } from './requestReturn';

// Export the complete order function
export { completeOrder } from './completeOrder';

// Export the auto-complete orders scheduled function
export { autoCompleteOrders } from './autoCompleteOrders';

// Export notification functions
export {
  notifySellerOnNewOrder,
  notifyBuyerOnOrderStatusChange,
  notifyOnNewMessage,
  sendPromotionalNotification,
  cleanupFCMTokenOnUserDelete
} from './notifications';

// Export the retry pending refunds scheduled function
export { retryPendingRefunds } from './retryPendingRefunds';

// Export the migration function for confirmed orders
export { migrateConfirmedOrders } from './migrateConfirmedOrders';
