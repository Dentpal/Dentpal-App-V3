import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';
import { Resend } from 'resend';

if (admin.apps.length === 0) {
  admin.initializeApp({
    databaseURL: 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app',
  });
}

const db = admin.firestore();

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');

const FROM_ADDRESS = 'Dentpal <support@dentpal.shop>';
const SELLER_CENTER_URL = 'https://dentpal-site.web.app';

type OrderItem = {
  sellerId?: string;
  productName?: string;
  productImage?: string;
  price?: number;
  quantity?: number;
  total?: number;
};

type SellerFeeBreakdown = {
  sellerId?: string;
  sellerName?: string;
  cartValue?: number;
  buyerShippingCharge?: number;
  totalChargedToBuyer?: number;
};

type ShippingInfo = {
  fullName?: string;
  phoneNumber?: string;
  addressLine1?: string;
  addressLine2?: string | null;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
};

const peso = (n: unknown) => {
  const num = typeof n === 'number' && isFinite(n) ? n : 0;
  return `₱${num.toFixed(2)}`;
};

const escapeHtml = (s: unknown) =>
  String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

const formatManilaDateTime = (createdAt: unknown): string => {
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

const formatAddress = (s: ShippingInfo | undefined | null): string => {
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

const buildHtml = (params: {
  orderId: string;
  sellerItems: OrderItem[];
  breakdown: SellerFeeBreakdown | undefined;
  shippingInfo: ShippingInfo | undefined;
  dateTimeLabel: string;
}): string => {
  const { orderId, sellerItems, breakdown, shippingInfo, dateTimeLabel } = params;

  const itemRows = sellerItems
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

  const subtotal =
    breakdown?.cartValue ??
    sellerItems.reduce(
      (acc, i) => acc + (typeof i.total === 'number' ? i.total : (i.price ?? 0) * (i.quantity ?? 0)),
      0
    );
  const shipping = breakdown?.buyerShippingCharge ?? 0;
  const grandTotal = breakdown?.totalChargedToBuyer ?? subtotal + shipping;

  const addressHtml = escapeHtml(formatAddress(shippingInfo)).replace(/\n/g, '<br>');

  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f5f6f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f6f8;padding:24px 0">
      <tr>
        <td align="center">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;max-width:600px;width:100%">
            <tr>
              <td style="padding:24px 28px;background:#0b6b5a;color:#ffffff">
                <div style="font-size:20px;font-weight:700">New Dentpal Order</div>
                <div style="font-size:13px;opacity:.9;margin-top:4px">${escapeHtml(dateTimeLabel)} (Asia/Manila)</div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 28px">
                <p style="margin:0 0 8px 0;font-size:14px;color:#222">You have a new order on Dentpal.</p>
                <p style="margin:0 0 20px 0;font-size:13px;color:#666">Order ID: <strong>${escapeHtml(orderId)}</strong></p>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #eee;border-radius:8px;border-collapse:separate;border-spacing:0">
                  <thead>
                    <tr style="background:#fafafa">
                      <th align="left" style="padding:10px 12px;font-size:12px;color:#666;font-weight:600;border-bottom:1px solid #eee">Image</th>
                      <th align="left" style="padding:10px 12px;font-size:12px;color:#666;font-weight:600;border-bottom:1px solid #eee">Product</th>
                      <th align="right" style="padding:10px 12px;font-size:12px;color:#666;font-weight:600;border-bottom:1px solid #eee">Price</th>
                      <th align="center" style="padding:10px 12px;font-size:12px;color:#666;font-weight:600;border-bottom:1px solid #eee">Qty</th>
                      <th align="right" style="padding:10px 12px;font-size:12px;color:#666;font-weight:600;border-bottom:1px solid #eee">Total</th>
                    </tr>
                  </thead>
                  <tbody>${itemRows}</tbody>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:20px">
                  <tr>
                    <td style="padding:6px 0;font-size:14px;color:#444">Subtotal</td>
                    <td style="padding:6px 0;font-size:14px;color:#222;text-align:right">${peso(subtotal)}</td>
                  </tr>
                  <tr>
                    <td style="padding:6px 0;font-size:14px;color:#444">Shipping</td>
                    <td style="padding:6px 0;font-size:14px;color:#222;text-align:right">${peso(shipping)}</td>
                  </tr>
                  <tr>
                    <td style="padding:10px 0 0 0;font-size:15px;color:#0b6b5a;font-weight:700;border-top:1px solid #eee">Total charged to buyer</td>
                    <td style="padding:10px 0 0 0;font-size:15px;color:#0b6b5a;font-weight:700;text-align:right;border-top:1px solid #eee">${peso(grandTotal)}</td>
                  </tr>
                </table>

                <div style="margin-top:24px">
                  <div style="font-size:13px;font-weight:700;color:#222;margin-bottom:6px">Shipping address</div>
                  <div style="font-size:13px;color:#444;line-height:1.5">${addressHtml || '<em>No address provided</em>'}</div>
                </div>

                <div style="margin-top:28px;text-align:center">
                  <a href="${SELLER_CENTER_URL}" style="display:inline-block;padding:12px 22px;background:#0b6b5a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600">Go to Seller Center</a>
                </div>

                <p style="margin:24px 0 0 0;font-size:12px;color:#888;text-align:center">This is an automated message from Dentpal.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
};

const buildText = (params: {
  orderId: string;
  sellerItems: OrderItem[];
  breakdown: SellerFeeBreakdown | undefined;
  shippingInfo: ShippingInfo | undefined;
  dateTimeLabel: string;
}): string => {
  const { orderId, sellerItems, breakdown, shippingInfo, dateTimeLabel } = params;
  const itemLines = sellerItems
    .map((i) => {
      const lineTotal =
        typeof i.total === 'number' ? i.total : (i.price ?? 0) * (i.quantity ?? 0);
      return `- ${i.productName ?? 'Item'} | ${peso(i.price)} x ${i.quantity ?? 0} = ${peso(lineTotal)}`;
    })
    .join('\n');
  const subtotal =
    breakdown?.cartValue ??
    sellerItems.reduce(
      (acc, i) => acc + (typeof i.total === 'number' ? i.total : (i.price ?? 0) * (i.quantity ?? 0)),
      0
    );
  const shipping = breakdown?.buyerShippingCharge ?? 0;
  const grandTotal = breakdown?.totalChargedToBuyer ?? subtotal + shipping;
  return [
    `New Dentpal Order — ${dateTimeLabel} (Asia/Manila)`,
    `Order ID: ${orderId}`,
    '',
    'Items:',
    itemLines || '(no items)',
    '',
    `Subtotal: ${peso(subtotal)}`,
    `Shipping: ${peso(shipping)}`,
    `Total charged to buyer: ${peso(grandTotal)}`,
    '',
    'Shipping address:',
    formatAddress(shippingInfo) || '(none)',
    '',
    `Seller Center: ${SELLER_CENTER_URL}`,
  ].join('\n');
};

export const notifySellerOnNewOrderEmail = onDocumentCreated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
    secrets: [RESEND_API_KEY],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const order = snap.data() as {
      sellerIds?: string[];
      items?: OrderItem[];
      sellerFeeBreakdowns?: SellerFeeBreakdown[];
      shippingInfo?: ShippingInfo;
      createdAt?: admin.firestore.Timestamp;
    };
    const orderId = event.params.orderId;

    const sellerIds = Array.isArray(order.sellerIds) ? order.sellerIds.filter(Boolean) : [];
    if (sellerIds.length === 0) {
      console.log(`[notifySellerOnNewOrderEmail] No sellerIds on order ${orderId}, skipping`);
      return;
    }

    const apiKey = RESEND_API_KEY.value();
    if (!apiKey) {
      console.error('[notifySellerOnNewOrderEmail] RESEND_API_KEY is not set');
      return;
    }
    const resend = new Resend(apiKey);

    const dateTimeLabel = formatManilaDateTime(order.createdAt);
    const subject = `New Dentpal Order (${dateTimeLabel})`;
    const items = Array.isArray(order.items) ? order.items : [];
    const breakdowns = Array.isArray(order.sellerFeeBreakdowns) ? order.sellerFeeBreakdowns : [];

    const results = await Promise.allSettled(
      sellerIds.map(async (sellerId) => {
        try {
          const [userDoc, sellerDoc] = await Promise.all([
            db.collection('User').doc(sellerId).get(),
            db.collection('Seller').doc(sellerId).get(),
          ]);
          const userData = userDoc.data();
          const sellerData = sellerDoc.data();
          const sellerEmail =
            (userData?.email as string | undefined) ||
            (sellerData?.email as string | undefined) ||
            (sellerData?.vendor?.contacts?.email as string | undefined);

          if (!sellerEmail) {
            console.log(
              `[notifySellerOnNewOrderEmail] No email for seller ${sellerId} on order ${orderId}, skipping`
            );
            return;
          }

          const sellerItems = items.filter((i) => i.sellerId === sellerId);
          const breakdown = breakdowns.find((b) => b.sellerId === sellerId);

          const html = buildHtml({
            orderId,
            sellerItems,
            breakdown,
            shippingInfo: order.shippingInfo,
            dateTimeLabel,
          });
          const text = buildText({
            orderId,
            sellerItems,
            breakdown,
            shippingInfo: order.shippingInfo,
            dateTimeLabel,
          });

          const { data, error } = await resend.emails.send({
            from: FROM_ADDRESS,
            to: sellerEmail,
            subject,
            html,
            text,
          });

          if (error) {
            console.error(
              `[notifySellerOnNewOrderEmail] Resend error for seller ${sellerId} on order ${orderId}:`,
              error
            );
            return;
          }
          console.log(
            `[notifySellerOnNewOrderEmail] Sent to ${sellerEmail} (seller ${sellerId}) for order ${orderId}, id=${data?.id}`
          );
        } catch (err) {
          console.error(
            `[notifySellerOnNewOrderEmail] Failed for seller ${sellerId} on order ${orderId}:`,
            err
          );
        }
      })
    );

    const failed = results.filter((r) => r.status === 'rejected').length;
    if (failed > 0) {
      console.warn(
        `[notifySellerOnNewOrderEmail] ${failed}/${sellerIds.length} per-seller tasks rejected for order ${orderId}`
      );
    }
  }
);
