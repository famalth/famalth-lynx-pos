"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.startBackupJob = startBackupJob;
const node_cron_1 = __importDefault(require("node-cron"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const { decryptAndUnzip } = require('../utils/decrypt');
const { processBackup } = require('../modules/backupService');
const { uploadBackupViaScript, cleanOldBackups } = require('../modules/driveService');
const { retry } = require('../utils/retry');
const { getBackupStatus, updateSyncSuccess } = require('../utils/backupTracker');
// Define strict backup and log directories
const isCompiled = typeof process.pkg !== 'undefined';
const baseDir = isCompiled ? path_1.default.dirname(process.execPath) : path_1.default.join(__dirname, '..');
const BACKUP_DIR = path_1.default.join(baseDir, 'backups');
const LOG_FILE = path_1.default.join(baseDir, 'backup-log.txt');
const activeBackupJobs = new Set();
// ==========================================
// LOGGER & EXCEPTION HANDLERS
// ==========================================
function logMessage(msg, isError = false) {
    const timestamp = new Date().toISOString();
    const level = isError ? '[ERROR]' : '[INFO]';
    const logText = `${timestamp} ${level} ${msg}\n`;
    if (isError) {
        console.error(logText.trim());
    }
    else {
        console.log(logText.trim());
    }
    try {
        fs_1.default.appendFileSync(LOG_FILE, logText);
    }
    catch (e) {
        console.error(`Failed to write to log file: ${e.message}`);
    }
}
process.on('uncaughtException', (err) => {
    logMessage(`[FATAL] Uncaught Exception: ${err.message}\n${err.stack}`, true);
    process.exit(1);
});
process.on('unhandledRejection', (reason) => {
    logMessage(`[FATAL] Unhandled Rejection: ${reason}`, true);
});
// ==========================================
// BACKUP
// ==========================================
function getReadableTimestamp() {
    const now = new Date();
    return now.getFullYear() + '-' +
        String(now.getMonth() + 1).padStart(2, '0') + '-' +
        String(now.getDate()).padStart(2, '0') + '_' +
        String(now.getHours()).padStart(2, '0') + '-' +
        String(now.getMinutes()).padStart(2, '0') + '-' +
        String(now.getSeconds()).padStart(2, '0');
}
function getDayKey(ts) {
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}
function getStaggeredMinute(outletCode, explicitMinute) {
    if (typeof explicitMinute === 'number' && Number.isInteger(explicitMinute) && explicitMinute >= 0 && explicitMinute <= 59) {
        return explicitMinute;
    }
    let hash = 0;
    const normalized = String(outletCode || 'unknown').trim().toLowerCase();
    for (let i = 0; i < normalized.length; i++) {
        hash = ((hash << 5) - hash + normalized.charCodeAt(i)) | 0;
    }
    return Math.abs(hash) % 60;
}
/**
 * Smart Local Retention Policy per outlet:
 * - Today: keep up to 12 hourly backups
 * - Past 10 completed days: keep only 1 final (latest) backup per day
 * - Older than 10 days: auto-delete
 */
function cleanOldLocalBackups(dir, outletCode) {
    if (!fs_1.default.existsSync(dir))
        return;
    const normalizedOutlet = outletCode ? outletCode.trim().toLowerCase() : '';
    const files = fs_1.default.readdirSync(dir)
        .filter(f => {
        const isBackup = f.endsWith('.enc') || f.endsWith('.fambak') || f.endsWith('.posbak');
        if (!isBackup)
            return false;
        if (normalizedOutlet && !f.toLowerCase().includes(normalizedOutlet))
            return false;
        return true;
    })
        .map(f => {
        const fullPath = path_1.default.join(dir, f);
        return {
            path: fullPath,
            time: fs_1.default.statSync(fullPath).mtime.getTime()
        };
    })
        .sort((a, b) => b.time - a.time);
    const now = new Date();
    const todayKey = getDayKey(now.getTime());
    const cutoffMs = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 10).getTime();
    const byDay = new Map();
    let deletedCount = 0;
    for (const f of files) {
        if (f.time < cutoffMs) {
            try {
                fs_1.default.unlinkSync(f.path);
                deletedCount++;
            }
            catch (_) { }
            continue;
        }
        const dayKey = getDayKey(f.time);
        if (!byDay.has(dayKey))
            byDay.set(dayKey, []);
        byDay.get(dayKey).push(f);
    }
    for (const [dayKey, dayFiles] of byDay.entries()) {
        const maxKeepForDay = dayKey === todayKey ? 12 : 1;
        if (dayFiles.length > maxKeepForDay) {
            const toDelete = dayFiles.slice(maxKeepForDay);
            for (const f of toDelete) {
                try {
                    fs_1.default.unlinkSync(f.path);
                    deletedCount++;
                }
                catch (_) { }
            }
        }
    }
    if (deletedCount > 0) {
        logMessage(`Cleaned ${deletedCount} old local backups${outletCode ? ` for [${outletCode}]` : ''} (Policy: 12 today, 1/day for last 10 days).`);
    }
}
async function verifyLocalBackup(encFilePath) {
    const verifyDir = fs_1.default.mkdtempSync(path_1.default.join(BACKUP_DIR, "verify-"));
    const verifyZip = path_1.default.join(verifyDir, "verify.zip");
    try {
        const extractedSql = await decryptAndUnzip(encFilePath, verifyZip, verifyDir);
        if (!extractedSql || !fs_1.default.existsSync(extractedSql)) {
            throw new Error("Backup archive did not contain the expected backup.sql payload.");
        }
    }
    finally {
        if (fs_1.default.existsSync(verifyDir)) {
            fs_1.default.rmSync(verifyDir, { recursive: true, force: true });
        }
    }
}
async function isOutletCloudBackupEnabled(activeDb, outletCode, outletId) {
    try {
        let resolvedId = Number(outletId || 0);
        if (!resolvedId && outletCode) {
            const [outRows] = await activeDb.query(`SELECT id FROM outlets WHERE LOWER(TRIM(outlet_code)) = LOWER(TRIM($1)) LIMIT 1;`, { bind: [outletCode] });
            resolvedId = Number(outRows?.[0]?.id || 0);
        }
        if (resolvedId) {
            const [rows] = await activeDb.query(`SELECT is_cloud_enabled FROM system_settings WHERE outlet_id = $1 LIMIT 1;`, { bind: [resolvedId] });
            if (rows && rows[0] && typeof rows[0].is_cloud_enabled !== 'undefined') {
                return rows[0].is_cloud_enabled === true;
            }
        }
    }
    catch (_) { }
    const localStatus = getBackupStatus(outletCode);
    return (localStatus === null || localStatus === void 0 ? void 0 : localStatus.isCloudEnabled) === true;
}
async function startBackupJob(client, config) {
    const outletCode = client && client.outlet_code ? client.outlet_code : "unknown";
    if (activeBackupJobs.has(outletCode)) {
        logMessage(`Backup job already running for outlet [${outletCode}]. Skipping duplicate trigger.`);
        return;
    }
    const { withDistributedLock } = require('../utils/distributedLock');
    const propertyDb = require('../db/models');
    activeBackupJobs.add(outletCode);
    const staggerMinute = getStaggeredMinute(outletCode, client === null || client === void 0 ? void 0 : client.staggerMinute);
    const cronExpr = `${staggerMinute} * * * *`;
    logMessage(`Backup scheduler initialized for [${outletCode}]. Running cron: ${cronExpr}`);
    node_cron_1.default.schedule(cronExpr, async () => {
        await withDistributedLock(propertyDb, `backup_job_${outletCode}`, async () => {
            try {
                const { TenantBackupService } = require('../services/tenantBackup.service');
                const activeDb = propertyDb.sequelize || propertyDb;
                const isCloudEnabled = await isOutletCloudBackupEnabled(activeDb, outletCode, client === null || client === void 0 ? void 0 : client.outlet_id);
                if (!isCloudEnabled) {
                    logMessage(`Skipping auto-backup for outlet [${outletCode}]: cloud/auto backup is disabled.`);
                    return;
                }
                if (!fs_1.default.existsSync(BACKUP_DIR)) {
                    fs_1.default.mkdirSync(BACKUP_DIR, { recursive: true });
                    logMessage(`Created backup directory at: ${BACKUP_DIR}`);
                }
                logMessage(`Hourly backup job started for outlet [${outletCode}]. Securing into proprietary .fambak archive...`);
                const fambakResult = await retry(() => TenantBackupService.createFambakBackup(activeDb, {
                    scope: 'OUTLET',
                    outletId: client === null || client === void 0 ? void 0 : client.outlet_id,
                    outletCode: outletCode,
                    saveToDrive: true
                }));
                const finalFilePath = fambakResult.filePath;
                const fileName = fambakResult.filename;
                logMessage(`Secured .fambak archive created: ${fileName} (${fambakResult.sizePretty}, ${fambakResult.totalRecords} records).`);
                // Verify archive integrity
                const fileBuf = fs_1.default.readFileSync(finalFilePath);
                const manifest = await TenantBackupService.inspectBackupManifest(fileBuf);
                if (!manifest || manifest.totalRecords === undefined) {
                    throw new Error("Backup integrity verification failed: empty manifest.");
                }
                logMessage(`Archive verified: format=${manifest.format}, scope=${manifest.scope}, tables=${manifest.tables.length}, total_records=${manifest.totalRecords}.`);
                updateSyncSuccess(outletCode);
                logMessage("Cloud sync recorded successfully.");
                cleanOldLocalBackups(BACKUP_DIR, outletCode);
                if (finalFilePath && path_1.default.dirname(finalFilePath) !== BACKUP_DIR) {
                    cleanOldLocalBackups(path_1.default.dirname(finalFilePath), outletCode);
                }
                logMessage("Hourly backup job execution finished.");
            }
            catch (err) {
                logMessage(`Backup job failed: ${err.message}`, true);
            }
            finally {
                activeBackupJobs.delete(outletCode);
            }
        });
    });
}
module.exports = { startBackupJob };
