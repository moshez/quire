/**
 * Civil date conversion tests
 *
 * Tests a JavaScript implementation of the civil_from_days algorithm
 * that mirrors the ATS2 implementation in quire.dats. The ATS2 version
 * is proven correct by MONTH_DAYS dataprop and termination metric;
 * these tests verify the algorithm logic against known dates.
 */

import { describe, it, expect } from 'vitest';

function isLeapYear(y) {
  if (y % 4 !== 0) return false;
  if (y % 100 !== 0) return true;
  return y % 400 === 0;
}

function daysInMonth(y, m) {
  const dims = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m === 2 && isLeapYear(y)) return 29;
  return dims[m];
}

/**
 * Convert days since Unix epoch (1970-01-01) to { year, month, day }.
 * Mirrors the recursive _civil_from_days_loop in quire.dats.
 */
function civilFromDays(n) {
  let y = 1970, m = 1, d = 1;
  for (let i = 0; i < n; i++) {
    const dim = daysInMonth(y, m);
    if (d < dim) {
      d++;
    } else if (m < 12) {
      m++;
      d = 1;
    } else {
      y++;
      m = 1;
      d = 1;
    }
  }
  return { year: y, month: m, day: d };
}

describe('civilFromDays', () => {
  it('day 0 → 1970-01-01', () => {
    expect(civilFromDays(0)).toEqual({ year: 1970, month: 1, day: 1 });
  });

  it('day 1 → 1970-01-02', () => {
    expect(civilFromDays(1)).toEqual({ year: 1970, month: 1, day: 2 });
  });

  it('day 30 → 1970-01-31', () => {
    expect(civilFromDays(30)).toEqual({ year: 1970, month: 1, day: 31 });
  });

  it('day 31 → 1970-02-01', () => {
    expect(civilFromDays(31)).toEqual({ year: 1970, month: 2, day: 1 });
  });

  it('day 58 → 1970-02-28 (non-leap year)', () => {
    expect(civilFromDays(58)).toEqual({ year: 1970, month: 2, day: 28 });
  });

  it('day 59 → 1970-03-01 (1970 is not a leap year)', () => {
    expect(civilFromDays(59)).toEqual({ year: 1970, month: 3, day: 1 });
  });

  it('day 364 → 1970-12-31', () => {
    expect(civilFromDays(364)).toEqual({ year: 1970, month: 12, day: 31 });
  });

  it('day 365 → 1971-01-01', () => {
    expect(civilFromDays(365)).toEqual({ year: 1971, month: 1, day: 1 });
  });

  // 1972 is a leap year
  it('day 789 → 1972-02-29 (leap year)', () => {
    expect(civilFromDays(789)).toEqual({ year: 1972, month: 2, day: 29 });
  });

  it('day 790 → 1972-03-01', () => {
    expect(civilFromDays(790)).toEqual({ year: 1972, month: 3, day: 1 });
  });

  it('day 10957 → 2000-01-01', () => {
    expect(civilFromDays(10957)).toEqual({ year: 2000, month: 1, day: 1 });
  });

  // 2000 is a leap year (divisible by 400)
  it('day 11016 → 2000-02-29 (century leap year)', () => {
    expect(civilFromDays(11016)).toEqual({ year: 2000, month: 2, day: 29 });
  });

  // 1900 is NOT a leap year (divisible by 100 but not 400)
  // But 1900 is before epoch, so test 2100 instead via offset
  // 2100-01-01 = day 47482
  it('day 47482 → 2100-01-01', () => {
    expect(civilFromDays(47482)).toEqual({ year: 2100, month: 1, day: 1 });
  });

  it('day 18628 → 2021-01-01', () => {
    expect(civilFromDays(18628)).toEqual({ year: 2021, month: 1, day: 1 });
  });

  // Month boundaries in 1970
  it('day 89 → 1970-03-31', () => {
    expect(civilFromDays(89)).toEqual({ year: 1970, month: 3, day: 31 });
  });

  it('day 90 → 1970-04-01', () => {
    expect(civilFromDays(90)).toEqual({ year: 1970, month: 4, day: 1 });
  });

  it('day 119 → 1970-04-30', () => {
    expect(civilFromDays(119)).toEqual({ year: 1970, month: 4, day: 30 });
  });

  it('day 120 → 1970-05-01', () => {
    expect(civilFromDays(120)).toEqual({ year: 1970, month: 5, day: 1 });
  });

  it('day 150 → 1970-05-31', () => {
    expect(civilFromDays(150)).toEqual({ year: 1970, month: 5, day: 31 });
  });

  it('day 151 → 1970-06-01', () => {
    expect(civilFromDays(151)).toEqual({ year: 1970, month: 6, day: 1 });
  });

  it('day 180 → 1970-06-30', () => {
    expect(civilFromDays(180)).toEqual({ year: 1970, month: 6, day: 30 });
  });

  it('day 181 → 1970-07-01', () => {
    expect(civilFromDays(181)).toEqual({ year: 1970, month: 7, day: 1 });
  });

  it('day 211 → 1970-07-31', () => {
    expect(civilFromDays(211)).toEqual({ year: 1970, month: 7, day: 31 });
  });

  it('day 212 → 1970-08-01', () => {
    expect(civilFromDays(212)).toEqual({ year: 1970, month: 8, day: 1 });
  });

  it('day 242 → 1970-08-31', () => {
    expect(civilFromDays(242)).toEqual({ year: 1970, month: 8, day: 31 });
  });

  it('day 243 → 1970-09-01', () => {
    expect(civilFromDays(243)).toEqual({ year: 1970, month: 9, day: 1 });
  });

  it('day 272 → 1970-09-30', () => {
    expect(civilFromDays(272)).toEqual({ year: 1970, month: 9, day: 30 });
  });

  it('day 273 → 1970-10-01', () => {
    expect(civilFromDays(273)).toEqual({ year: 1970, month: 10, day: 1 });
  });

  it('day 303 → 1970-10-31', () => {
    expect(civilFromDays(303)).toEqual({ year: 1970, month: 10, day: 31 });
  });

  it('day 304 → 1970-11-01', () => {
    expect(civilFromDays(304)).toEqual({ year: 1970, month: 11, day: 1 });
  });

  it('day 333 → 1970-11-30', () => {
    expect(civilFromDays(333)).toEqual({ year: 1970, month: 11, day: 30 });
  });

  it('day 334 → 1970-12-01', () => {
    expect(civilFromDays(334)).toEqual({ year: 1970, month: 12, day: 1 });
  });

  // Cross-reference with JS Date
  it('matches JS Date for 2024-06-15', () => {
    // 2024-06-15 = day 19889 since epoch
    const d = new Date(Date.UTC(2024, 5, 15)); // month is 0-indexed
    const daysSinceEpoch = Math.floor(d.getTime() / 86400000);
    const result = civilFromDays(daysSinceEpoch);
    expect(result).toEqual({ year: 2024, month: 6, day: 15 });
  });

  it('matches JS Date for 2025-12-31', () => {
    const d = new Date(Date.UTC(2025, 11, 31));
    const daysSinceEpoch = Math.floor(d.getTime() / 86400000);
    const result = civilFromDays(daysSinceEpoch);
    expect(result).toEqual({ year: 2025, month: 12, day: 31 });
  });

  // Consecutive day relationships
  it('consecutive days increment correctly', () => {
    for (let n = 0; n < 1000; n++) {
      const r = civilFromDays(n);
      const r2 = civilFromDays(n + 1);
      // Either day increments, or month changes, or year changes
      const isNextDay = r2.day === r.day + 1 && r2.month === r.month && r2.year === r.year;
      const isNextMonth = r2.day === 1 && r2.month === r.month + 1 && r2.year === r.year;
      const isNextYear = r2.day === 1 && r2.month === 1 && r2.year === r.year + 1;
      expect(isNextDay || isNextMonth || isNextYear).toBe(true);
    }
  });
});

describe('isLeapYear', () => {
  it('2000 is a leap year (divisible by 400)', () => {
    expect(isLeapYear(2000)).toBe(true);
  });

  it('1900 is not a leap year (divisible by 100 but not 400)', () => {
    expect(isLeapYear(1900)).toBe(false);
  });

  it('2024 is a leap year (divisible by 4)', () => {
    expect(isLeapYear(2024)).toBe(true);
  });

  it('2023 is not a leap year', () => {
    expect(isLeapYear(2023)).toBe(false);
  });
});
