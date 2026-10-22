/** Gregorian calendar arithmetic in the caller's timezone; never use host-local dates. */
export class StatisticsCalendar {
  private formatter: Intl.DateTimeFormat;
  constructor(readonly timeZone: string, readonly firstWeekday: number) {
    this.formatter = new Intl.DateTimeFormat("en-US", { timeZone, calendar: "gregory", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  }
  local(date: Date) {
    const p = Object.fromEntries(this.formatter.formatToParts(date).map(x => [x.type, x.value]));
    return new Date(Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second, date.getUTCMilliseconds()));
  }
  instant(local: Date) {
    let guess = local.getTime();
    const visited = new Set<number>();
    for (let i = 0; i < 6; i++) {
      const difference = local.getTime() - this.local(new Date(guess)).getTime();
      if (difference === 0) break;
      visited.add(guess);
      const next = guess + difference;
      if (visited.has(next)) {
        // A nonexistent wall time in the spring gap advances by the gap,
        // matching Calendar.date(byAdding:) rather than drifting backwards.
        guess = Math.max(guess, next);
        break;
      }
      guess = next;
    }
    return new Date(guess);
  }
  add(date: Date, count: number, unit: "day" | "week" | "month") {
    const local = this.local(date);
    if (unit === "month") local.setUTCMonth(local.getUTCMonth() + count);
    else local.setUTCDate(local.getUTCDate() + count * (unit === "week" ? 7 : 1));
    return this.instant(local);
  }
  start(date: Date, unit: "day" | "week" | "month") {
    const local = this.local(date);
    local.setUTCHours(0, 0, 0, 0);
    if (unit === "month") local.setUTCDate(1);
    if (unit === "week") local.setUTCDate(local.getUTCDate() - (local.getUTCDay() - (this.firstWeekday - 1) + 7) % 7);
    return this.instant(local);
  }
  daysSince(date: Date, now: Date) {
    const day = (d: Date) => { const x = this.local(d); return Date.UTC(x.getUTCFullYear(), x.getUTCMonth(), x.getUTCDate()); };
    return Math.round((day(now) - day(date)) / 86_400_000);
  }
}
