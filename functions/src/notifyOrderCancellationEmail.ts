import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';
import { Resend } from 'resend';
import {
  OrderItem,
  SellerFeeBreakdown,
  ShippingInfo,
  computeTotals,
  escapeHtml,
  formatAddress,
  formatManilaDateTime,
  itemsTableRows,
  itemsTextLines,
  peso,
  resolveSellerEmail,
} from './utils/orderEmailHelpers';

if (admin.apps.length === 0) {
  admin.initializeApp({
    databaseURL: 'https://dentpal-161e5-default-rtdb.asia-southeast1.firebasedatabase.app',
  });
}

const db = admin.firestore();

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');

const FROM_ADDRESS = 'Dentpal <support@dentpal.shop>';
const SELLER_CENTER_URL = 'https://dentpal-site.web.app';

type RefundInfo = {
  refundId?: string;
  refundAmount?: number;
  refundStatus?: string;
  refundReason?: string;
};

const buildHtml = (params: {
  orderId: string;
  sellerItems: OrderItem[];
  breakdown: SellerFeeBreakdown | undefined;
  shippingInfo: ShippingInfo | undefined;
  dateTimeLabel: string;
  cancellationReason: string;
  refundInfo: RefundInfo | undefined;
  isCodOrder: boolean;
}): string => {
  const {
    orderId,
    sellerItems,
    breakdown,
    shippingInfo,
    dateTimeLabel,
    cancellationReason,
    refundInfo,
    isCodOrder,
  } = params;

  const { subtotal, shipping, grandTotal } = computeTotals(sellerItems, breakdown);
  const addressHtml = escapeHtml(formatAddress(shippingInfo)).replace(/\n/g, '<br>');

  const refundBlock = refundInfo?.refundId
    ? `
                <div style="margin-top:20px;padding:14px 16px;background:#fff7ed;border:1px solid #fed7aa;border-radius:8px">
                  <div style="font-size:13px;font-weight:700;color:#9a3412;margin-bottom:4px">Refund initiated</div>
                  <div style="font-size:13px;color:#7c2d12;line-height:1.5">
                    Refund ID: <strong>${escapeHtml(refundInfo.refundId)}</strong><br>
                    Amount: <strong>${peso(refundInfo.refundAmount ?? grandTotal)}</strong><br>
                    Status: <strong>${escapeHtml(refundInfo.refundStatus ?? 'pending')}</strong>
                  </div>
                </div>`
    : isCodOrder
      ? `
                <div style="margin-top:20px;padding:14px 16px;background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px">
                  <div style="font-size:13px;color:#166534;line-height:1.5">
                    This was a <strong>Cash on Delivery</strong> order — no payment was collected, so no refund is required.
                  </div>
                </div>`
      : '';

  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f5f6f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f6f8;padding:24px 0">
      <tr>
        <td align="center">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;max-width:600px;width:100%">
            <tr>
              <td style="padding:24px 28px;background:#b91c1c;color:#ffffff">
                <div style="font-size:20px;font-weight:700">Order Cancelled</div>
                <div style="font-size:13px;opacity:.9;margin-top:4px">${escapeHtml(dateTimeLabel)} (Asia/Manila)</div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 28px">
                <p style="margin:0 0 8px 0;font-size:14px;color:#222">A buyer has cancelled their Dentpal order.</p>
                <p style="margin:0 0 16px 0;font-size:13px;color:#666">Order ID: <strong>${escapeHtml(orderId)}</strong></p>

                <div style="padding:14px 16px;background:#fef2f2;border:1px solid #fecaca;border-radius:8px;margin-bottom:20px">
                  <div style="font-size:13px;font-weight:700;color:#991b1b;margin-bottom:4px">Cancellation reason</div>
                  <div style="font-size:13px;color:#7f1d1d;line-height:1.5">${escapeHtml(cancellationReason) || '<em>No reason provided</em>'}</div>
                </div>

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
                  <tbody>${itemsTableRows(sellerItems)}</tbody>
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
                    <td style="padding:10px 0 0 0;font-size:15px;color:#b91c1c;font-weight:700;border-top:1px solid #eee">Order total (cancelled)</td>
                    <td style="padding:10px 0 0 0;font-size:15px;color:#b91c1c;font-weight:700;text-align:right;border-top:1px solid #eee">${peso(grandTotal)}</td>
                  </tr>
                </table>

                ${refundBlock}

                <div style="margin-top:24px">
                  <div style="font-size:13px;font-weight:700;color:#222;margin-bottom:6px">Shipping address</div>
                  <div style="font-size:13px;color:#444;line-height:1.5">${addressHtml || '<em>No address provided</em>'}</div>
                </div>

                <div style="margin-top:28px;text-align:center">
                  <a href="${SELLER_CENTER_URL}" style="display:inline-block;padding:12px 22px;background:#b91c1c;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600">Open Seller Center</a>
                </div>

                <p style="margin:24px 0 0 0;font-size:12px;color:#888;text-align:center">This is an automated message from Dentpal. No further action is required for this cancellation.</p>
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
  cancellationReason: string;
  refundInfo: RefundInfo | undefined;
  isCodOrder: boolean;
}): string => {
  const {
    orderId,
    sellerItems,
    breakdown,
    shippingInfo,
    dateTimeLabel,
    cancellationReason,
    refundInfo,
    isCodOrder,
  } = params;
  const { subtotal, shipping, grandTotal } = computeTotals(sellerItems, breakdown);

  const refundLine = refundInfo?.refundId
    ? `Refund initiated — ID: ${refundInfo.refundId}, Amount: ${peso(refundInfo.refundAmount ?? grandTotal)}, Status: ${refundInfo.refundStatus ?? 'pending'}`
    : isCodOrder
      ? 'Cash on Delivery — no refund required'
      : '';

  return [
    `Order Cancelled — ${dateTimeLabel} (Asia/Manila)`,
    `Order ID: ${orderId}`,
    '',
    `Cancellation reason: ${cancellationReason || '(none provided)'}`,
    '',
    'Items:',
    itemsTextLines(sellerItems) || '(no items)',
    '',
    `Subtotal: ${peso(subtotal)}`,
    `Shipping: ${peso(shipping)}`,
    `Order total: ${peso(grandTotal)}`,
    refundLine ? `\n${refundLine}` : '',
    '',
    'Shipping address:',
    formatAddress(shippingInfo) || '(none)',
    '',
    `Seller Center: ${SELLER_CENTER_URL}`,
  ]
    .filter((line) => line !== '')
    .join('\n');
};

