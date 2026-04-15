import * as admin from 'firebase-admin';

export interface VoucherValidationResult {
  discountAmount: number;
  freeShipping: boolean;
  voucherData: admin.firestore.DocumentData | null;
  voucherDocId: string | null;
  voucherCode: string | null;
}

export interface FreeDeliveryResult {
  freeShipping: boolean;
  voucherDocId: string | null;
}

/**
 * Validate a selected voucher against Firestore and calculate the discount.
 * Returns discountAmount, freeShipping flag, and doc ID for usage tracking.
 */
export async function validateAndApplyVoucher(
  sellerId: string,
  voucherInfo: { code: string; seller_id: string; discount_type: string } | null,
  sellerCartValue: number,
  db: admin.firestore.Firestore
): Promise<VoucherValidationResult> {
  const empty: VoucherValidationResult = {
    discountAmount: 0,
    freeShipping: false,
    voucherData: null,
    voucherDocId: null,
    voucherCode: null,
  };

  if (!voucherInfo || !voucherInfo.code) {
    return empty;
  }

  // Query Vouchers collection by sellerId + code + active status
  const voucherSnapshot = await db
    .collection('Vouchers')
    .where('sellerId', '==', sellerId)
    .where('code', '==', voucherInfo.code)
    .where('status', '==', 'active')
    .limit(1)
    .get();

  if (voucherSnapshot.empty) {
    console.warn(`Voucher ${voucherInfo.code} not found or inactive for seller ${sellerId}`);
    return empty;
  }

  const voucherDoc = voucherSnapshot.docs[0];
  const voucher = voucherDoc.data();
  const voucherDocId = voucherDoc.id;

  // Validate dates
  const now = new Date();
  if (voucher.startDate) {
    const startDate = voucher.startDate.toDate
      ? voucher.startDate.toDate()
      : new Date(voucher.startDate);
    if (now < startDate) {
      console.warn(`Voucher ${voucherInfo.code} not yet active`);
      return empty;
    }
  }
  if (voucher.endDate) {
    const endDate = voucher.endDate.toDate
      ? voucher.endDate.toDate()
      : new Date(voucher.endDate);
    if (now > endDate) {
      console.warn(`Voucher ${voucherInfo.code} has expired`);
      return empty;
    }
  }

  // Validate usage count
  if (voucher.maxUses > 0 && voucher.usedCount >= voucher.maxUses) {
    console.warn(`Voucher ${voucherInfo.code} has reached max uses`);
    return empty;
  }

  // Validate minimum order amount
  if (voucher.minimumOrderAmount && sellerCartValue < voucher.minimumOrderAmount) {
    console.warn(
      `Cart value ${sellerCartValue} below minimum ${voucher.minimumOrderAmount} for voucher ${voucherInfo.code}`
    );
    return empty;
  }

  // Calculate discount based on type
  let discountAmount = 0;
  let freeShipping = false;

  if (voucher.discountType === 'percentage') {
    discountAmount = sellerCartValue * (voucher.discountValue / 100);
    if (voucher.maximumSpend && discountAmount > voucher.maximumSpend) {
      discountAmount = voucher.maximumSpend;
    }
    discountAmount = Math.min(discountAmount, sellerCartValue);
  } else if (voucher.discountType === 'fixed') {
    discountAmount = Math.min(voucher.discountValue || 0, sellerCartValue);
  } else if (voucher.discountType === 'free_delivery') {
    freeShipping = true;
  }

  return {
    discountAmount,
    freeShipping,
    voucherData: voucher,
    voucherDocId,
    voucherCode: voucherInfo.code,
  };
}

/**
 * Check if a seller has an active free_delivery voucher and whether the
 * post-discount cart value meets the minimum order threshold.
 */
export async function checkFreeDeliveryEligibility(
  sellerId: string,
  postDiscountCartValue: number,
  db: admin.firestore.Firestore
): Promise<FreeDeliveryResult> {
  const snapshot = await db
    .collection('Vouchers')
    .where('sellerId', '==', sellerId)
    .where('discountType', '==', 'free_delivery')
    .where('status', '==', 'active')
    .limit(1)
    .get();

  if (snapshot.empty) {
    return { freeShipping: false, voucherDocId: null };
  }

  const voucher = snapshot.docs[0].data();
  const minAmount = voucher.minimumOrderAmount || 0;

  // Use post-discount cart value for threshold check
  if (postDiscountCartValue >= minAmount) {
    return { freeShipping: true, voucherDocId: snapshot.docs[0].id };
  }

  return { freeShipping: false, voucherDocId: null };
}

/**
 * Increment usedCount on validated voucher documents after order creation.
 */
export async function incrementVoucherUsage(
  voucherDocIds: string[],
  db: admin.firestore.Firestore
): Promise<void> {
  if (voucherDocIds.length === 0) return;

  const batch = db.batch();
  for (const docId of voucherDocIds) {
    batch.update(db.collection('Vouchers').doc(docId), {
      usedCount: admin.firestore.FieldValue.increment(1),
    });
  }
  await batch.commit();
}
