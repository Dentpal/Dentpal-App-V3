/**
 * Metro Manila (NCR) coverage — single source of truth for Same Day Delivery
 * eligibility. Lalamove same-day is only offered when BOTH the seller pickup
 * and buyer drop-off addresses fall within Metro Manila.
 */

/** The 16 cities + 1 municipality (Pateros) that make up NCR. */
export const NCR_CITIES: string[] = [
  'manila',
  'quezon city',
  'caloocan',
  'las pinas',
  'makati',
  'malabon',
  'mandaluyong',
  'marikina',
  'muntinlupa',
  'navotas',
  'paranaque',
  'pasay',
  'pasig',
  'pateros',
  'san juan',
  'taguig',
  'valenzuela',
];

/** Strings that, when present in the city/state, indicate NCR. */
const NCR_REGION_HINTS = ['metro manila', 'ncr', 'national capital region'];

/** Normalize for comparison: lowercase, strip accents/punctuation, collapse spaces. */
function normalize(value: string | undefined | null): string {
  if (!value) return '';
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip diacritics (ñ -> n, etc.)
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Whether the given address (by its city and/or state/province text) is within
 * Metro Manila. Accepts loose, free-text values from address docs.
 */
export function isMetroManila(city?: string | null, state?: string | null): boolean {
  const c = normalize(city);
  const s = normalize(state);

  // Region-level hints on either field.
  if (NCR_REGION_HINTS.some((h) => c.includes(h) || s.includes(h))) return true;

  // City-name match on either field (handles addresses that put the city in
  // the "state" slot, e.g. "Makati, Metro Manila").
  return NCR_CITIES.some((nc) => c === nc || s === nc || c.includes(nc) || s.includes(nc));
}
