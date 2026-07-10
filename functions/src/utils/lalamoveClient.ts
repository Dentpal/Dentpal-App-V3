/**
 * Lalamove API v3 client (Philippines market).
 *
 * Thin wrapper around the Lalamove REST API used for Same Day Delivery.
 * Mirrors the structure of the other backend helpers (jrsShippingHelper).
 *
 * Auth (per developers.lalamove.com):
 *   Authorization: hmac <API_KEY>:<TIMESTAMP_ms>:<SIGNATURE>
 *   SIGNATURE = HmacSHA256("<TIMESTAMP>\r\n<VERB>\r\n<PATH>\r\n\r\n<BODY>", <SECRET>)
 *   plus headers: Market: PH, Request-ID: <uuid>, Content-Type: application/json
 *
 * Credentials are read from process.env (local .env in the emulator, Google
 * Secret Manager in production via `secrets: [...]` on each function):
 *   LALAMOVE_API_KEY, LALAMOVE_API_SECRET, LALAMOVE_ENV ('sandbox' | 'production')
 */
import * as crypto from 'crypto';
import axios, { AxiosResponse } from 'axios';
import * as logger from 'firebase-functions/logger';

const MARKET = 'PH';
const API_VERSION = 'v3';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface LalamoveStop {
  coordinates: { lat: string; lng: string };
  address: string;
}

export interface LalamoveContact {
  stopId: string;
  name: string;
  /** E.164, e.g. +63912XXXXXXX */
  phone: string;
  remarks?: string;
}

export interface QuotationParams {
  pickup: { coordinates: LatLng; address: string };
  dropoff: { coordinates: LatLng; address: string };
  /** Defaults to MOTORCYCLE. */
  serviceType?: string;
  /** Optional package metadata. */
  item?: {
    quantity?: string;
    weight?: string;
    categories?: string[];
    handlingInstructions?: string[];
  };
}

export interface QuotationResult {
  quotationId: string;
  expiresAt: string;
  serviceType: string;
  /** First stop = pickup, second = dropoff. */
  stops: Array<{ stopId: string; address: string }>;
  priceBreakdown: {
    total: string;
    currency: string;
    [k: string]: string;
  };
  distance?: { value: string; unit: string };
}

export interface PlaceOrderParams {
  quotationId: string;
  sender: LalamoveContact;
  recipients: LalamoveContact[];
  metadata?: Record<string, string>;
  isPODEnabled?: boolean;
}

export interface LalamoveOrder {
  orderId: string;
  quotationId: string;
  status: string;
  shareLink?: string;
  driverId?: string;
  priceBreakdown?: { total: string; currency: string; [k: string]: string };
  distance?: { value: string; unit: string };
  metadata?: Record<string, string>;
}

function baseUrl(): string {
  const env = (process.env.LALAMOVE_ENV || 'sandbox').toLowerCase();
  const host =
    env === 'production' || env === 'prod'
      ? 'https://rest.lalamove.com'
      : 'https://rest.sandbox.lalamove.com';
  return `${host}/${API_VERSION}`;
}

function credentials(): { apiKey: string; secret: string } {
  const apiKey = process.env.LALAMOVE_API_KEY;
  const secret = process.env.LALAMOVE_API_SECRET;
  if (!apiKey || !secret) {
    throw new Error('Lalamove credentials are not configured');
  }
  return { apiKey, secret };
}

/**
 * Builds the Authorization + standard headers for a Lalamove request.
 * `path` must include the version prefix (e.g. /v3/quotations).
 * `rawBody` is the exact JSON string sent as the request body ('' for GET/DELETE).
 */
function buildHeaders(method: string, path: string, rawBody: string): Record<string, string> {
  const { apiKey, secret } = credentials();
  const timestamp = Date.now().toString();
  const verb = method.toUpperCase();
  const encryptedString = `${timestamp}\r\n${verb}\r\n${path}\r\n\r\n${rawBody}`;
  const signature = crypto
    .createHmac('sha256', secret)
    .update(encryptedString)
    .digest('hex');

  return {
    Authorization: `hmac ${apiKey}:${timestamp}:${signature}`,
    Market: MARKET,
    'Request-ID': crypto.randomUUID(),
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
}

/**
 * Performs a signed Lalamove API call.
 * @param method HTTP verb
 * @param resourcePath path WITHOUT the version prefix (e.g. /quotations)
 * @param body request payload (will be wrapped as { data: body } if `wrap`)
 */
async function lalamoveRequest<T>(
  method: 'GET' | 'POST' | 'DELETE' | 'PATCH',
  resourcePath: string,
  body?: unknown,
): Promise<T> {
  const fullPath = `/${API_VERSION}${resourcePath}`;
  const rawBody = body !== undefined ? JSON.stringify({ data: body }) : '';
  const headers = buildHeaders(method, fullPath, rawBody);

  try {
    const response: AxiosResponse = await axios.request({
      method,
      url: `${baseUrl()}${resourcePath}`,
      headers,
      data: rawBody || undefined,
      timeout: 20000,
      // We parse the body ourselves so the signature matches exactly.
      transformRequest: [(d) => d],
      validateStatus: (s) => s >= 200 && s < 300,
    });
    // 204 No Content (cancel) has no body.
    return (response.data?.data ?? response.data) as T;
  } catch (error: any) {
    const status = error?.response?.status;
    const errors = error?.response?.data?.errors;
    logger.error('Lalamove API request failed', {
      method,
      path: resourcePath,
      status,
      errors,
      message: error?.message,
    });
    const detail =
      Array.isArray(errors) && errors.length
        ? errors.map((e: any) => e.id || e.message).join('; ')
        : error?.message || 'Unknown error';
    const err = new Error(`Lalamove ${method} ${resourcePath} failed (${status ?? 'n/a'}): ${detail}`);
    (err as any).lalamoveStatus = status;
    (err as any).lalamoveErrors = errors;
    throw err;
  }
}

/** POST /v3/quotations */
export async function getQuotation(params: QuotationParams): Promise<QuotationResult> {
  const serviceType = params.serviceType || 'MOTORCYCLE';
  const data: Record<string, unknown> = {
    serviceType,
    language: 'en_PH',
    stops: [
      {
        coordinates: {
          lat: String(params.pickup.coordinates.lat),
          lng: String(params.pickup.coordinates.lng),
        },
        address: params.pickup.address,
      },
      {
        coordinates: {
          lat: String(params.dropoff.coordinates.lat),
          lng: String(params.dropoff.coordinates.lng),
        },
        address: params.dropoff.address,
      },
    ],
  };
  if (params.item) data.item = params.item;
  return lalamoveRequest<QuotationResult>('POST', '/quotations', data);
}

/** POST /v3/orders */
export async function placeOrder(params: PlaceOrderParams): Promise<LalamoveOrder> {
  const data: Record<string, unknown> = {
    quotationId: params.quotationId,
    sender: params.sender,
    recipients: params.recipients,
  };
  if (params.metadata) data.metadata = params.metadata;
  if (typeof params.isPODEnabled === 'boolean') data.isPODEnabled = params.isPODEnabled;
  return lalamoveRequest<LalamoveOrder>('POST', '/orders', data);
}

/** GET /v3/orders/{orderId} */
export async function getOrder(orderId: string): Promise<LalamoveOrder> {
  return lalamoveRequest<LalamoveOrder>('GET', `/orders/${encodeURIComponent(orderId)}`);
}

/** DELETE /v3/orders/{orderId} — returns 204 on success. */
export async function cancelOrder(orderId: string): Promise<void> {
  await lalamoveRequest<void>('DELETE', `/orders/${encodeURIComponent(orderId)}`);
}
