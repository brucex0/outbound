/** WGS84 inverse geodesic, matching CLLocation's ellipsoidal distance model. */
export function routeDistance(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }): number {
  const radians = Math.PI / 180, major = 6_378_137, flattening = 1 / 298.257223563, minor = (1 - flattening) * major;
  const u1 = Math.atan((1 - flattening) * Math.tan(a.latitude * radians)), u2 = Math.atan((1 - flattening) * Math.tan(b.latitude * radians));
  const sin1 = Math.sin(u1), cos1 = Math.cos(u1), sin2 = Math.sin(u2), cos2 = Math.cos(u2);
  const longitude = (b.longitude - a.longitude) * radians;
  let lambda = longitude, sigma = 0, sinSigma = 0, cosSigma = 1, cosSquaredAlpha = 1, cosTwoSigmaM = 0;
  let converged = false;
  for (let i = 0; i < 100; i++) {
    const sinLambda = Math.sin(lambda), cosLambda = Math.cos(lambda);
    sinSigma = Math.hypot(cos2 * sinLambda, cos1 * sin2 - sin1 * cos2 * cosLambda);
    if (sinSigma === 0) return 0;
    cosSigma = sin1 * sin2 + cos1 * cos2 * cosLambda;
    sigma = Math.atan2(sinSigma, cosSigma);
    const sinAlpha = cos1 * cos2 * sinLambda / sinSigma;
    cosSquaredAlpha = 1 - sinAlpha * sinAlpha;
    cosTwoSigmaM = cosSquaredAlpha > 1e-15 ? cosSigma - 2 * sin1 * sin2 / cosSquaredAlpha : 0;
    const c = flattening / 16 * cosSquaredAlpha * (4 + flattening * (4 - 3 * cosSquaredAlpha));
    const next = longitude + (1 - c) * flattening * sinAlpha * (sigma + c * sinSigma * (cosTwoSigmaM + c * cosSigma * (-1 + 2 * cosTwoSigmaM ** 2)));
    if (Math.abs(next - lambda) < 1e-12) { converged = true; break; }
    lambda = next;
  }
  if (!converged) {
    // Antipodal geometry cannot occur in a genuine contiguous workout sample.
    // Keep the fallback finite for malformed imported geometry, without logging coordinates.
    const h = Math.sin((b.latitude - a.latitude) * radians / 2) ** 2 + Math.cos(a.latitude * radians) * Math.cos(b.latitude * radians) * Math.sin(longitude / 2) ** 2;
    return 6_371_000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
  }
  const uSquared = cosSquaredAlpha * (major * major - minor * minor) / (minor * minor);
  const coefficientA = 1 + uSquared / 16384 * (4096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)));
  const coefficientB = uSquared / 1024 * (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)));
  const deltaSigma = coefficientB * sinSigma * (cosTwoSigmaM + coefficientB / 4 * (cosSigma * (-1 + 2 * cosTwoSigmaM ** 2) - coefficientB / 6 * cosTwoSigmaM * (-3 + 4 * sinSigma ** 2) * (-3 + 4 * cosTwoSigmaM ** 2)));
  return minor * coefficientA * (sigma - deltaSigma);
}
