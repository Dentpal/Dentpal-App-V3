/**
 * Server-side geocoding fallback for Same Day Delivery.
 *
 * Coordinates are cached on the doc keyed to the exact address they were
 * geocoded from (`geocodedAddress` signature). They're reused only while that
 * signature still matches the current address; otherwise (address changed, or
 * unsigned/stale coords) we re-geocode via the Google Maps Geocoding API and
 * re-stamp — so a quote always uses coordinates for the address on file.
 */
import axios from 'axios';
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { LatLng } from './lalamoveClient';

const GEOCODE_URL = 'https://maps.googleapis.com/maps/api/geocode/json';

/**
 * Compact, comparable signature of an address string, so cached coordinates can
 * be tied to the exact address they were geocoded from (and invalidated when the
 * address later changes). Lowercased, punctuation-stripped, whitespace-collapsed.
 */
export function addressSignature(addressText: string): string {
  return (addressText || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function readStoredCoords(data: any, addressText: string): LatLng | null {
  const lat = data?.latitude;
  const lng = data?.longitude;
  if (typeof lat !== 'number' || typeof lng !== 'number' || (lat === 0 && lng === 0)) {
    return null;
  }
  // Only reuse coords that were stamped with the address they were geocoded from
  // AND still match it. Unsigned coords are NOT trusted — they may be a stale
  // fallback geocode (e.g. a Metro-Manila centroid saved before the address
  // resolved) or client-set coords for a since-edited address — so we re-geocode
  // and stamp a signature, self-healing to the correct location.
  const sig = data?.geocodedAddress;
  if (typeof sig !== 'string' || sig.length === 0 || sig !== addressSignature(addressText)) {
    return null;
  }
  return { lat, lng };
}

/** Calls the Google Maps Geocoding API for a free-text address. */
async function callGoogleGeocode(addressText: string): Promise<LatLng> {
  const key = process.env.GOOGLE_MAPS_API_KEY;
  if (!key) throw new Error('GOOGLE_MAPS_API_KEY is not configured');

  const res = await axios.get(GEOCODE_URL, {
    params: {
      address: addressText,
      key,
      region: 'ph',
      components: 'country:PH',
    },
    timeout: 15000,
  });

  const status = res.data?.status;
  const result = res.data?.results?.[0];
  if (status !== 'OK' || !result?.geometry?.location) {
    throw new Error(`Geocoding failed for address (status: ${status ?? 'unknown'})`);
  }
  const loc = result.geometry.location;
  return { lat: loc.lat, lng: loc.lng };
}

/**
 * Resolves coordinates for a Firestore document reference, reusing stored
 * latitude/longitude when available and caching freshly geocoded values back.
 *
 * @param ref         document reference holding the address (and where coords are cached)
 * @param data        already-loaded document data (avoids a re-read)
 * @param addressText full address string to geocode if coords are missing
 */
export async function resolveCoordinates(
  ref: admin.firestore.DocumentReference,
  data: any,
  addressText: string,
): Promise<LatLng> {
  const stored = readStoredCoords(data, addressText);
  if (stored) return stored;

  logger.info('Geocoding address server-side (no matching stored coords)', { path: ref.path });
  const coords = await callGoogleGeocode(addressText);

  // Cache back — keyed to this exact address — so we only geocode it once and
  // automatically re-geocode if the address later changes.
  try {
    await ref.set(
      {
        latitude: coords.lat,
        longitude: coords.lng,
        geocodedAddress: addressSignature(addressText),
        geocodedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (e) {
    logger.warn('Failed to cache geocoded coordinates', { path: ref.path, error: (e as Error).message });
  }
  return coords;
}

/** Geocode a plain address string without caching (used when there is no doc to cache to). */
export async function geocodeAddress(addressText: string): Promise<LatLng> {
  return callGoogleGeocode(addressText);
}