export const notifyOrderCancellationEmail = onDocumentUpdated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
    secrets: [RESEND_API_KEY],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    if (before.status === 'cancelled' || after.status !== 'cancelled') {
      return;
    }

    const orderId = event.params.orderId;
    const sellerIds: string[] = Array.isArray(after.sellerIds)
      ? after.sellerIds.filter(Boolean)
      : [];
    if (sellerIds.length === 0) {
      console.log(`[notifyOrderCancellationEmail] No sellerIds on order ${orderId}, skipping`);
      return;
    }

    const apiKey = RESEND_API_KEY.value();
    if (!apiKey) {
      console.error('[notifyOrderCancellationEmail] RESEND_API_KEY is not set');
      return;
    }
    const resend = new Resend(apiKey);

    const dateTimeLabel = formatManilaDateTime(after.cancelledAt ?? after.updatedAt);
    const subject = `Order Cancelled (${dateTimeLabel})`;
    const items: OrderItem[] = Array.isArray(after.items) ? after.items : [];
    const breakdowns: SellerFeeBreakdown[] = Array.isArray(after.sellerFeeBreakdowns)
      ? after.sellerFeeBreakdowns
      : [];
    const cancellationReason: string =
      (after.cancellationReason as string | undefined) ?? '';
    const refundInfo: RefundInfo | undefined = after.refundInfo;
    const isCodOrder = after.paymongo?.paymentMethod === 'cash_on_delivery';

    const results = await Promise.allSettled(
      sellerIds.map(async (sellerId) => {
        try {
          const sellerEmail = await resolveSellerEmail(db, sellerId);
          if (!sellerEmail) {
            console.log(
              `[notifyOrderCancellationEmail] No email for seller ${sellerId} on order ${orderId}, skipping`
            );
            return;
          }

          const sellerItems = items.filter((i) => i.sellerId === sellerId);
          const breakdown = breakdowns.find((b) => b.sellerId === sellerId);

          const html = buildHtml({
            orderId,
            sellerItems,
            breakdown,
            shippingInfo: after.shippingInfo,
            dateTimeLabel,
            cancellationReason,
            refundInfo,
            isCodOrder,
          });
          const text = buildText({
            orderId,
            sellerItems,
            breakdown,
            shippingInfo: after.shippingInfo,
            dateTimeLabel,
            cancellationReason,
            refundInfo,
            isCodOrder,
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
              `[notifyOrderCancellationEmail] Resend error for seller ${sellerId} on order ${orderId}:`,
              error
            );
            return;
          }
          console.log(
            `[notifyOrderCancellationEmail] Sent to ${sellerEmail} (seller ${sellerId}) for order ${orderId}, id=${data?.id}`
          );
        } catch (err) {
          console.error(
            `[notifyOrderCancellationEmail] Failed for seller ${sellerId} on order ${orderId}:`,
            err
          );
        }
      })
    );

    const failed = results.filter((r) => r.status === 'rejected').length;
    if (failed > 0) {
      console.warn(
        `[notifyOrderCancellationEmail] ${failed}/${sellerIds.length} per-seller tasks rejected for order ${orderId}`
      );
    }
  }
);
