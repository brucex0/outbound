import { createHash } from "node:crypto";

const MET_FORECAST_URL = "https://api.met.no/weatherapi/locationforecast/2.0/compact";
const CACHE_TTL_MS = 30 * 60 * 1_000;
const STALE_TTL_MS = 6 * 60 * 60 * 1_000;

export type WeatherImpact = "none" | "advisory" | "caution" | "unsafe";

export type RunningWeatherSnapshot = {
  fetchedAt: string;
  placeName: null;
  symbolName: string;
  condition: string;
  temperatureCelsius: number;
  apparentTemperatureCelsius: number;
  windKilometersPerHour: number;
  precipitationChance: number;
  impact: WeatherImpact;
  headlineKey: string;
  guidanceKey: string | null;
  bestWindowStart: string | null;
  attribution: {
    provider: "MET Norway";
    text: "Weather data from MET Norway";
    url: "https://api.met.no/doc/License";
    license: "CC BY 4.0";
    modified: true;
  };
};

type CacheEntry = {
  storedAt: number;
  lastModified: string | null;
  snapshot: RunningWeatherSnapshot;
};

const cache = new Map<string, CacheEntry>();

export async function getRunningWeather(input: {
  userId: string;
  locale: string;
  latitude: number;
  longitude: number;
  altitudeMeters?: number;
  force?: boolean;
}): Promise<{ snapshot: RunningWeatherSnapshot; cacheStatus: "fresh" | "revalidated" | "miss" | "stale" }> {
  const latitude = roundedCoordinate(input.latitude);
  const longitude = roundedCoordinate(input.longitude);
  const altitude = input.altitudeMeters == null ? undefined : Math.round(input.altitudeMeters);
  const key = cacheKey(input.userId, input.locale, latitude, longitude, altitude);
  const cached = cache.get(key);
  const now = Date.now();

  if (!input.force && cached && now - cached.storedAt < CACHE_TTL_MS) {
    return { snapshot: cached.snapshot, cacheStatus: "fresh" };
  }

  const url = new URL(MET_FORECAST_URL);
  url.searchParams.set("lat", latitude.toFixed(2));
  url.searchParams.set("lon", longitude.toFixed(2));
  if (altitude != null) url.searchParams.set("altitude", String(altitude));

  const headers: Record<string, string> = {
    Accept: "application/json",
    "Accept-Encoding": "gzip, deflate",
    "User-Agent": process.env.WEATHER_PROVIDER_USER_AGENT ?? "Plainstride/1.0 https://plainstride.run",
  };
  if (cached?.lastModified) headers["If-Modified-Since"] = cached.lastModified;

  try {
    const response = await fetch(url, { headers, redirect: "follow", signal: AbortSignal.timeout(8_000) });
    if (response.status === 304 && cached) {
      cached.storedAt = now;
      return { snapshot: cached.snapshot, cacheStatus: "revalidated" };
    }
    if (!response.ok) throw new Error(`weather_provider_${response.status}`);

    const payload = await response.json() as MetForecast;
    const snapshot = normalizeForecast(payload, now);
    cache.set(key, {
      storedAt: now,
      lastModified: response.headers.get("last-modified"),
      snapshot,
    });
    pruneCache(now);
    return { snapshot, cacheStatus: "miss" };
  } catch (error) {
    if (cached && now - cached.storedAt < STALE_TTL_MS) {
      return { snapshot: cached.snapshot, cacheStatus: "stale" };
    }
    throw error;
  }
}

function normalizeForecast(forecast: MetForecast, fetchedAtMs: number): RunningWeatherSnapshot {
  const timeseries = forecast.properties?.timeseries ?? [];
  if (timeseries.length === 0) throw new Error("weather_provider_empty_forecast");
  const current = timeseries[0];
  const instant = current.data.instant.details;
  const symbol = current.data.next_1_hours?.summary.symbol_code
    ?? current.data.next_6_hours?.summary.symbol_code
    ?? "cloudy";
  const precipitationChance = clampProbability(
    current.data.next_1_hours?.details.probability_of_precipitation
      ?? current.data.next_6_hours?.details.probability_of_precipitation
      ?? 0,
  );
  const windKph = instant.wind_speed * 3.6;
  const apparentCelsius = apparentTemperature(instant.air_temperature, instant.relative_humidity, windKph);
  const policy = runningPolicy(symbol, apparentCelsius, windKph, precipitationChance);

  return {
    fetchedAt: new Date(fetchedAtMs).toISOString(),
    placeName: null,
    symbolName: symbol,
    condition: normalizedCondition(symbol),
    temperatureCelsius: round(instant.air_temperature, 1),
    apparentTemperatureCelsius: round(apparentCelsius, 1),
    windKilometersPerHour: round(windKph, 1),
    precipitationChance: round(precipitationChance, 2),
    impact: policy.impact,
    headlineKey: policy.headlineKey,
    guidanceKey: policy.guidanceKey,
    bestWindowStart: bestRunningWindow(timeseries, fetchedAtMs),
    attribution: {
      provider: "MET Norway",
      text: "Weather data from MET Norway",
      url: "https://api.met.no/doc/License",
      license: "CC BY 4.0",
      modified: true,
    },
  };
}

