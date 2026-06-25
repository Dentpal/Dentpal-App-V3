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

const buildHtml = (params: {
  orderId: string;
  returnRequestId: string | undefined;
  sellerItems: OrderItem[];
  breakdown: SellerFeeBreakdown | undefined;
  shippingInfo: ShippingInfo | undefined;
  dateTimeLabel: string;
  returnReason: string;
}): string => {
  const {
    orderId,
    returnRequestId,
    sellerItems,
    breakdown,
    shippingInfo,
    dateTimeLabel,
    returnReason,
  } = params;

  const { subtotal, shipping, grandTotal } = computeTotals(sellerItems, breakdown);
  const addressHtml = escapeHtml(formatAddress(shippingInfo)).replace(/\n/g, '<br>');

  const returnRequestLine = returnRequestId
    ? `<p style="margin:0 0 16px 0;font-size:13px;color:#666">Return Request ID: <strong>${escapeHtml(returnRequestId)}</strong></p>`
    : '';

  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f5f6f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f6f8;padding:24px 0">
      <tr>
        <td align="center">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;max-width:600px;width:100%">
            <tr>
              <td style="padding:24px 28px;background:#b45309;color:#ffffff">
                <div style="font-size:20px;font-weight:700">Return / Refund Requested</div>
                <div style="font-size:13px;opacity:.9;margin-top:4px">${escapeHtml(dateTimeLabel)} (Asia/Manila)</div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 28px">
                <p style="margin:0 0 8px 0;font-size:14px;color:#222">A buyer has requested a return / refund on a delivered Dentpal order.</p>
                <p style="margin:0 0 4px 0;font-size:13px;color:#666">Order ID: <strong>${escapeHtml(orderId)}</strong></p>
                ${returnRequestLine}

                <div style="padding:14px 16px;background:#fffbeb;border:1px solid #fde68a;border-radius:8px;margin:0 0 20px 0">
                  <div style="font-size:13px;font-weight:700;color:#92400e;margin-bottom:4px">Buyer's reason for return</div>
                  <div style="font-size:13px;color:#78350f;line-height:1.5">${escapeHtml(returnReason) || '<em>No reason provided</em>'}</div>
                </div>

                <div style="padding:14px 16px;background:#fef2f2;border:1px solid #fecaca;border-radius:8px;margin:0 0 20px 0">
                  <div style="font-size:13px;font-weight:700;color:#991b1b;margin-bottom:4px">Action required</div>
                  <div style="font-size:13px;color:#7f1d1d;line-height:1.5">Please review this request in the Seller Center within 1–2 business days and approve or reject the return.</div>
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
                    <td style="padding:10px 0 0 0;font-size:15px;color:#b45309;font-weight:700;border-top:1px solid #eee">Potential refund amount</td>
                    <td style="padding:10px 0 0 0;font-size:15px;color:#b45309;font-weight:700;text-align:right;border-top:1px solid #eee">${peso(grandTotal)}</td>
                  </tr>
                </table>

                <div style="margin-top:24px">
                  <div style="font-size:13px;font-weight:700;color:#222;margin-bottom:6px">Shipping address</div>
                  <div style="font-size:13px;color:#444;line-height:1.5">${addressHtml || '<em>No address provided</em>'}</div>
                </div>

                <div style="margin-top:28px;text-align:center">
                  <a href="${SELLER_CENTER_URL}" style="display:inline-block;padding:12px 22px;background:#b45309;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600">Review Return Request</a>
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
  returnRequestId: string | undefined;
  sellerItems: OrderItem[];
  breakdown: SellerFeeBreakdown | undefined;
  shippingInfo: ShippingInfo | undefined;
  dateTimeLabel: string;
  returnReason: string;
}): string => {
  const {
    orderId,
    returnRequestId,
    sellerItems,
    breakdown,
    shippingInfo,
    dateTimeLabel,
    returnReason,
  } = params;
  const { subtotal, shipping, grandTotal } = computeTotals(sellerItems, breakdown);
  return [
    `Return / Refund Requested — ${dateTimeLabel} (Asia/Manila)`,
    `Order ID: ${orderId}`,
    returnRequestId ? `Return Request ID: ${returnRequestId}` : '',
    '',
    `Buyer's reason: ${returnReason || '(none provided)'}`,
    '',
    'Action required: Please review and approve/reject in the Seller Center within 1–2 business days.',
    '',
    'Items:',
    itemsTextLines(sellerItems) || '(no items)',
    '',
    `Subtotal: ${peso(subtotal)}`,
    `Shipping: ${peso(shipping)}`,
    `Potential refund amount: ${peso(grandTotal)}`,
    '',
    'Shipping address:',
    formatAddress(shippingInfo) || '(none)',
    '',
    `Seller Center: ${SELLER_CENTER_URL}`,
  ]
    .filter((line) => line !== '')
    .join('\n');
};

