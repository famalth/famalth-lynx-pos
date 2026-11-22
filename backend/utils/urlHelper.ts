/**
 * Resolves the dynamic Base URL for the application.
 * Priority:
 * 1. APP_URL / BASE_URL / PUBLIC_URL environment variables
 * 2. RENDER_EXTERNAL_URL (automatic on Render cloud hosting)
 * 3. Incoming HTTP Request protocol & host (x-forwarded-proto, x-forwarded-host, req.get('host'))
 * 4. Fallback to http://localhost:PORT
 */
export function getBaseUrl(req?: any): string {
  const envUrl = process.env.APP_URL || process.env.BASE_URL || process.env.PUBLIC_URL || process.env.RENDER_EXTERNAL_URL;
  if (envUrl && typeof envUrl === 'string' && envUrl.trim().length > 0) {
    return envUrl.trim().replace(/\/+$/, '');
  }

  if (req) {
    const forwardedProto = req.headers?.['x-forwarded-proto'];
    const protocol = (typeof forwardedProto === 'string' ? forwardedProto.split(',')[0].trim() : null) || req.protocol || 'http';
    const host = req.headers?.['x-forwarded-host'] || (typeof req.get === 'function' ? req.get('host') : null) || req.headers?.host;
    if (host) {
      return `${protocol}://${host}`.replace(/\/+$/, '');
    }
  }

  const port = process.env.PORT || 3000;
  return `http://localhost:${port}`;
}

export default { getBaseUrl };
