import fs from "fs";
import path from "path";
import { upsertClient } from "./driveService";
import loadConfig from "../utils/decryptConfig";
import { startBackupJob } from "../jobs/backupJob";
import { autoRestoreLatest } from "./restore";

const rootDir = (process as any).pkg ? path.dirname(process.execPath) : process.cwd();
const CLIENT_FILE = path.join(rootDir, "client.json");

export async function touchClient(outletCode: string): Promise<void> {
    if (!outletCode) {
        console.error("[TOUCH] Missing outletCode parameter.");
        return;
    }

    try {
        if (!fs.existsSync(CLIENT_FILE)) {
            return;
        }
        const config = loadConfig();

        const fileData = fs.readFileSync(CLIENT_FILE, "utf8");
        let clients = JSON.parse(fileData);
        if (!Array.isArray(clients)) {
            clients = [clients];
        }

        const targetClient = clients.find((c: any) => c && c.outlet_code === outletCode);

        if (targetClient) {
            startBackupJob(targetClient, config);
            await upsertClient(targetClient);
        } else {
            console.warn(`[TOUCH] Outlet configuration for ${outletCode} not found.`);
        }
    } catch (err: any) {
        console.error(`[TOUCH] Client sync failed: ${err.message}`);
    }
}

export async function syncDatabaseOnly(req: any, res: any): Promise<any> {
    try {
        const outletCode = req.user?.outlet_code || req.query?.outlet_code || req.body?.outlet_code;

        if (!outletCode) {
            return res.status(400).json({
                success: false,
                message: "Missing outlet code in request."
            });
        }

        const fileData = fs.readFileSync(CLIENT_FILE, "utf8");
        let clients = JSON.parse(fileData);

        if (!Array.isArray(clients)) {
            clients = [clients];
        }

        const targetClient = clients.find((c: any) => c && c.outlet_code === outletCode);

        if (!targetClient || !targetClient.folderId) {
            return res.status(404).json({
                success: false,
                message: "Client not found or missing Google Drive folder ID."
            });
        }

        console.log(`[SYNC] Executing on-demand database sync from folder: ${targetClient.folderId}`);

        // Prefer proprietary .fambak archive restoration
        try {
            const propertyDb = require("../db/models");
            const activeDb = req.propertyDb || propertyDb.sequelize || propertyDb;
            const { TenantBackupService } = require("../services/tenantBackup.service");

            const backups = await TenantBackupService.listBackups(activeDb, outletCode, true);
            const fambakBackup = backups.find((b: any) => b && b.filename && (b.filename.endsWith('.fambak') || b.filename.endsWith('.posbak')));
            if (fambakBackup && fambakBackup.filename) {
                const filePath = TenantBackupService.resolveBackupFilePath(fambakBackup.filename, outletCode, true);
                if (filePath && fs.existsSync(filePath)) {
                    console.log(`[SYNC] Restoring via proprietary .fambak snapshot: ${fambakBackup.filename}`);
                    const fileBuffer = fs.readFileSync(filePath);
                    const restoreRes = await TenantBackupService.restoreFambakBackup(activeDb, fileBuffer, {
                        scope: 'OUTLET',
                        selectedOutletCode: outletCode,
                        targetOutletCode: outletCode,
                        overwriteExisting: false
                    });
                    console.log(`[SYNC] .fambak restoration complete: ${restoreRes.totalRecordsRestored} records restored.`);
                    return res.json({
                        success: true,
                        message: `Database cleanly synced via .fambak archive (${restoreRes.totalRecordsRestored} records restored). No duplicates created.`,
                        details: restoreRes
                    });
                }
            }
        } catch (fambakErr: any) {
            console.warn(`[SYNC] .fambak pre-check skipped (${fambakErr.message}). Continuing...`);
        }

        await autoRestoreLatest(targetClient.folderId, outletCode);

        console.log("[SYNC] Database sync sequence complete. Local data is up to date.");

        res.json({
            success: true,
            message: "Database synced successfully!"
        });

    } catch (error: any) {
        console.error(`[SYNC] Critical Sync Failure: ${error.message}`);

        res.status(500).json({
            success: false,
            message: "Data sync failed: " + error.message
        });
    }
}

export default { touchClient, syncDatabaseOnly };