function runningPolicy(symbol: string, apparentCelsius: number, windKph: number, precipitationChance: number) {
  const condition = symbol.toLowerCase();
  if (condition.includes("thunder")) {
    return { impact: "unsafe" as const, headlineKey: "weather.headline.unsafe", guidanceKey: "weather.guidance.unsafe" };
  }
  if (apparentCelsius >= 32) {
    return { impact: "caution" as const, headlineKey: "weather.headline.heat", guidanceKey: "weather.guidance.heat" };
  }
  if (apparentCelsius <= -7) {
    return { impact: "caution" as const, headlineKey: "weather.headline.cold", guidanceKey: "weather.guidance.cold" };
  }
  if (windKph >= 35) {
    return { impact: "advisory" as const, headlineKey: "weather.headline.wind", guidanceKey: "weather.guidance.wind" };
  }
  if (condition.includes("snow") || condition.includes("sleet") || condition.includes("freezing")) {
    return { impact: "caution" as const, headlineKey: "weather.headline.slippery", guidanceKey: "weather.guidance.slippery" };
  }
  if (precipitationChance >= 0.65 || condition.includes("rain")) {
    return { impact: "advisory" as const, headlineKey: "weather.headline.rain", guidanceKey: "weather.guidance.rain" };
  }
  return { impact: "none" as const, headlineKey: "weather.headline.good", guidanceKey: null };
}

function bestRunningWindow(hours: MetTimeseries[], nowMs: number): string | null {
  const upcoming = hours.filter((hour) => {
    const time = Date.parse(hour.time);
    return time >= nowMs && time <= nowMs + 18 * 60 * 60 * 1_000;
  });
  let best: { index: number; score: number } | null = null;
  for (let index = 0; index + 2 < upcoming.length; index += 1) {
    const window = upcoming.slice(index, index + 3);
    const averageRain = window.reduce((sum, hour) => sum + precipitation(hour), 0) / window.length;
    const averageTemperature = window.reduce((sum, hour) => sum + hour.data.instant.details.air_temperature, 0) / window.length;
    const score = averageRain * 2 + Math.abs(averageTemperature - 14) / 20;
    if (!best || score < best.score) best = { index, score };
  }
  if (!best || best.index === 0) return null;
  const start = Date.parse(upcoming[best.index].time);
  return start - nowMs < 12 * 60 * 60 * 1_000 ? new Date(start).toISOString() : null;
}

function precipitation(hour: MetTimeseries): number {
  return clampProbability(hour.data.next_1_hours?.details.probability_of_precipitation
    ?? hour.data.next_6_hours?.details.probability_of_precipitation
    ?? 0);
}

function apparentTemperature(temperatureCelsius: number, humidityPercent: number, windKph: number): number {
  if (temperatureCelsius <= 10 && windKph > 4.8) {
    return 13.12 + 0.6215 * temperatureCelsius - 11.37 * windKph ** 0.16
      + 0.3965 * temperatureCelsius * windKph ** 0.16;
  }
  if (temperatureCelsius >= 27) {
    const fahrenheit = temperatureCelsius * 9 / 5 + 32;
    const heatIndexFahrenheit = -42.379 + 2.04901523 * fahrenheit + 10.14333127 * humidityPercent
      - 0.22475541 * fahrenheit * humidityPercent - 0.00683783 * fahrenheit ** 2
      - 0.05481717 * humidityPercent ** 2 + 0.00122874 * fahrenheit ** 2 * humidityPercent
      + 0.00085282 * fahrenheit * humidityPercent ** 2
      - 0.00000199 * fahrenheit ** 2 * humidityPercent ** 2;
    return (heatIndexFahrenheit - 32) * 5 / 9;
  }
  return temperatureCelsius;
}

function normalizedCondition(symbol: string): string {
  return symbol.replace(/_(day|night|polartwilight)$/, "").replaceAll("_", " ");
}

function clampProbability(percent: number) { return Math.min(1, Math.max(0, percent / 100)); }
function roundedCoordinate(value: number) { return Math.round(value * 100) / 100; }
function round(value: number, digits: number) { const factor = 10 ** digits; return Math.round(value * factor) / factor; }
function cacheKey(userId: string, locale: string, lat: number, lon: number, altitude?: number) {
  return createHash("sha256").update(`${userId}|${locale}|${lat}|${lon}|${altitude ?? ""}`).digest("hex");
}
function pruneCache(now: number) {
  if (cache.size < 2_000) return;
  for (const [key, value] of cache) if (now - value.storedAt >= STALE_TTL_MS) cache.delete(key);
}

type MetForecast = { properties?: { timeseries?: MetTimeseries[] } };
type MetTimeseries = {
  time: string;
  data: {
    instant: { details: { air_temperature: number; relative_humidity: number; wind_speed: number } };
    next_1_hours?: MetPeriod;
    next_6_hours?: MetPeriod;
  };
};
type MetPeriod = { summary: { symbol_code: string }; details: { probability_of_precipitation?: number } };
