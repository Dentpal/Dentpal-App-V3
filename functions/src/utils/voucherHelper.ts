import * as admin from 'firebase-admin';

export interface VoucherValidationResult {
  discountAmount: number;
  voucherData: admin.firestore.DocumentData | null;
  voucherDocId: string | null;
  voucherCode: string | null;
}

export interface ShippingVoucherResult {
  coversStandard: boolean;
  coversExpress: boolean;
  voucherData: admin.firestore.DocumentData | null;
  voucherDocId: string | null;
  voucherCode: string | null;
}

/**
 * Parse a voucher's `shippingOption` array into the set of covered modes.
 * Legacy/missing/empty → standard only. The literal value `'both'` expands to
 * both modes.
 */
function parseShippingCoverage(shippingOption: unknown): { coversStandard: boolean; coversExpress: boolean } {
  if (!Array.isArray(shippingOption) || shippingOption.length === 0) {
    return { coversStandard: true, coversExpress: false };
  }
  let coversStandard = false;
  let coversExpress = false;
  for (const raw of shippingOption) {
    const value = typeof raw === 'string' ? raw.toLowerCase().trim() : '';
    if (value === 'both') {
      coversStandard = true;
      coversExpress = true;
    } else if (value === 'standard') {
      coversStandard = true;
    } else if (value === 'express') {
      coversExpress = true;
    }
  }
  if (!coversStandard && !coversExpress) {
    return { coversStandard: true, coversExpress: false };
  }
  return { coversStandard, coversExpress };
}

async function fetchAndValidateVoucher(
  sellerId: string,
  code: string,
  sellerCartValue: number,
  db: admin.firestore.Firestore,
): Promise<{ doc: admin.firestore.QueryDocumentSnapshot; data: admin.firestore.DocumentData } | null> {
  const voucherSnapshot = await db
    .collection('Vouchers')
    .where('sellerId', '==', sellerId)
    .where('code', '==', code)
    .where('status', '==', 'active')
    .limit(1)
    .get();

  if (voucherSnapshot.empty) {
    console.warn(`Voucher ${code} not found or inactive for seller ${sellerId}`);
    return null;
  }

  const voucherDoc = voucherSnapshot.docs[0];
  const voucher = voucherDoc.data();

  const now = new Date();
  if (voucher.startDate) {
    const startDate = voucher.startDate.toDate
      ? voucher.startDate.toDate()
      : new Date(voucher.startDate);
    if (now < startDate) {
      console.warn(`Voucher ${code} not yet active`);
      return null;
    }
  }
  if (voucher.endDate) {
    const endDate = voucher.endDate.toDate
      ? voucher.endDate.toDate()
      : new Date(voucher.endDate);
    if (now > endDate) {
      console.warn(`Voucher ${code} has expired`);
      return null;
    }
  }

  if (voucher.maxUses > 0 && voucher.usedCount >= voucher.maxUses) {
    console.warn(`Voucher ${code} has reached max uses`);
    return null;
  }

  if (voucher.minimumOrderAmount && sellerCartValue < voucher.minimumOrderAmount) {
    console.warn(
      `Cart value ${sellerCartValue} below minimum ${voucher.minimumOrderAmount} for voucher ${code}`,
    );
    return null;
  }

  return { doc: voucherDoc, data: voucher };
}

/**
 * Validate a discount voucher (percentage or fixed) and compute its discount.
 *
 * Reject `free_delivery` vouchers — those go through `validateAndApplyShippingVoucher`.
 */
export async function validateAndApplyVoucher(
  sellerId: string,
  voucherInfo: { code: string; seller_id: string; discount_type: string } | null,
  sellerCartValue: number,
  db: admin.firestore.Firestore,
): Promise<VoucherValidationResult> {
  const empty: VoucherValidationResult = {
    discountAmount: 0,
    voucherData: null,
    voucherDocId: null,
    voucherCode: null,
  };

  if (!voucherInfo || !voucherInfo.code) {
    return empty;
  }

  const found = await fetchAndValidateVoucher(sellerId, voucherInfo.code, sellerCartValue, db);
  if (!found) return empty;

  const { doc: voucherDoc, data: voucher } = found;

  if (voucher.discountType === 'free_delivery') {
    console.warn(
      `Voucher ${voucherInfo.code} is a free_delivery voucher; ignoring as a discount voucher (use shipping voucher slot)`,
    );
    return empty;
  }

  if (voucher.shippingOption !== undefined) {
    console.warn(
      `Voucher ${voucherInfo.code} has shippingOption set on a non-free_delivery voucher; field ignored`,
    );
  }

  let discountAmount = 0;
  if (voucher.discountType === 'percentage') {
    discountAmount = sellerCartValue * (voucher.discountValue / 100);
    if (voucher.maximumSpend && discountAmount > voucher.maximumSpend) {
      discountAmount = voucher.maximumSpend;
    }
    discountAmount = Math.min(discountAmount, sellerCartValue);
  } else if (voucher.discountType === 'fixed') {
    discountAmount = Math.min(voucher.discountValue || 0, sellerCartValue);
  }

  // Round to 2 decimals to keep currency math consistent with the frontend.
  discountAmount = Math.round(discountAmount * 100) / 100;

  return {
    discountAmount,
    voucherData: voucher,
    voucherDocId: voucherDoc.id,
    voucherCode: voucherInfo.code,
  };
}

/**
 * Validate a shipping voucher and return which modes it covers.
 *
 * Requires `discountType === 'free_delivery'`. Other voucher types are rejected.
 */
export async function validateAndApplyShippingVoucher(
  sellerId: string,
  voucherInfo: { code: string; seller_id: string; discount_type: string; shipping_option?: unknown } | null,
  sellerCartValue: number,
  db: admin.firestore.Firestore,
): Promise<ShippingVoucherResult> {
  const empty: ShippingVoucherResult = {
    coversStandard: false,
    coversExpress: false,
    voucherData: null,
    voucherDocId: null,
    voucherCode: null,
  };

  if (!voucherInfo || !voucherInfo.code) {
    return empty;
  }

  const found = await fetchAndValidateVoucher(sellerId, voucherInfo.code, sellerCartValue, db);
  if (!found) return empty;

  const { doc: voucherDoc, data: voucher } = found;

  if (voucher.discountType !== 'free_delivery') {
    console.warn(
      `Voucher ${voucherInfo.code} is not a free_delivery voucher; cannot apply as shipping voucher`,
    );
    return empty;
  }

  const { coversStandard, coversExpress } = parseShippingCoverage(voucher.shippingOption);

  return {
    coversStandard,
    coversExpress,
    voucherData: voucher,
    voucherDocId: voucherDoc.id,
    voucherCode: voucherInfo.code,
  };
}

/**
 * Increment usedCount on validated voucher documents after order creation.
 */
export async function incrementVoucherUsage(
  voucherDocIds: string[],
  db: admin.firestore.Firestore,
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
