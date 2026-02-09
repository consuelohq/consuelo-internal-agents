import type { PhoneNumber, NumberSelection } from '../types.js';

/**
 * Extracts the 3-digit US area code from an E.164 number (+1XXXXXXXXXX).
 */
export function extractAreaCode(phoneNumber: string): string | null {
  const cleaned = phoneNumber.replace(/\D/g, '');
  if (cleaned.length === 11 && cleaned.startsWith('1')) return cleaned.slice(1, 4);
  if (cleaned.length === 10) return cleaned.slice(0, 3);
  return null;
}

export interface NumberPool {
  numbers: PhoneNumber[];
  primaryNumber?: PhoneNumber;
}

/**
 * Local presence service — selects the best outbound number
 * based on geographic proximity to the customer's area code.
 *
 * Selection priority:
 *  1. Exact area code match
 *  2. Closest area code within maxDistanceMiles (requires distanceFn)
 *  3. Primary number fallback
 */
export class LocalPresenceService {
  private maxDistanceMiles: number;
  private distanceFn?: (areaCodeA: string, areaCodeB: string) => Promise<number | null>;

  constructor(opts?: {
    maxDistanceMiles?: number;
    distanceFn?: (a: string, b: string) => Promise<number | null>;
  }) {
    this.maxDistanceMiles = opts?.maxDistanceMiles ?? 100;
    this.distanceFn = opts?.distanceFn;
  }

  async selectNumber(pool: NumberPool, customerNumber: string): Promise<NumberSelection | null> {
    const customerAreaCode = extractAreaCode(customerNumber);
    if (!customerAreaCode || !pool.numbers.length) {
      return this.primaryFallback(pool, customerAreaCode);
    }

    // 1. exact area code match
    const exact = pool.numbers.find((n) => n.areaCode === customerAreaCode && n.isActive);
    if (exact) {
      return {
        phoneNumber: exact.phoneNumber,
        areaCode: exact.areaCode,
        localMatch: true,
        proximityMatch: false,
        isPrimary: exact.isPrimary,
        customerAreaCode,
      };
    }

    // 2. proximity match (if distance function provided)
    if (this.distanceFn) {
      let best: { number: PhoneNumber; distance: number } | null = null;

      for (const num of pool.numbers) {
        if (!num.isActive) continue;
        const dist = await this.distanceFn(customerAreaCode, num.areaCode);
        if (dist !== null && dist <= this.maxDistanceMiles) {
          if (!best || dist < best.distance) {
            best = { number: num, distance: dist };
          }
        }
      }

      if (best) {
        return {
          phoneNumber: best.number.phoneNumber,
          areaCode: best.number.areaCode,
          localMatch: false,
          proximityMatch: true,
          distanceMiles: best.distance,
          isPrimary: best.number.isPrimary,
          customerAreaCode,
        };
      }
    }

    // 3. primary fallback
    return this.primaryFallback(pool, customerAreaCode);
  }

  private primaryFallback(pool: NumberPool, customerAreaCode: string | null): NumberSelection | null {
    const primary = pool.primaryNumber ?? pool.numbers.find((n) => n.isPrimary && n.isActive);
    if (!primary) return null;
    return {
      phoneNumber: primary.phoneNumber,
      areaCode: primary.areaCode,
      localMatch: false,
      proximityMatch: false,
      isPrimary: true,
      customerAreaCode: customerAreaCode ?? undefined,
    };
  }
}
