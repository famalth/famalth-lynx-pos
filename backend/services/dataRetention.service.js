"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DataRetentionService = exports.RETENTION_TABLES = void 0;
const sequelize_1 = require("sequelize");
const tenantBackup_service_1 = __importDefault(require("./tenantBackup.service"));
exports.RETENTION_TABLES = [
    // 1. Restaurant / KOT child & header tables
    { table: 'kot_revisions', module: 'SALES', isChild: true, parentTable: 'kot_headers', parentFk: 'kot_header_id' },
    { table: 'kot_items', module: 'SALES', isChild: true, parentTable: 'kot_headers', parentFk: 'kot_header_id' },
    { table: 'kot_headers', module: 'SALES', dateColumn: 'created_at' },
    { table: 'restaurant_audit_trail', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'table_reservations', module: 'SALES', dateColumn: 'created_at' },
    // 2. Lucky Draw Campaign & WhatsApp tables
    { table: 'draw_vouchers', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'customer_draw_progress', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'lucky_draw_campaigns', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'whatsapp_logs', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'whatsapp_campaigns', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    // 3. Supplier Returns & Goods Receipts
    { table: 'supplier_return_refunds', module: 'PURCHASES', isChild: true, parentTable: 'supplier_return_headers', parentFk: 'return_id' },
    { table: 'supplier_return_items', module: 'PURCHASES', isChild: true, parentTable: 'supplier_return_headers', parentFk: 'return_id' },
    { table: 'supplier_return_headers', module: 'PURCHASES', dateColumn: 'created_at' },
    { table: 'goods_receipt_items', module: 'PURCHASES', isChild: true, parentTable: 'goods_receipts', parentFk: 'grn_id' },
    { table: 'goods_receipts', module: 'PURCHASES', dateColumn: 'created_at' },
    { table: 'supplier_payments', module: 'PURCHASES', dateColumn: 'created_at' },
    { table: 'supplier_bills', module: 'PURCHASES', dateColumn: 'created_at' },
    // 4. Purchase Orders
    { table: 'purchase_order_items', module: 'PURCHASES', isChild: true, parentTable: 'purchase_orders', parentFk: 'po_id' },
    { table: 'purchase_orders', module: 'PURCHASES', dateColumn: 'created_at' },
    // 5. Stock Issues / Returns / Damages / Assembly / Requests / Delivery Challans
    { table: 'return_items', module: 'INVENTORY', isChild: true, parentTable: 'return_headers', parentFk: 'return_id' },
    { table: 'return_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'issue_items', module: 'INVENTORY', isChild: true, parentTable: 'issue_headers', parentFk: 'issue_id' },
    { table: 'issue_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'damage_items', module: 'INVENTORY', isChild: true, parentTable: 'damage_headers', parentFk: 'damage_id' },
    { table: 'damage_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'assembly_items', module: 'INVENTORY', isChild: true, parentTable: 'assembly_headers', parentFk: 'assembly_id' },
    { table: 'assembly_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'request_items', module: 'INVENTORY', isChild: true, parentTable: 'request_headers', parentFk: 'request_id' },
    { table: 'request_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'delivery_challan_items', module: 'INVENTORY', isChild: true, parentTable: 'delivery_challan_headers', parentFk: 'challan_id' },
    { table: 'delivery_challan_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    // 6. Milk Subscriptions
    { table: 'milk_subscription_consumptions', module: 'SALES', isChild: true, parentTable: 'milk_subscriptions', parentFk: 'subscription_id' },
    { table: 'milk_subscription_items', module: 'SALES', isChild: true, parentTable: 'milk_subscriptions', parentFk: 'subscription_id' },
    { table: 'milk_subscription_schemes', module: 'SALES', isChild: true, parentTable: 'milk_subscriptions', parentFk: 'subscription_id' },
    { table: 'milk_subscription_settlements', module: 'SALES', isChild: true, parentTable: 'milk_subscriptions', parentFk: 'subscription_id' },
    { table: 'milk_subscriptions', module: 'SALES', dateColumn: 'created_at' },
    // 7. HRMS Transactional Tables
    { table: 'hr_loan_transactions', module: 'HRMS', isChild: true, parentTable: 'hr_loans', parentFk: 'loan_id' },
    { table: 'hr_loans', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_sales_commissions', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_cashier_handovers', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_payroll_details', module: 'HRMS', isChild: true, parentTable: 'hr_payroll_runs', parentFk: 'payroll_run_id' },
    { table: 'hr_payroll_runs', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_salary_revisions', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_arrears', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_attendance_punches', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_leave_balances', module: 'HRMS', dateColumn: 'created_at' },
    { table: 'hr_leave_applications', module: 'HRMS', dateColumn: 'created_at' },
    // 8. Clinic & OPD Appointments
    { table: 'clinic_appointments', module: 'CLINIC', dateColumn: 'created_at' },
    // 9. Sales & Customer Transactions
    { table: 'sales_items', module: 'SALES', isChild: true, parentTable: 'sales_headers', parentFk: 'sale_id' },
    { table: 'sales_refunds', module: 'SALES', isChild: true, parentTable: 'sales_headers', parentFk: 'sale_id' },
    { table: 'sales_credit_notes', module: 'SALES', dateColumn: 'created_at' },
    { table: 'customer_repayments', module: 'SALES', dateColumn: 'created_at' },
    { table: 'customer_item_advances', module: 'SALES', dateColumn: 'created_at' },
    { table: 'customer_advances', module: 'SALES', dateColumn: 'created_at' },
    { table: 'customer_orders', module: 'SALES', dateColumn: 'created_at' },
    { table: 'sales_headers', module: 'SALES', dateColumn: 'created_at' },
    { table: 'sales_scheme_customers', module: 'SALES', dateColumn: 'created_at' },
    { table: 'customer_loyalty_ledger', module: 'SALES', dateColumn: 'created_at' },
    // 9. Finance, Expenses & Accounting
    { table: 'cash_ledger', module: 'FINANCE', dateColumn: 'created_at' },
    { table: 'expense_taxes', module: 'FINANCE', isChild: true, parentTable: 'expenses', parentFk: 'expense_id' },
    { table: 'expense_deductions', module: 'FINANCE', isChild: true, parentTable: 'expenses', parentFk: 'expense_id' },
    { table: 'expense_entries', module: 'FINANCE', dateColumn: 'created_at' },
    { table: 'expenses', module: 'FINANCE', dateColumn: 'created_at' },
    { table: 'daily_opening_balances', module: 'FINANCE', dateColumn: 'created_at' },
    { table: 'voucher_lines', module: 'FINANCE', isChild: true, parentTable: 'accounting_vouchers', parentFk: 'voucher_id' },
    { table: 'accounting_vouchers', module: 'FINANCE', dateColumn: 'created_at' },
    // 10. Stock Ledger, Stock Transfers, Notifications, Audits, Night Audit
    { table: 'stock_transfer_items', module: 'INVENTORY', isChild: true, parentTable: 'stock_transfer_headers', parentFk: 'transfer_id' },
    { table: 'stock_transfer_headers', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'stock_ledger', module: 'INVENTORY', dateColumn: 'created_at' },
    { table: 'system_notifications', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'audit_logs', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    { table: 'night_audit_details', module: 'AUDIT_LOGS', isChild: true, parentTable: 'night_audit_runs', parentFk: 'audit_run_id' },
    { table: 'night_audit_runs', module: 'AUDIT_LOGS', dateColumn: 'created_at' },
    // 11. Outlet-Scoped Master Data (Excluding Users)
    // HR & Payroll Masters (employees & payroll setup scoped strictly to outlet_id)
    { table: 'hr_penalties', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_employees', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_departments', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_designations', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_offices', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_shifts', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_pay_structures', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_salary_components', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_leave_types', module: 'HR_MASTERS', dateColumn: 'created_at' },
    { table: 'hr_holidays', module: 'HR_MASTERS', dateColumn: 'created_at' },
    // Retail Masters (excluding users)
    { table: 'bill_value_promos', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'sales_schemes', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'item_master', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'product_templates', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'item_attributes', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'customers', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'suppliers', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'tax_group_components', module: 'RETAIL_MASTERS', isChild: true, parentTable: 'tax_groups', parentFk: 'tax_group_id' },
    { table: 'tax_groups', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'taxes_master', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'tax_profiles', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    { table: 'stock_locations', module: 'RETAIL_MASTERS', dateColumn: 'created_at' },
    // Clinic Masters
    { table: 'clinic_doctors', module: 'CLINIC_MASTERS', dateColumn: 'created_at' },
    { table: 'clinic_services', module: 'CLINIC_MASTERS', dateColumn: 'created_at' },
    { table: 'clinic_patients', module: 'CLINIC_MASTERS', dateColumn: 'created_at' },
    // Restaurant Masters
    { table: 'restaurant_tables', module: 'RESTAURANT_MASTERS', dateColumn: 'created_at' },
    { table: 'restaurant_floors', module: 'RESTAURANT_MASTERS', dateColumn: 'created_at' },
    { table: 'kitchen_stations', module: 'RESTAURANT_MASTERS', dateColumn: 'created_at' },
    { table: 'kot_printers', module: 'RESTAURANT_MASTERS', dateColumn: 'created_at' },
    // 12. Users (Outlet-Scoped, always preserves primary admin_<outletCode> account)
    { table: 'users', module: 'USERS', dateColumn: 'created_at' },
];
class DataRetentionService {
    /**
     * Helper: Builds SQL WHERE clause fragment for outlet and date range
     */
    static buildFilterClause(def, options, replacements) {
        const isAllOutlets = options.allOutlets === true;
        const outletId = Number(options.outletId || 1);
        const conditions = [];
        // 1. Outlet Scoping
        if (!isAllOutlets) {
            if (def.isChild && def.parentTable && def.parentFk) {
                // Child table scoped through parent
                conditions.push(`"${def.parentFk}" IN (SELECT id FROM "${def.parentTable}" WHERE outlet_id = :outletId)`);
            }
            else {
                conditions.push(`outlet_id = :outletId`);
            }
            replacements.outletId = outletId;
        }
        // Preserve primary outlet admin account (admin_<outletCode>) when purging users
        if (def.table === 'users') {
            const outletCode = String(options.outletCode || '').trim();
            if (outletCode) {
                replacements.adminUsernameExact = `admin_${outletCode}`.toLowerCase();
                replacements.adminUsernamePrefix = `admin_${outletCode}_%`.toLowerCase();
                conditions.push(`LOWER(TRIM(username)) != :adminUsernameExact`);
                conditions.push(`LOWER(TRIM(username)) NOT LIKE :adminUsernamePrefix`);
            }
            else {
                conditions.push(`LOWER(TRIM(username)) NOT LIKE 'admin_outlet%'`);
            }
        }
        // 2. Date Filtering
        const retType = options.retentionType || (options.olderThanYears ? 'OLDER_THAN' : 'ALL_TIME');
        if (retType === 'OLDER_THAN') {
            const years = Number(options.olderThanYears || 5);
            const cutoffDate = new Date(Date.now() - years * 365.25 * 24 * 60 * 60 * 1000).toISOString();
            replacements.cutoffDate = cutoffDate;
            if (def.isChild && def.parentTable && def.parentFk) {
                conditions.push(`"${def.parentFk}" IN (SELECT id FROM "${def.parentTable}" WHERE created_at < :cutoffDate)`);
            }
            else {
                conditions.push(`created_at < :cutoffDate`);
            }
        }
        else if (retType === 'DATE_RANGE') {
            if (options.startDate) {
                replacements.startDate = new Date(options.startDate).toISOString();
                if (def.isChild && def.parentTable && def.parentFk) {
                    conditions.push(`"${def.parentFk}" IN (SELECT id FROM "${def.parentTable}" WHERE created_at >= :startDate)`);
                }
                else {
                    conditions.push(`created_at >= :startDate`);
                }
            }
            if (options.endDate) {
                replacements.endDate = new Date(options.endDate).toISOString();
                if (def.isChild && def.parentTable && def.parentFk) {
                    conditions.push(`"${def.parentFk}" IN (SELECT id FROM "${def.parentTable}" WHERE created_at <= :endDate)`);
                }
                else {
                    conditions.push(`created_at <= :endDate`);
                }
            }
        }
        return conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    }
    /**
     * Helper: Filter table definitions by requested modules
     */
    static getSelectedTables(modules) {
        if (!modules || modules.length === 0 || modules.includes('ALL')) {
            return exports.RETENTION_TABLES;
        }
        const set = new Set(modules.map(m => m.toUpperCase()));
        return exports.RETENTION_TABLES.filter(t => set.has(t.module.toUpperCase()));
    }
    /**
     * 1. Dry-Run Retention Preview
     * Counts how many records will be deleted without touching the database.
     */
    static async previewRetentionPurge(activeDb, options) {
        let resolvedOutletId = Number(options.outletId || 0);
        let resolvedOutletCode = String(options.outletCode || '').trim();
        if (resolvedOutletCode && !resolvedOutletId) {
            try {
                const [oRow] = await activeDb.query(`SELECT id, outlet_code FROM outlets WHERE outlet_code = :code LIMIT 1;`, { replacements: { code: resolvedOutletCode }, type: sequelize_1.QueryTypes.SELECT });
                if (oRow?.id) {
                    resolvedOutletId = Number(oRow.id);
                    resolvedOutletCode = String(oRow.outlet_code || resolvedOutletCode);
                }
            }
            catch (_) { }
        }
        if (!resolvedOutletId)
            resolvedOutletId = 1;
        if (!resolvedOutletCode)
            resolvedOutletCode = `OUT_${resolvedOutletId}`;
        options.outletId = resolvedOutletId;
        options.outletCode = resolvedOutletCode;
        const selectedTables = this.getSelectedTables(options.modules);
        const breakdown = [];
        let totalMatchingRecords = 0;
        for (const def of selectedTables) {
            const replacements = {};
            const whereClause = this.buildFilterClause(def, options, replacements);
            const queryStr = `SELECT COUNT(*) as count FROM "${def.table}" ${whereClause};`;
            try {
                const rows = await activeDb.query(queryStr, {
                    replacements,
                    type: sequelize_1.QueryTypes.SELECT
                }).catch(() => [{ count: 0 }]);
                const count = Number(rows?.[0]?.count || 0);
                if (count > 0) {
                    breakdown.push({
                        table: def.table,
                        module: def.module,
                        count
                    });
                    totalMatchingRecords += count;
                }
            }
            catch (_) {
                // Table may not exist in specific tenant schemas
            }
        }
        const retType = options.retentionType || (options.olderThanYears ? 'OLDER_THAN' : 'ALL_TIME');
        let policyDesc = 'All Historical Records';
        if (retType === 'OLDER_THAN') {
            policyDesc = `Older than ${options.olderThanYears || 5} Years (Statutory Retention Policy)`;
        }
        else if (retType === 'DATE_RANGE') {
            policyDesc = `Custom Date Range: ${options.startDate || 'Start'} to ${options.endDate || 'End'}`;
        }
        return {
            totalMatchingRecords,
            breakdown,
            scope: options.allOutlets ? 'ENTERPRISE_ALL_OUTLETS' : `OUTLET_${options.outletCode || options.outletId || 'SELECTED'}`,
            retentionPolicy: policyDesc,
        };
    }
    /**
     * 2. Execute Retention Purge
     * Executes deletion inside a safe rollback-capable database transaction.
     * If createBackupFirst is true, creates a complete backup archive before deletion.
     */
    static async executeRetentionPurge(activeDb, options) {
        const isAllOutlets = options.allOutlets === true;
        let outletId = Number(options.outletId || 0);
        let outletCode = String(options.outletCode || '').trim();
        if (outletCode) {
            try {
                const [oRow] = await activeDb.query(`SELECT id, outlet_code FROM outlets WHERE outlet_code = :code LIMIT 1;`, { replacements: { code: outletCode }, type: sequelize_1.QueryTypes.SELECT });
                if (oRow && oRow.id) {
                    outletId = Number(oRow.id);
                    outletCode = String(oRow.outlet_code || outletCode);
                }
            }
            catch (_) { }
        }
        else if (outletId) {
            try {
                const [oRow] = await activeDb.query(`SELECT id, outlet_code FROM outlets WHERE id = :id LIMIT 1;`, { replacements: { id: outletId }, type: sequelize_1.QueryTypes.SELECT });
                if (oRow && oRow.outlet_code) {
                    outletCode = String(oRow.outlet_code);
                }
            }
            catch (_) { }
        }
        if (!outletId)
            outletId = 1;
        if (!outletCode)
            outletCode = `OUT_${outletId}`;
        options.outletId = outletId;
        options.outletCode = outletCode;
        // STEP 1: Mandatory / Optional Safety Backup Snapshot
        let backupResult = null;
        if (options.createBackupFirst !== false) {
            console.log(`🛡️ [RETENTION] Generating pre-purge safety backup snapshot before deleting data...`);
            try {
                backupResult = await tenantBackup_service_1.default.createFambakBackup(activeDb, {
                    scope: isAllOutlets ? 'ALL' : 'OUTLET',
                    outletId,
                    outletCode,
                    saveToDrive: true,
                });
                // If email provided, send recovery email with link
                if (options.recipientEmail && options.req) {
                    const { BackupManagementController } = require('../controllers/backup/backupManagement.controller');
                    await BackupManagementController.sendDisasterRecoveryEmail({
                        activeDb,
                        filePath: backupResult.filePath,
                        filename: backupResult.filename,
                        recipientEmail: options.recipientEmail,
                        outletCode,
                        outletId,
                        req: options.req,
                        scope: isAllOutlets ? 'ALL' : 'OUTLET',
                    }).catch((e) => console.warn('Pre-purge email link warning:', e.message));
                }
            }
            catch (backupErr) {
                console.error('❌ [RETENTION] Safety backup failed:', backupErr.message);
                throw new Error(`Safety backup failed prior to purge. Aborting deletion for data security: ${backupErr.message}`);
            }
        }
        // STEP 2: Execute Scoped Deletions in Safe Database Transaction
        const selectedTables = this.getSelectedTables(options.modules);
        let totalDeletedRecords = 0;
        const breakdown = [];
        await activeDb.transaction(async (t) => {
            // Break circular/self-referential FKs before scoped deletions
            const fkBreaks = isAllOutlets
                ? [
                    `UPDATE "sales_headers" SET original_sale_id = NULL, previous_sale_id = NULL, replaced_by_sale_id = NULL;`,
                    `UPDATE "kot_headers" SET sales_header_id = NULL;`,
                    `UPDATE "hr_employees" SET level1_approver_id = NULL, level2_approver_id = NULL;`,
                ]
                : [
                    `UPDATE "sales_headers" SET original_sale_id = NULL, previous_sale_id = NULL, replaced_by_sale_id = NULL WHERE outlet_id = :outletId;`,
                    `UPDATE "kot_headers" SET sales_header_id = NULL WHERE outlet_id = :outletId;`,
                    `UPDATE "hr_employees" SET level1_approver_id = NULL, level2_approver_id = NULL WHERE outlet_id = :outletId;`,
                ];
            for (const q of fkBreaks) {
                try {
                    await activeDb.query('SAVEPOINT sp_fk', { transaction: t });
                    await activeDb.query(q, { replacements: { outletId }, transaction: t });
                    await activeDb.query('RELEASE SAVEPOINT sp_fk', { transaction: t });
                }
                catch (_) {
                    await activeDb.query('ROLLBACK TO SAVEPOINT sp_fk', { transaction: t }).catch(() => {});
                }
            }
            // Child tables first, parents last
            for (const def of selectedTables) {
                const replacements = {};
                const whereClause = this.buildFilterClause(def, options, replacements);
                const queryStr = `DELETE FROM "${def.table}" ${whereClause};`;
                try {
                    await activeDb.query('SAVEPOINT sp_purge', { transaction: t });
                    const [, meta] = await activeDb.query(queryStr, {
                        replacements,
                        transaction: t,
                    });
                    await activeDb.query('RELEASE SAVEPOINT sp_purge', { transaction: t });
                    const rowCount = typeof meta === 'number' ? meta : (meta?.rowCount || 0);
                    if (rowCount > 0) {
                        breakdown.push({ table: def.table, deleted: rowCount });
                        totalDeletedRecords += rowCount;
                    }
                }
                catch (delErr) {
                    await activeDb.query('ROLLBACK TO SAVEPOINT sp_purge', { transaction: t }).catch(() => {});
                    console.warn(`[RETENTION] Warning deleting from ${def.table}: ${delErr.message}`);
                }
            }
            // Realign bank account opening balances if all finance was cleared
            if (options.modules?.includes('FINANCE') || options.modules?.includes('ALL') || !options.modules) {
                try {
                    await activeDb.query('SAVEPOINT sp_bank', { transaction: t });
                    const bankWhere = isAllOutlets ? '' : 'WHERE outlet_id = :outletId';
                    await activeDb.query(`UPDATE "bank_accounts" SET opening_balance = 0.00, current_balance = 0.00 ${bankWhere};`, { replacements: { outletId }, transaction: t });
                    await activeDb.query('RELEASE SAVEPOINT sp_bank', { transaction: t });
                }
                catch (_) {
                    await activeDb.query('ROLLBACK TO SAVEPOINT sp_bank', { transaction: t }).catch(() => {});
                }
            }
            // Optional: Reset sequences & outlet operational settings to default (preserves property_info, outlets, admin_<outletCode>, Gmail/SMTP & WhatsApp config)
            if (options.resetSettingsToDefault === true) {
                const resetQueries = isAllOutlets
                    ? [
                        `UPDATE "document_sequences" SET next_number = 1;`,
                        `UPDATE "numbering_settings" SET next_number = 1;`,
                        `UPDATE "outlet_settings" SET settings = '{}';`,
                    ]
                    : [
                        `UPDATE "document_sequences" SET next_number = 1 WHERE outlet_id = :outletId;`,
                        `UPDATE "numbering_settings" SET next_number = 1 WHERE outlet_id = :outletId;`,
                        `UPDATE "outlet_settings" SET settings = '{}' WHERE outlet_id = :outletId;`,
                    ];
                for (const rq of resetQueries) {
                    try {
                        await activeDb.query('SAVEPOINT sp_reset', { transaction: t });
                        await activeDb.query(rq, { replacements: { outletId }, transaction: t });
                        await activeDb.query('RELEASE SAVEPOINT sp_reset', { transaction: t });
                    }
                    catch (_) {
                        await activeDb.query('ROLLBACK TO SAVEPOINT sp_reset', { transaction: t }).catch(() => {});
                    }
                }
            }
        });
        const retType = options.retentionType || (options.olderThanYears ? 'OLDER_THAN' : 'ALL_TIME');
        let policyDesc = 'All Historical Records';
        if (retType === 'OLDER_THAN') {
            policyDesc = `Older than ${options.olderThanYears || 5} Years`;
        }
        else if (retType === 'DATE_RANGE') {
            policyDesc = `Date Range: ${options.startDate} to ${options.endDate}`;
        }
        console.log(`✅ [RETENTION] Purge completed successfully: ${totalDeletedRecords.toLocaleString()} records removed.`);
        return {
            success: true,
            totalDeletedRecords,
            tablesAffected: breakdown.length,
            backupResult,
            breakdown,
            retentionPolicy: policyDesc,
        };
    }
    /**
     * 3. Automated 5-Year Cloud Data Retention Policy Runner
     * Prunes transactional data older than 5 years enterprise-wide or per outlet.
     */
    static async applyAutomated5YearPolicy(activeDb, options) {
        return this.executeRetentionPurge(activeDb, {
            allOutlets: options.allOutlets ?? false,
            outletId: options.outletId,
            outletCode: options.outletCode,
            retentionType: 'OLDER_THAN',
            olderThanYears: 5,
            modules: ['ALL'],
            createBackupFirst: options.createBackupFirst !== false,
        });
    }
}
exports.DataRetentionService = DataRetentionService;
exports.default = DataRetentionService;
module.exports = DataRetentionService;
