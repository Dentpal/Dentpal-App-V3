import * as admin from 'firebase-admin';

export type OrderItem = {
  sellerId?: string;
  productName?: string;
  productImage?: string;
  price?: number;
  quantity?: number;
  total?: number;
};

export type SellerFeeBreakdown = {
  sellerId?: string;
  sellerName?: string;
  cartValue?: number;
  buyerShippingCharge?: number;
  totalChargedToBuyer?: number;
};

export type ShippingInfo = {
  fullName?: string;
  phoneNumber?: string;
  addressLine1?: string;
  addressLine2?: string | null;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
};

export const peso = (n: unknown): string => {
  const num = typeof n === 'number' && isFinite(n) ? n : 0;
  return `₱${num.toFixed(2)}`;
};

export const escapeHtml = (s: unknown): string =>
  String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

export const formatManilaDateTime = (createdAt: unknown): string => {
  let ms: number | null = null;
  if (createdAt instanceof admin.firestore.Timestamp) {
    ms = createdAt.toMillis();
  } else if (
    createdAt &&
    typeof createdAt === 'object' &&
    typeof (createdAt as { _seconds?: number })._seconds === 'number'
  ) {
    ms = (createdAt as { _seconds: number })._seconds * 1000;
  } else {
    ms = Date.now();
  }
  const d = new Date(ms);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')} ${get('hour')}:${get('minute')}`;
};

export const formatAddress = (s: ShippingInfo | undefined | null): string => {
  if (!s) return '';
  const lines = [
    s.fullName,
    s.phoneNumber,
    s.addressLine1,
    s.addressLine2,
    [s.city, s.state, s.postalCode].filter(Boolean).join(', '),
    s.country,
  ].filter((line) => line && String(line).trim().length > 0);
  return lines.join('\n');
};

export const resolveSellerEmail = async (
  db: admin.firestore.Firestore,
  sellerId: string
): Promise<string | undefined> => {
  const [userDoc, sellerDoc] = await Promise.all([
    db.collection('User').doc(sellerId).get(),
    db.collection('Seller').doc(sellerId).get(),
  ]);
  const userData = userDoc.data();
  const sellerData = sellerDoc.data();
  return (
    (userData?.email as string | undefined) ||
    (sellerData?.email as string | undefined) ||
    (sellerData?.vendor?.contacts?.email as string | undefined)
  );
};

export const itemsTableRows = (sellerItems: OrderItem[]): string =>
  sellerItems
    .map((item) => {
      const img = item.productImage
        ? `<img src="${escapeHtml(item.productImage)}" alt="" width="80" height="80" style="display:block;border-radius:6px;object-fit:cover;border:1px solid #eee" />`
        : '';
      const lineTotal =
        typeof item.total === 'number'
          ? item.total
          : (item.price ?? 0) * (item.quantity ?? 0);
      return `
        <tr>
          <td style="padding:12px;border-bottom:1px solid #eee;width:96px">${img}</td>
          <td style="padding:12px;border-bottom:1px solid #eee;font-size:14px;color:#222">${escapeHtml(item.productName ?? 'Item')}</td>
          <td style="padding:12px;border-bottom:1px solid #eee;font-size:14px;color:#444;text-align:right">${peso(item.price)}</td>
          <td style="padding:12px;border-bottom:1px solid #eee;font-size:14px;color:#444;text-align:center">${item.quantity ?? 0}</td>
          <td style="padding:12px;border-bottom:1px solid #eee;font-size:14px;color:#222;text-align:right;font-weight:600">${peso(lineTotal)}</td>
        </tr>`;
    })
    .join('');

export const itemsTextLines = (sellerItems: OrderItem[]): string =>
  sellerItems
    .map((i) => {
      const lineTotal =
        typeof i.total === 'number' ? i.total : (i.price ?? 0) * (i.quantity ?? 0);
      return `- ${i.productName ?? 'Item'} | ${peso(i.price)} x ${i.quantity ?? 0} = ${peso(lineTotal)}`;
    })
    .join('\n');

export const computeTotals = (
  sellerItems: OrderItem[],
  breakdown: SellerFeeBreakdown | undefined
): { subtotal: number; shipping: number; grandTotal: number } => {
  const subtotal =
    breakdown?.cartValue ??
    sellerItems.reduce(
      (acc, i) => acc + (typeof i.total === 'number' ? i.total : (i.price ?? 0) * (i.quantity ?? 0)),
      0
    );
  const shipping = breakdown?.buyerShippingCharge ?? 0;
  const grandTotal = breakdown?.totalChargedToBuyer ?? subtotal + shipping;
  return { subtotal, shipping, grandTotal };
};
