/**
 * Same Day Delivery ordering-window helpers.
 *
 * Sellers configure, in `checkoutOptions.sameDaySchedule` (Seller doc), the days
 * of week and the daily start/end time during which buyers may place Same Day
 * (Lalamove) orders. This module validates the current Philippine time against
 * that window so a client cannot place a same-day order outside the seller's
 * configured hours. Bounds set in the seller UI: 7:00 AM–5:00 PM.
 */

export type SameDayDayKey = 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun';

export interface SameDaySchedule {
  days: Record<SameDayDayKey, boolean>;
  startTime: string; // 'HH:MM' 24h
  endTime: string; // 'HH:MM' 24h
}

/** Default window: Monday–Friday, 10:00 AM – 3:00 PM. */
export const DEFAULT_SAME_DAY_SCHEDULE: SameDaySchedule = {
  days: { mon: true, tue: true, wed: true, thu: true, fri: true, sat: false, sun: false },
  startTime: '10:00',
  endTime: '15:00',
};

const DAY_KEYS: SameDayDayKey[] = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/** Parse 'HH:MM' into minutes-since-midnight; returns `fallback` if malformed. */
function toMinutes(hhmm: unknown, fallback: number): number {
  if (typeof hhmm !== 'string') return fallback;
  const [h, m] = hhmm.split(':');
  const hi = parseInt(h, 10);
  const mi = parseInt(m, 10);
  if (Number.isNaN(hi) || Number.isNaN(mi)) return fallback;
  return hi * 60 + mi;
}

/** Fill a raw Firestore value into a complete schedule (defaults for gaps). */
export function normalizeSameDaySchedule(raw: any): SameDaySchedule {
  if (!raw || typeof raw !== 'object') return DEFAULT_SAME_DAY_SCHEDULE;
  const rawDays = raw.days && typeof raw.days === 'object' ? raw.days : {};
  const days = {} as Record<SameDayDayKey, boolean>;
  for (const k of DAY_KEYS) {
    days[k] = k in rawDays ? rawDays[k] === true : DEFAULT_SAME_DAY_SCHEDULE.days[k];
  }
  return {
    days,
    startTime:
      typeof raw.startTime === 'string' && raw.startTime ? raw.startTime : DEFAULT_SAME_DAY_SCHEDULE.startTime,
    endTime: typeof raw.endTime === 'string' && raw.endTime ? raw.endTime : DEFAULT_SAME_DAY_SCHEDULE.endTime,
  };
}

/** Current Philippine (UTC+8) wall-clock, independent of the server timezone. */
function philippineNow(now: Date): { dayKey: SameDayDayKey; minutes: number } {
  const ph = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  const jsDay = ph.getUTCDay(); // 0=Sun..6=Sat
  const dayKey = DAY_KEYS[(jsDay + 6) % 7]; // Mon->0 .. Sun->6
  return { dayKey, minutes: ph.getUTCHours() * 60 + ph.getUTCMinutes() };
}

/**
 * Whether Same Day ordering is currently open for a seller with the given raw
 * schedule (from `checkoutOptions.sameDaySchedule`), evaluated in PH time.
 * A missing/malformed schedule falls back to the default window.
 */
export function isWithinSameDayWindow(rawSchedule: any, now: Date = new Date()): boolean {
  const schedule = normalizeSameDaySchedule(rawSchedule);
  const { dayKey, minutes } = philippineNow(now);
  if (!schedule.days[dayKey]) return false;
  const start = toMinutes(schedule.startTime, toMinutes(DEFAULT_SAME_DAY_SCHEDULE.startTime, 600));
  const end = toMinutes(schedule.endTime, toMinutes(DEFAULT_SAME_DAY_SCHEDULE.endTime, 900));
  return minutes >= start && minutes <= end;
}
