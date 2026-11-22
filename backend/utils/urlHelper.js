"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBaseUrl = getBaseUrl;

function getBaseUrl(req) {
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

exports.default = { getBaseUrl };
