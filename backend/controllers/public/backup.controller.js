"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const { getBackupStatus, toggleCloudBackup, updateSyncSuccess, isCloudEnvironment } = require("../../utils/backupTracker");
const { processBackup } = require("../../modules/backupService");
const { restoreFromEncBuffer } = require("../../modules/restore");
const { uploadBackupViaScript, cleanOldBackups, createClientFolder } = require("../../modules/driveService");
const loadConfig = require("../../utils/decryptConfig");
const fs = require("fs");
const path = require("path");
const rootDir = process.pkg ? path.dirname(process.execPath) : process.cwd();
const CLIENT_FILE = path.join(rootDir, "client.json");
const BACKUP_DIR = path.join(rootDir, 'backups');
exports.getBackupStatusAlert = async (req, res) => {
    try {
        const outletCode = req.outlet_code;
        let status = getBackupStatus(outletCode);
        // Reconcile with database system_settings.is_cloud_enabled
        try {
            const propertyDb = require("../../db/models");
            const activeDb = propertyDb.sequelize || propertyDb;
            const [settingsRows] = await activeDb.query("SELECT is_cloud_enabled FROM system_settings LIMIT 1;").catch(() => [[]]);
            if (settingsRows && settingsRows[0] && typeof settingsRows[0].is_cloud_enabled !== "undefined") {
                const dbCloudEnabled = !!settingsRows[0].is_cloud_enabled;
                if (!dbCloudEnabled && status.isCloudEnabled) {
                    toggleCloudBackup(outletCode, false);
                    status = getBackupStatus(outletCode);
                }
                else if (dbCloudEnabled && !status.isCloudEnabled && !status.userManuallyDisabled) {
                    toggleCloudBackup(outletCode, true);
                    status = getBackupStatus(outletCode);
                }
            }
        }
        catch (_) { }
        let alertType = "NONE";
        if (!status.isCloudEnabled) {
            alertType = "ENABLE_PROMPT";
        }
        else {
            const now = new Date().getTime();
            if (!status.lastSyncTime || (now - status.lastSyncTime) > 86400000) {
                alertType = "SYNC_FAILED";
            }
        }
        return res.status(200).json({
            success: true,
            alert: alertType,
            isCloudEnabled: !!status.isCloudEnabled,
            lastSyncTime: status.lastSyncTime
        });
    }
    catch (err) {
        console.error("Backup Status Controller Error:", err);
        return res.status(500).json({
            success: false,
            error: "Internal server error while checking backup status."
        });
    }
};
exports.toggleBackup = async (req, res) => {
    try {
        const outletCode = req.outlet_code || req.body.outlet_code;
        const { enabled } = req.body;
        toggleCloudBackup(outletCode, !!enabled);
        // ALWAYS synchronize database system_settings.is_cloud_enabled with JSON tracker
        try {
            const propertyDb = require("../../db/models");
            const activeDb = propertyDb.sequelize || propertyDb;
            await activeDb.query("UPDATE system_settings SET is_cloud_enabled = :enabled;", { replacements: { enabled: !!enabled } }).catch(() => { });
        }
        catch (_) { }
        try {
            const { BackupManagementController } = require("../backup/backupManagement.controller");
            BackupManagementController.invalidateStatsCache();
        }
        catch (_) { }
        return res.status(200).json({
            success: true,
            message: enabled ? "Cloud backup enabled" : "Cloud backup disabled"
        });
    }
    catch (err) {
        console.error("Toggle Backup Error:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
};
exports.createLocalEncBackup = async (req, res) => {
    try {
        const { isCloudEnvironment } = require("../../utils/backupTracker");
        const { TenantBackupService } = require("../../services/tenantBackup.service");
        const propertyDb = require("../../db/models");
        const activeDb = req.propertyDb || propertyDb.sequelize || propertyDb;

        const outletCode = String(req.user?.outlet_code || req.outlet_code || req.query?.outlet_code || "DEFAULT").trim();
        const outletId = Number(req.user?.outlet_id || req.outlet_id || 1);

        console.log(`[BACKUP] Generating secured .fambak archive for outlet ${outletCode}...`);

        const result = await TenantBackupService.createFambakBackup(activeDb, {
            scope: 'OUTLET',
            outletId,
            outletCode,
            saveToDrive: false
        });

        const fileBuffer = fs.readFileSync(result.filePath);

        return res.status(200).json({
            success: true,
            message: `Secured .fambak backup archive generated successfully for ${outletCode}.`,
            data: {
                filename: result.filename,
                base64: fileBuffer.toString("base64")
            }
        });
    } catch (err) {
        console.error("Local .fambak backup error:", err);
        return res.status(500).json({
            success: false,
            message: err.message || "Failed to create .fambak backup archive."
        });
    }
};
exports.restoreFromLocalEnc = async (req, res) => {
    try {
        const { isCloudEnvironment } = require("../../utils/backupTracker");
        const isCloud = isCloudEnvironment();

        let body = req.body || {};
        if ((!body || Object.keys(body).length === 0) && req.rawBody) {
            try { body = JSON.parse(req.rawBody.toString('utf8')); } catch (_) {}
        }
        const filename = String(body.filename || "").trim();
        const base64 = String(body.base64 || "").trim();
        if (!filename.toLowerCase().endsWith(".enc") && !filename.toLowerCase().endsWith(".fambak") && !filename.toLowerCase().endsWith(".posbak")) {
            return res.status(400).json({
                success: false,
                message: "Only proprietary .fambak secured backup archives are allowed."
            });
        }
        if (!base64) {
            return res.status(400).json({
                success: false,
                message: "Backup payload is required."
            });
        }

        const lowerName = filename.toLowerCase();

        // STRICT CLOUD ENFORCEMENT: Legacy .enc is forbidden on cloud
        if (isCloud && lowerName.endsWith(".enc")) {
            return res.status(403).json({
                success: false,
                message: "Legacy .enc backup files are strictly disabled on cloud servers. Only secured .fambak archives are allowed."
            });
        }

        const encBuffer = Buffer.from(base64, "base64");
        if (!encBuffer.length) {
            return res.status(400).json({
                success: false,
                message: "Invalid backup payload."
            });
        }

        if (lowerName.endsWith(".fambak") || lowerName.endsWith(".posbak")) {
            const { TenantBackupService } = require('../../services/tenantBackup.service');
            const propertyDb = require('../../db/models');
            const activeDb = req.propertyDb || propertyDb.sequelize || propertyDb;
            const outletCode = String(req.user?.outlet_code || req.outlet_code || body.outlet_code || "").trim();

            const restoreResult = await TenantBackupService.restoreFambakBackup(activeDb, encBuffer, {
                scope: (isCloud || outletCode) ? 'OUTLET' : 'ALL',
                selectedOutletCode: outletCode || undefined,
                targetOutletCode: outletCode || undefined,
                overwriteExisting: true
            });
            return res.status(200).json({
                success: true,
                message: `Secured .fambak archive restored successfully from ${filename} (${restoreResult.totalRecordsRestored} records restored across ${restoreResult.tablesRestored.length} tables).`,
                outlet_code: restoreResult.restoredOutletCode || outletCode,
                details: restoreResult
            });
        }

        // Offline legacy fallback only (if not in cloud)
        await restoreFromEncBuffer(encBuffer);
        let primaryOutletCode = "";
        try {
            const propertyDb = require('../../db/models');
            const [outlets] = await (propertyDb.sequelize || propertyDb).query("SELECT outlet_code FROM outlets ORDER BY id ASC LIMIT 1;").catch(() => []);
            if (outlets && outlets[0] && outlets[0].outlet_code) {
                primaryOutletCode = outlets[0].outlet_code;
            }
        } catch (_) {}
        return res.status(200).json({
            success: true,
            message: "Backup restored successfully from legacy .enc file.",
            outlet_code: primaryOutletCode
        });
    } catch (err) {
        console.error("Restore backup error:", err);
        return res.status(500).json({
            success: false,
            message: err.message || "Failed to restore backup archive."
        });
    }
};

exports.uploadBackupOnDemand = async (req, res) => {
    try {
        const outletCode = req.user?.outlet_code || req.outlet_code;

        if (!outletCode) {
            return res.status(400).json({
                success: false,
                message: "Missing outlet code in request."
            });
        }

        const isCloudServer = isCloudEnvironment();
        console.log(`[BACKUP] Starting secured .fambak backup sequence for outlet ${outletCode} (cloud: ${isCloudServer})...`);

        const { TenantBackupService } = require('../../services/tenantBackup.service');
        const propertyDb = require('../../db/models');
        const activeDb = req.propertyDb || propertyDb.sequelize || propertyDb;

        const fambakResult = await TenantBackupService.createFambakBackup(activeDb, {
            scope: 'OUTLET',
            outletCode: outletCode,
            saveToDrive: !isCloudServer
        });

        updateSyncSuccess(outletCode);

        return res.status(200).json({
            success: true,
            message: isCloudServer
                ? `Secured .fambak archive for ${outletCode} created on cloud storage successfully!`
                : `Secured .fambak archive for ${outletCode} created and synced successfully!`,
            filename: fambakResult.filename,
            totalRecords: fambakResult.totalRecords,
            storage_mode: isCloudServer ? 'ENTERPRISE_CLOUD' : 'LOCAL_DRIVE'
        });

    } catch (err) {
        console.error("On-demand backup upload failed:", err);
        return res.status(500).json({
            success: false,
            message: err.message || "Failed to create and upload secured .fambak backup."
        });
    }
};
module.exports = exports;
exports.default = exports;
