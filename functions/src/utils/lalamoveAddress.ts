/**
 * Resolves Lalamove "stop" information (coordinates, address text, contact) for
 * the seller pickup and buyer drop-off, plus the city/state used for Metro
 * Manila coverage checks. Shared by calculateLalamoveQuote and bookLalamoveDelivery.
 */
import * as admin from 'firebase-admin';
import { LatLng } from './lalamoveClient';
import { resolveCoordinates } from './geocodeHelper';

export interface ResolvedStop {
  coordinates: LatLng;
  /** Single-line address string for Lalamove. */
  address: string;
  /** Contact display name. */
  name: string;
  /** E.164 phone (+63...), best-effort. */
  phone: string;
  /** Raw city/state for coverage checks. */
  city: string;
  state: string;
}

/** Build a single-line address string from address-like fields. */
export function formatAddressText(data: any): string {
  const parts = [
    data?.addressLine1 || data?.address_line_1 || data?.line1,
    data?.addressLine2 || data?.address_line_2 || data?.line2,
    data?.barangay,
    data?.city || data?.City,
    data?.state || data?.State || data?.province || data?.Province,
    data?.postalCode || data?.postal_code,
  ]
    .map((p) => (typeof p === 'string' ? p.trim() : ''))
    .filter((p) => p.length > 0);
  const joined = parts.join(', ');
  return joined.length > 0 ? joined : 'Metro Manila, Philippines';
}

/**
 * Normalize a PH phone number to E.164 (+63XXXXXXXXXX).
 * Accepts 09XXXXXXXXX, 9XXXXXXXXX, +639XXXXXXXXX, 639XXXXXXXXX.
 */
export function toE164PH(raw: string | undefined | null): string {
  const digits = (raw || '').replace(/[^\d]/g, '');
  if (!digits) return '';
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  if (digits.startsWith('9') && digits.length === 10) return `+63${digits}`;
  return raw && raw.startsWith('+') ? raw : `+${digits}`;
}

/** Resolve the buyer drop-off stop from User/{userId}/Address/{addressId}. */
export async function resolveBuyerStop(
  db: admin.firestore.Firestore,
  userId: string,
  addressId: string,
): Promise<ResolvedStop> {
  const ref = db.collection('User').doc(userId).collection('Address').doc(addressId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error('Shipping address not found');
  const data = snap.data() as any;

  const address = formatAddressText(data);
  const coordinates = await resolveCoordinates(ref, data, address);
  return {
    coordinates,
    address,
    name: data?.fullName || 'Customer',
    phone: toE164PH(data?.phoneNumber),
    city: data?.city || '',
    state: data?.state || data?.province || '',
  };
}

/** A seller pickup address resolved from any of the known seller-doc shapes. */
interface SellerAddrParts {
  addressText: string;
  city: string;
  state: string;
}

/** company.address.{line1,line2,city,province,region,zip} → address parts. */
function partsFromCompanyAddress(companyAddr: any): SellerAddrParts | null {
  if (!companyAddr || typeof companyAddr !== 'object') return null;
  return {
    addressText: formatAddressText({
      addressLine1: companyAddr.line1,
      addressLine2: companyAddr.line2,
      barangay: companyAddr.barangay,
      city: companyAddr.city,
      province: companyAddr.province || companyAddr.region,
      postalCode: companyAddr.zip,
    }),
    city: (companyAddr.city || '').toString(),
    state: (companyAddr.province || companyAddr.region || '').toString(),
  };
}

/** Root address map (mobile cart): { city, state, addressLine1, ... }. */
function partsFromAddressMap(map: any): SellerAddrParts | null {
  if (!map || typeof map !== 'object') return null;
  return {
    addressText: formatAddressText(map),
    city: (map.city || map.City || '').toString(),
    state: (map.state || map.State || map.province || map.Province || '').toString(),
  };
}

/**
 * The seller's address lives in different shapes depending on how the store was
 * onboarded: the seller center writes `vendor.company.address` (and older docs
 * may use a top-level `company.address`), while the mobile cart reads a root
 * `address` map/string. A doc can even carry a stub alongside a populated shape,
 * so collect every candidate and pick the first that genuinely has a city/state.
 */
function resolveSellerAddressParts(data: any): SellerAddrParts {
  const root = data?.address;

  // Free-text address fields.
  if (typeof root === 'string' && root.trim()) {
    return { addressText: root.trim(), city: root, state: root };
  }
  if (typeof data?.shippingAddress === 'string' && data.shippingAddress.trim()) {
    const s = data.shippingAddress.trim();
    return { addressText: s, city: s, state: s };
  }

  const candidates = [
    // Vendor enrollment shape, nested under `vendor` (current seller center)…
    partsFromCompanyAddress(data?.vendor?.company?.address),
    // …or at the top level (older docs).
    partsFromCompanyAddress(data?.company?.address),
    // Root address map (mobile cart), top level or under `vendor`.
    partsFromAddressMap(root),
    partsFromAddressMap(data?.vendor?.address),
  ].filter((c): c is SellerAddrParts => c !== null);

  // Prefer a candidate that has a city, then one with a state, then any.
  const best =
    candidates.find((c) => c.city.trim()) ||
    candidates.find((c) => c.state.trim()) ||
    candidates[0];
  if (best) return best;

  return { addressText: 'Metro Manila, Philippines', city: '', state: '' };
}

/**
 * Resolve the seller pickup stop. Prefers the `Seller` doc (the seller-center
 * source of truth, same collection the mobile cart reads), falling back to the
 * `User` doc for resilience. Reuses cached coordinates; otherwise geocodes the
 * store address once and caches lat/lng back on the doc.
 */
export async function resolveSellerStop(
  db: admin.firestore.Firestore,
  sellerId: string,
): Promise<ResolvedStop> {
  let ref = db.collection('Seller').doc(sellerId);
  let snap = await ref.get();
  if (!snap.exists) {
    ref = db.collection('User').doc(sellerId);
    snap = await ref.get();
  }
  if (!snap.exists) throw new Error('Seller not found');
  const data = snap.data() as any;

  const parts = resolveSellerAddressParts(data);
  const address = parts.addressText;

  // Reuse cached coords keyed to this address; geocode + cache on first use or
  // when the store address changed (same path the buyer drop-off uses).
  const coordinates = await resolveCoordinates(ref, data, address);

  // Store name / contact live either at the top level or under `vendor`.
  const company = data?.vendor?.company || data?.company || {};
  const contacts = data?.vendor?.contacts || data?.contacts || {};
  return {
    coordinates,
    address,
    name:
      data?.storeName ||
      data?.shopName ||
      company?.storeName ||
      company?.name ||
      data?.vendor?.storeName ||
      data?.displayName ||
      'Seller',
    phone: toE164PH(
      contacts?.phone ||
        data?.phoneNumber ||
        company?.phone ||
        data?.mobile ||
        data?.contactNumber,
    ),
    city: parts.city,
    state: parts.state,
  };
}
