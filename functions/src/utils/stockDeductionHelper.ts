import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

const db = getFirestore();

/**
 * Deduct stock for order items after order completion
 * Updates Product > Variation stock levels based on order items
 * This is a shared utility used by both manual and automatic order completion
 */
export async function deductStockForOrder(orderId: string, orderItems: any[]): Promise<void> {
  if (!orderItems || orderItems.length === 0) {
    logger.warn(`No items to deduct stock for order ${orderId}`);
    return;
  }

  const stockUpdates: Array<{ 
    success: boolean; 
    productId: string; 
    variationId?: string; 
    quantity: number; 
    error?: string 
  }> = [];

  for (const item of orderItems) {
    try {
      const productId = item.productId;
      const variationId = item.variationId;
      const quantity = Number(item.quantity) || 0;

      if (!productId) {
        logger.warn(`Order ${orderId}: Item missing productId, skipping stock deduction`, { item });
        stockUpdates.push({ success: false, productId: 'unknown', quantity, error: 'Missing productId' });
        continue;
      }

      if (quantity <= 0) {
        logger.warn(`Order ${orderId}: Invalid quantity for product ${productId}, skipping`, { quantity });
        stockUpdates.push({ success: false, productId, variationId, quantity, error: 'Invalid quantity' });
        continue;
      }

      // If there's a variationId, update the variation stock
      if (variationId) {
        const variationRef = db.collection('Product').doc(productId).collection('Variation').doc(variationId);
        const variationDoc = await variationRef.get();

        if (!variationDoc.exists) {
          logger.warn(`Order ${orderId}: Variation ${variationId} not found for product ${productId}`, { item });
          stockUpdates.push({ success: false, productId, variationId, quantity, error: 'Variation not found' });
          continue;
        }

        const currentStock = Number(variationDoc.data()?.stock) || 0;
        const newStock = Math.max(0, currentStock - quantity);

        await variationRef.update({
          stock: newStock,
          updatedAt: FieldValue.serverTimestamp(),
        });

        logger.info(`Order ${orderId}: Deducted ${quantity} from variation ${variationId} stock (${currentStock} → ${newStock})`, {
          productId,
          variationId,
          previousStock: currentStock,
          newStock,
          deducted: quantity,
        });

        stockUpdates.push({ success: true, productId, variationId, quantity });
      } else {
        // If no variationId, update the product-level stock (if it exists)
        const productRef = db.collection('Product').doc(productId);
        const productDoc = await productRef.get();

        if (!productDoc.exists) {
          logger.warn(`Order ${orderId}: Product ${productId} not found`, { item });
          stockUpdates.push({ success: false, productId, quantity, error: 'Product not found' });
          continue;
        }

        const productData = productDoc.data();
        const currentStock = Number(productData?.inStock) || 0;
        const newStock = Math.max(0, currentStock - quantity);

        await productRef.update({
          inStock: newStock,
          updatedAt: FieldValue.serverTimestamp(),
        });

        logger.info(`Order ${orderId}: Deducted ${quantity} from product ${productId} stock (${currentStock} → ${newStock})`, {
          productId,
          previousStock: currentStock,
          newStock,
          deducted: quantity,
        });

        stockUpdates.push({ success: true, productId, quantity });
      }

      // Update the product's updatedAt timestamp to trigger UI refreshes
      const productRef = db.collection('Product').doc(productId);
      await productRef.update({
        updatedAt: FieldValue.serverTimestamp(),
      });

    } catch (error) {
      logger.error(`Order ${orderId}: Failed to deduct stock for item`, {
        item,
        error: error instanceof Error ? error.message : 'Unknown error',
      });
      stockUpdates.push({
        success: false,
        productId: item.productId || 'unknown',
        variationId: item.variationId,
        quantity: item.quantity,
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }

  // Log summary
  const successCount = stockUpdates.filter(u => u.success).length;
  const failureCount = stockUpdates.filter(u => !u.success).length;

  logger.info(`Order ${orderId}: Stock deduction summary`, {
    totalItems: orderItems.length,
    successful: successCount,
    failed: failureCount,
    updates: stockUpdates,
  });
}