const extractReturnReason = (after: admin.firestore.DocumentData): string => {
  const historyEntry = (after.statusHistory as Array<{ status?: string; note?: string }> | undefined)
    ?.slice()
    .reverse()
    .find((entry) => entry?.status === 'return_requested');
  const note = historyEntry?.note ?? '';
  return note.replace(/^Return requested:\s*/i, '').trim();
};

export const notifyOrderReturnRefundEmail = onDocumentUpdated(
  {
    document: 'Order/{orderId}',
    region: 'asia-southeast1',
    secrets: [RESEND_API_KEY],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    if (before.status === 'return_requested' || after.status !== 'return_requested') {
      return;
    }

    const orderId = event.params.orderId;
    const sellerIds: string[] = Array.isArray(after.sellerIds)
      ? after.sellerIds.filter(Boolean)
      : [];
    if (sellerIds.length === 0) {
      console.log(`[notifyOrderReturnRefundEmail] No sellerIds on order ${orderId}, skipping`);
      return;
    }

    const apiKey = RESEND_API_KEY.value();
    if (!apiKey) {
      console.error('[notifyOrderReturnRefundEmail] RESEND_API_KEY is not set');
      return;
    }
    const resend = new Resend(apiKey);

    const dateTimeLabel = formatManilaDateTime(after.updatedAt);
    const subject = `Return / Refund Requested (${dateTimeLabel})`;
    const items: OrderItem[] = Array.isArray(after.items) ? after.items : [];
    const breakdowns: SellerFeeBreakdown[] = Array.isArray(after.sellerFeeBreakdowns)
      ? after.sellerFeeBreakdowns
      : [];
    const returnReason = extractReturnReason(after);
    const returnRequestId: string | undefined = after.returnRequestId;

    const results = await Promise.allSettled(
      sellerIds.map(async (sellerId) => {
        try {
          const sellerEmail = await resolveSellerEmail(db, sellerId);
          if (!sellerEmail) {
            console.log(
              `[notifyOrderReturnRefundEmail] No email for seller ${sellerId} on order ${orderId}, skipping`
            );
            return;
          }

          const sellerItems = items.filter((i) => i.sellerId === sellerId);
          const breakdown = breakdowns.find((b) => b.sellerId === sellerId);

          const html = buildHtml({
            orderId,
            returnRequestId,
            sellerItems,
            breakdown,
            shippingInfo: after.shippingInfo,
            dateTimeLabel,
            returnReason,
          });
          const text = buildText({
            orderId,
            returnRequestId,
            sellerItems,
            breakdown,
            shippingInfo: after.shippingInfo,
            dateTimeLabel,
            returnReason,
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
              `[notifyOrderReturnRefundEmail] Resend error for seller ${sellerId} on order ${orderId}:`,
              error
            );
            return;
          }
          console.log(
            `[notifyOrderReturnRefundEmail] Sent to ${sellerEmail} (seller ${sellerId}) for order ${orderId}, id=${data?.id}`
          );
        } catch (err) {
          console.error(
            `[notifyOrderReturnRefundEmail] Failed for seller ${sellerId} on order ${orderId}:`,
            err
          );
        }
      })
    );

    const failed = results.filter((r) => r.status === 'rejected').length;
    if (failed > 0) {
      console.warn(
        `[notifyOrderReturnRefundEmail] ${failed}/${sellerIds.length} per-seller tasks rejected for order ${orderId}`
      );
    }
  }
);
