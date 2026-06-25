import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

const db = getFirestore();

export const deactivateOutOfStockProducts = onSchedule({
  schedule: 'every 1 hours',
  timeZone: 'Asia/Manila',
  region: 'asia-southeast1',
}, async (_event) => {
  logger.info('Starting deactivate out-of-stock products job');

  try {
    const activeProductsSnapshot = await db.collection('Product')
      .where('isActive', '==', true)
      .where('status', '==', 'active')
      .get();

    if (activeProductsSnapshot.empty) {
      logger.info('No active products found');
      return;
    }

    logger.info(`Checking ${activeProductsSnapshot.size} active products for out-of-stock variations`);

    const batch = db.batch();
    let deactivatedCount = 0;

    for (const productDoc of activeProductsSnapshot.docs) {
      const productId = productDoc.id;

      const variationsSnapshot = await db
        .collection('Product')
        .doc(productId)
        .collection('Variation')
        .get();

      if (variationsSnapshot.empty) continue;

      const allOutOfStock = variationsSnapshot.docs.every(
        (v) => (v.data().stock ?? 0) <= 0
      );

      if (!allOutOfStock) continue;

      batch.update(db.collection('Product').doc(productId), {
        isActive: false,
        status: 'inactive',
        updatedAt: FieldValue.serverTimestamp(),
      });

      deactivatedCount++;
      logger.info(`Deactivating product ${productId} — all ${variationsSnapshot.size} variation(s) have 0 stock`);
    }

    if (deactivatedCount > 0) {
      await batch.commit();
      logger.info(`Deactivated ${deactivatedCount} out-of-stock product(s)`);
    } else {
      logger.info('All active products have at least one variation with stock');
    }

  } catch (error) {
    logger.error('Error in deactivate out-of-stock products job', {
      error: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined,
    });
  }
});
