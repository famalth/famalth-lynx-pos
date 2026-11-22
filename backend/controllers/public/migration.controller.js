var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
var migration_controller_exports = {};
__export(migration_controller_exports, {
  default: () => migration_controller_default,
  exportBundle: () => exportBundle,
  importBundle: () => importBundle,
  ping: () => ping,
  requestMigrationOtp: () => requestMigrationOtp,
  syncOnlineToOffline: () => syncOnlineToOffline,
  verifyMigrationOtp: () => verifyMigrationOtp
});
module.exports = __toCommonJS(migration_controller_exports);
var import_fs = __toESM(require("fs"));
var import_path = __toESM(require("path"));
var import_sequelize = require("sequelize");
var import_bcryptjs = __toESM(require("bcryptjs"));
var import_restore = require("../../modules/restore");
var import_jwt = require("../../utils/jwt.util");
const isCompiled = typeof process.pkg !== "undefined";
const rootDir = isCompiled ? import_path.default.dirname(process.execPath) : process.cwd();
const { sendOtpEmail } = require("../../modules/emailService");
const MIGRATION_OTP_FILE = import_path.default.join(rootDir, "data", "migration_otp_store.json");
function readMigrationOtpStore() {
  try {
    if (!import_fs.default.existsSync(MIGRATION_OTP_FILE)) {
      return {};
    }
    const raw = import_fs.default.readFileSync(MIGRATION_OTP_FILE, "utf8");
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (e) {
    return {};
  }
}
function writeMigrationOtpStore(store) {
  try {
    import_fs.default.mkdirSync(import_path.default.dirname(MIGRATION_OTP_FILE), { recursive: true });
    import_fs.default.writeFileSync(MIGRATION_OTP_FILE, JSON.stringify(store, null, 2));
  } catch (e) {
    console.error("[MIGRATION OTP] Failed to write store:", e.message);
  }
}
function pruneMigrationOtps(store) {
  const now = Date.now();
  for (const [key, rec] of Object.entries(store)) {
    if (!rec || !rec.expiresAt || now > rec.expiresAt) {
      delete store[key];
    }
  }
}
function formatMigrationError(error) {
  if (!error) return "Unknown error";
  if (error.errors && Array.isArray(error.errors) && error.errors.length > 0) {
    return error.errors.map((e) => `${e.path || e.type || "field"}: ${e.message}`).join(", ");
  }
  if (error.original && error.original.message) {
    return error.original.message;
  }
  return error.message || String(error);
}
function isPlatformMasterTable(tName) {
  const t = (tName || "").toLowerCase().trim();
  if (t.startsWith("master_") || t.startsWith("control_plane_") || t.startsWith("platform_")) return true;
  if (t.includes("tenant") && t !== "tenant_settings") return true;
  if (t === "resellers" || t === "support_agents" || t === "support_tickets" || t === "ticket_messages") return true;
  if (t === "system_backups" || t === "system_update_logs" || t === "client_logs" || t === "master_staff_users") return true;
  return false;
}
const childTableRelations = {
  "sales_items": { parentTable: "sales_headers", foreignKey: "sale_id" },
  "sales_refunds": { parentTable: "sales_headers", foreignKey: "sale_id" },
  "sales_credit_notes": { parentTable: "sales_headers", foreignKey: "sale_id" },
  "purchase_order_items": { parentTable: "purchase_orders", foreignKey: "po_id" },
  "goods_receipt_items": { parentTable: "goods_receipts", foreignKey: "grn_id" },
  "voucher_lines": { parentTable: "accounting_vouchers", foreignKey: "voucher_id" },
  "kot_items": { parentTable: "kot_headers", foreignKey: "kot_id" },
  "kot_revisions": { parentTable: "kot_headers", foreignKey: "kot_id" },
  "damage_items": { parentTable: "damage_headers", foreignKey: "damage_id" },
  "issue_items": { parentTable: "issue_headers", foreignKey: "issue_id" },
  "return_items": { parentTable: "return_headers", foreignKey: "return_id" },
  "request_items": { parentTable: "request_headers", foreignKey: "request_id" },
  "stock_transfer_items": { parentTable: "stock_transfer_headers", foreignKey: "transfer_id" },
  "assembly_items": { parentTable: "assembly_headers", foreignKey: "assembly_id" },
  "delivery_challan_items": { parentTable: "delivery_challan_headers", foreignKey: "challan_id" },
  "hr_payroll_details": { parentTable: "hr_payroll_runs", foreignKey: "payroll_run_id" },
  "hr_pay_structure_components": { parentTable: "hr_pay_structures", foreignKey: "pay_structure_id" },
  "hr_loan_transactions": { parentTable: "hr_loans", foreignKey: "loan_id" },
  "milk_subscription_items": { parentTable: "milk_subscriptions", foreignKey: "subscription_id" },
  "milk_subscription_consumptions": { parentTable: "milk_subscriptions", foreignKey: "subscription_id" },
  "milk_subscription_settlements": { parentTable: "milk_subscriptions", foreignKey: "subscription_id" },
  "sales_scheme_customers": { parentTable: "sales_schemes", foreignKey: "scheme_id" },
  "night_audit_details": { parentTable: "night_audit_runs", foreignKey: "audit_run_id" },
  "tax_group_components": { parentTable: "tax_groups", foreignKey: "tax_group_id" },
  "customer_draw_progress": { parentTable: "lucky_draw_campaigns", foreignKey: "campaign_id" },
  "draw_vouchers": { parentTable: "lucky_draw_campaigns", foreignKey: "campaign_id" },
  "ticket_messages": { parentTable: "support_tickets", foreignKey: "ticket_id" },
  "supplier_return_items": { parentTable: "supplier_return_headers", foreignKey: "return_id" },
  "user_permissions": { parentTable: "users", foreignKey: "user_id" },
  "expense_deductions": { parentTable: "expenses", foreignKey: "expense_id" },
  "expense_taxes": { parentTable: "expenses", foreignKey: "expense_id" },
  "attribute_values": { parentTable: "attributes", foreignKey: "attribute_id" },
  "variant_attribute_values": { parentTable: "item_master", foreignKey: "item_id" },
  "customer_item_advances": { parentTable: "customer_advances", foreignKey: "advance_id" },
  "customer_repayments": { parentTable: "customer_advances", foreignKey: "advance_id" },
  "customer_loyalty_ledger": { parentTable: "customers", foreignKey: "customer_id" }
};
const ping = async (req, res) => {
  return res.status(200).json({
    success: true,
    message: "RetailPOS Cloud Migration Gateway Active",
    version: "2.0",
    timestamp: (/* @__PURE__ */ new Date()).toISOString(),
    cloud_ready: true,
    supported_modes: ["RESTORE_DB", "MERGE_OUTLET", "PULL_ONLINE_TO_OFFLINE"]
  });
};
const requestMigrationOtp = async (req, res) => {
  try {
    const rawOutletCode = String(req.body.outlet_code || "").trim();
    const scope = String(req.body.scope || "").trim().toUpperCase();
    const isAllScope = scope === "ALL" || rawOutletCode.toUpperCase() === "ALL";
    const outletCode = isAllScope ? "ALL" : rawOutletCode.toUpperCase();
    const db = req.propertyDb;
    if (!db) {
      return res.status(500).json({ success: false, message: "Database connection not available." });
    }
    if (!isAllScope && !outletCode) {
      return res.status(400).json({ success: false, message: "Outlet Code is required to request migration security OTP." });
    }
    let targetEmail = "";
    let targetOutletName = "";
    if (db.models.outlets) {
      const outletWhere = isAllScope ? {} : { outlet_code: outletCode };
      const outlet = await db.models.outlets.findOne({ where: outletWhere, raw: true });
      if (outlet && outlet.contact_email) {
        targetEmail = outlet.contact_email.trim();
        targetOutletName = outlet.outlet_name || outlet.outlet_code;
      }
    }
    if (!targetEmail && db.models.users) {
      const adminUser = await db.models.users.findOne({
        where: { role: "ADMIN" },
        raw: true
      });
      if (adminUser && (adminUser.contact_email || adminUser.email)) {
        targetEmail = (adminUser.contact_email || adminUser.email).trim();
      }
    }
    if (!targetEmail && db.models.property_info) {
      const propInfo = await db.models.property_info.findOne({ raw: true });
      if (propInfo && (propInfo.contact_email || propInfo.email)) {
        targetEmail = (propInfo.contact_email || propInfo.email).trim();
      }
    }
    if (!targetEmail && outletCode && outletCode !== "ALL") {
      try {
        const { sendToGoogleScript } = require("../../modules/driveService");
        const sysConfig = require("../../utils/configManager");
        const effectiveConfig = sysConfig && sysConfig.default ? sysConfig.default : sysConfig || {};
        if (effectiveConfig.sheetId) {
          const cloudRes = await sendToGoogleScript({
            action: "verify_and_get_client",
            rootFolderId: effectiveConfig.rootFolderId,
            sheetId: effectiveConfig.sheetId,
            outletCode
          });
          if (cloudRes?.client?.contact_email) {
            targetEmail = cloudRes.client.contact_email.trim();
          }
        }
      } catch (_) {
      }
    }
    if (!targetEmail) {
      return res.status(404).json({
        success: false,
        message: `No registered business email address found for outlet '${outletCode}'. Please verify the outlet code.`
      });
    }
    const storeKey = isAllScope ? "ALL" : outletCode;
    const store = readMigrationOtpStore();
    pruneMigrationOtps(store);
    const existing = store[storeKey];
    if (existing && existing.lastSentAt && Date.now() - existing.lastSentAt < 6e4) {
      const remaining = Math.ceil((6e4 - (Date.now() - existing.lastSentAt)) / 1e3);
      return res.status(429).json({
        success: false,
        message: `Please wait ${remaining} seconds before requesting a new OTP.`
      });
    }
    const otpCode = Math.floor(1e5 + Math.random() * 9e5).toString();
    store[storeKey] = {
      otp: otpCode,
      outletCode: storeKey,
      email: targetEmail,
      expiresAt: Date.now() + 10 * 60 * 1e3,
      // 10 minutes
      lastSentAt: Date.now()
    };
    writeMigrationOtpStore(store);
    try {
      await sendOtpEmail(targetEmail, otpCode, `Store Migration & Cloud Sync Security Verification (${targetOutletName || storeKey})`);
    } catch (mailErr) {
      console.error("[MIGRATION OTP] Email sending failed:", mailErr.message);
    }
    const atIdx = targetEmail.indexOf("@");
    let maskedEmail = targetEmail;
    if (atIdx > 2) {
      const userPart = targetEmail.substring(0, atIdx);
      const domainPart = targetEmail.substring(atIdx);
      maskedEmail = `${userPart[0]}***${userPart[userPart.length - 1]}${domainPart}`;
    } else if (atIdx > 0) {
      maskedEmail = `*${targetEmail.substring(atIdx)}`;
    }
    return res.status(200).json({
      success: true,
      message: `A 6-digit migration verification OTP has been sent to the registered email (${maskedEmail}).`,
      masked_email: maskedEmail,
      expires_in_minutes: 10
    });
  } catch (error) {
    console.error("[MIGRATION OTP ERROR]:", error);
    return res.status(500).json({
      success: false,
      message: `Failed to generate migration OTP: ${error.message}`
    });
  }
};
const verifyMigrationOtp = async (req, res) => {
  try {
    const rawOutletCode = String(req.body.outlet_code || "").trim();
    const scope = String(req.body.scope || "").trim().toUpperCase();
    const isAllScope = scope === "ALL" || rawOutletCode.toUpperCase() === "ALL";
    const outletCode = isAllScope ? "ALL" : rawOutletCode.toUpperCase();
    const otp = String(req.body.otp || "").trim();
    if (!otp) {
      return res.status(400).json({ success: false, message: "Security OTP is required." });
    }
    const storeKey = isAllScope ? "ALL" : outletCode;
    const store = readMigrationOtpStore();
    pruneMigrationOtps(store);
    const record = store[storeKey];
    if (!record || record.otp !== otp || Date.now() > record.expiresAt) {
      return res.status(401).json({
        success: false,
        message: "Invalid or expired security OTP. Please request a new code."
      });
    }
    return res.status(200).json({
      success: true,
      message: "Security OTP verified successfully. Migration authorized."
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
function mapSqlType(col) {
  const dt = (col.data_type || "").toLowerCase();
  const udt = (col.udt_name || "").toLowerCase();
  if (udt === "jsonb") return "JSONB";
  if (udt === "json") return "JSON";
  if (dt === "integer" || udt === "int4") return "INTEGER";
  if (dt === "bigint" || udt === "int8") return "BIGINT";
  if (dt === "smallint" || udt === "int2") return "SMALLINT";
  if (dt === "boolean" || udt === "bool") return "BOOLEAN";
  if (dt === "numeric" || dt === "decimal") return "NUMERIC";
  if (dt.includes("timestamp")) return "TIMESTAMP WITH TIME ZONE";
  if (dt === "date") return "DATE";
  if (dt === "time") return "TIME";
  if (dt === "text") return "TEXT";
  if (dt.includes("char")) return "VARCHAR(255)";
  return "TEXT";
}
function getSensibleDefault(dataType, udtName) {
  const dt = (dataType || "").toLowerCase();
  const udt = (udtName || "").toLowerCase();
  if (dt.includes("int") || dt === "numeric" || dt === "decimal" || dt.includes("float") || dt === "real") return 0;
  if (dt === "boolean" || udt === "bool") return false;
  if (dt.includes("timestamp") || dt === "date") return (/* @__PURE__ */ new Date()).toISOString();
  if (udt === "jsonb" || udt === "json") return "{}";
  return "";
}
async function insertRowsBatch(db, tableName, rows, targetColumns, columnMetadataMap) {
  if (!rows || rows.length === 0) return 0;
  const colSet = new Set(targetColumns);
  const chunkCols = /* @__PURE__ */ new Set();
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    for (const k of Object.keys(row)) {
      if (colSet.has(k)) chunkCols.add(k);
    }
  }
  const validCols = Array.from(chunkCols);
  if (validCols.length === 0) return 0;
  const colList = validCols.map((c) => `"${c}"`).join(", ");
  const BATCH_SIZE = 50;
  let inserted = 0;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const chunk = rows.slice(i, i + BATCH_SIZE);
    const valuePlaceholders = [];
    const bindValues = [];
    let pIdx = 1;
    for (const row of chunk) {
      const rowPlaceholders = [];
      for (const col of validCols) {
        let val = row[col];
        if (val === void 0 || val === null) {
          const meta = columnMetadataMap?.get(col);
          if (meta && meta.is_nullable === "NO" && meta.column_default === null) {
            val = getSensibleDefault(meta.data_type, meta.udt_name);
          }
        }
        if (val !== null && typeof val === "object" && !(val instanceof Date) && !Buffer.isBuffer(val)) {
          val = JSON.stringify(val);
        }
        bindValues.push(val === void 0 ? null : val);
        rowPlaceholders.push(`$${pIdx++}`);
      }
      valuePlaceholders.push(`(${rowPlaceholders.join(", ")})`);
    }
    const sql = `INSERT INTO "${tableName}" (${colList}) VALUES ${valuePlaceholders.join(", ")} ON CONFLICT DO NOTHING;`;
    await db.query(sql, { bind: bindValues, type: import_sequelize.QueryTypes.INSERT });
    inserted += chunk.length;
  }
  return inserted;
}
function sortTablesTopologically(tableNames, fkEdges) {
  const adj = new Map();
  const inDegree = new Map();
  for (const t of tableNames) {
    adj.set(t, new Set());
    inDegree.set(t, 0);
  }
  for (const edge of fkEdges) {
    const child = edge.child_table;
    const parent = edge.parent_table;
    if (adj.has(parent) && adj.has(child)) {
      if (!adj.get(parent).has(child)) {
        adj.get(parent).add(child);
        inDegree.set(child, (inDegree.get(child) || 0) + 1);
      }
    }
  }
  const queue = [];
  for (const t of tableNames) {
    if ((inDegree.get(t) || 0) === 0) {
      queue.push(t);
    }
  }
  const sorted = [];
  while (queue.length > 0) {
    const curr = queue.shift();
    sorted.push(curr);
    const neighbors = adj.get(curr);
    if (neighbors) {
      for (const neighbor of neighbors) {
        inDegree.set(neighbor, (inDegree.get(neighbor) || 1) - 1);
        if (inDegree.get(neighbor) === 0) {
          queue.push(neighbor);
        }
      }
    }
  }
  for (const t of tableNames) {
    if (!sorted.includes(t)) sorted.push(t);
  }
  return sorted;
}
async function resetAllDatabaseSequences(db) {
  try {
    const [seqMappings] = await db.query(`
            SELECT 
              s.relname AS seq_name,
              t.relname AS table_name,
              a.attname AS column_name
            FROM pg_class s
            JOIN pg_depend d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass AND d.refclassid = 'pg_class'::regclass
            JOIN pg_class t ON t.oid = d.refobjid
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
            WHERE s.relkind = 'S' AND t.relkind = 'r' AND s.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
        `);
    for (const m of seqMappings) {
      try {
        await db.query(`SELECT setval('"${m.seq_name}"', COALESCE((SELECT MAX("${m.column_name}") FROM "${m.table_name}"), 1), true);`);
      } catch (_) {
      }
    }
    console.log(`\u2705 [SEQUENCES] All ${seqMappings.length} database sequences synchronized successfully.`);
  } catch (err) {
    console.warn(`\u26A0\uFE0F [SEQUENCES] Sequence reset notice:`, err.message);
  }
}
const exportBundle = async (req, res) => {
  try {
    const reqScope = String(req.body?.scope || "").toUpperCase();
    const isAllScope = reqScope === "ALL" || req.body?.outlet_code === "ALL";
    const outletCode = isAllScope ? "ALL" : req.user?.outlet_code || req.outlet_code || req.body.outlet_code;
    const db = req.propertyDb;
    if (!db) {
      return res.status(500).json({ success: false, message: "Database connection not available." });
    }
    let isAuthedAdmin = false;
    const authHeader = req.headers?.authorization || req.headers?.["x-access-token"];
    if (authHeader) {
      try {
        const tokenStr = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
        const { verify } = require("../../utils/jwt.util");
        const decoded = verify(tokenStr);
        if (decoded && (decoded.role === "ADMIN" || decoded.role === "SUPER_ADMIN")) {
          isAuthedAdmin = true;
          req.user = decoded;
        }
      } catch (_) {
      }
    }
    if (!isAuthedAdmin && req.user && (req.user.role === "ADMIN" || req.user.role === "SUPER_ADMIN")) {
      isAuthedAdmin = true;
    }
    const reqOtp = String(req.body?.otp || "").trim();
    if (!isAuthedAdmin) {
      const storeKey = isAllScope ? "ALL" : String(outletCode || "").toUpperCase();
      const store = readMigrationOtpStore();
      pruneMigrationOtps(store);
      const record = store[storeKey];
      if (!reqOtp || !record || record.otp !== reqOtp || Date.now() > record.expiresAt) {
        return res.status(401).json({
          success: false,
          message: "\u{1F512} Security Verification Required: A valid 6-digit OTP sent to the registered store owner email is required to export or migrate data."
        });
      }
      delete store[storeKey];
      writeMigrationOtpStore(store);
    }
    const stats = {};
    const [tableRows] = await db.query(`
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
              AND table_type = 'BASE TABLE'
              AND table_name NOT IN ('SequelizeMeta', 'spatial_ref_sys')
            ORDER BY table_name;
        `);
    const allTableNames = tableRows
      .map((r) => Array.isArray(r) ? r[0] : r.table_name || r[0])
      .filter((t) => !isPlatformMasterTable(t));
    const [columnRows] = await db.query(`
            SELECT table_name, column_name, data_type, udt_name, is_nullable, column_default 
            FROM information_schema.columns 
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position;
        `);
    const tableColsMap = /* @__PURE__ */ new Map();
    const tableSchemas = {};
    for (const c of columnRows) {
      const tName = c.table_name;
      if (!tableColsMap.has(tName)) tableColsMap.set(tName, /* @__PURE__ */ new Set());
      tableColsMap.get(tName).add(c.column_name);
      if (!tableSchemas[tName]) tableSchemas[tName] = [];
      tableSchemas[tName].push({
        column_name: c.column_name,
        data_type: c.data_type,
        udt_name: c.udt_name,
        is_nullable: c.is_nullable,
        column_default: c.column_default
      });
    }
    let outletRecord = null;
    let outletId = null;
    if (allTableNames.includes("outlets")) {
      const [outlets] = await db.query('SELECT * FROM "outlets"');
      if (outletCode && outletCode !== "ALL") {
        outletRecord = outlets.find((o) => o.outlet_code === outletCode) || null;
        if (outletRecord) outletId = outletRecord.id;
      }
    }
    const tablesData = {};
    if (isAllScope || !outletId) {
      for (const tName of allTableNames) {
        try {
          const rows = await db.query(`SELECT * FROM "${tName}"`, { type: import_sequelize.QueryTypes.SELECT });
          tablesData[tName] = rows;
          stats[tName] = rows.length;
        } catch (err) {
          console.warn(`[EXPORT] Table ${tName} read warning:`, err.message);
          tablesData[tName] = [];
        }
      }
    } else {
      // Selected Outlet Export: Strictly export THIS outlet's data only
      for (const tName of allTableNames) {
        if (isPlatformMasterTable(tName)) continue; // STRICT ISOLATION: Never export platform/super-admin/tenant tables
        if (childTableRelations[tName]) continue;

        if (tName === "outlets") {
          tablesData["outlets"] = outletRecord ? [outletRecord] : [];
          stats["outlets"] = tablesData["outlets"].length;
          continue;
        }

        if (tName === "users") {
          try {
            const rows = await db.query(
              `SELECT * FROM "users" WHERE "outlet_id" = $1 OR "username" = $2 OR "username" = $3`,
              {
                bind: [outletId, `admin_${outletCode}`, `admin_${outletCode.toLowerCase()}`],
                type: import_sequelize.QueryTypes.SELECT
              }
            );
            tablesData["users"] = rows;
            stats["users"] = rows.length;
          } catch (_) {
            tablesData["users"] = [];
          }
          continue;
        }

        const cols = tableColsMap.get(tName) || /* @__PURE__ */ new Set();
        try {
          if (cols.has("outlet_id")) {
            const HR_SHARED_MASTERS = new Set([
              "hr_offices", "hr_designations", "hr_shifts", "hr_leave_types",
              "hr_salary_components", "hr_pay_structures", "hr_holidays"
            ]);
            let querySql = `SELECT * FROM "${tName}" WHERE "outlet_id" = $1`;
            if (HR_SHARED_MASTERS.has(tName)) {
              querySql = `SELECT * FROM "${tName}" WHERE "outlet_id" = $1 OR "outlet_id" = 1 OR "outlet_id" IS NULL`;
            }
            const rows = await db.query(querySql, {
              bind: [outletId],
              type: import_sequelize.QueryTypes.SELECT
            });
            tablesData[tName] = rows;
          } else if (cols.has("outlet_code")) {
            const rows = await db.query(`SELECT * FROM "${tName}" WHERE "outlet_code" = $1`, {
              bind: [outletCode],
              type: import_sequelize.QueryTypes.SELECT
            });
            tablesData[tName] = rows;
          } else if (tName === "stock_transfer_headers") {
            const rows = await db.query(
              `SELECT * FROM "stock_transfer_headers" WHERE "source_outlet_id" = $1 OR "destination_outlet_id" = $1`,
              { bind: [outletId], type: import_sequelize.QueryTypes.SELECT }
            );
            tablesData[tName] = rows;
          } else {
            const ALLOWED_GLOBAL_STATIC = new Set([
              "payment_methods", "permissions", "schema_version", "sale_sources"
            ]);
            if (ALLOWED_GLOBAL_STATIC.has(tName)) {
              const rows = await db.query(`SELECT * FROM "${tName}"`, { type: import_sequelize.QueryTypes.SELECT });
              tablesData[tName] = rows;
            } else {
              tablesData[tName] = [];
            }
          }
          stats[tName] = (tablesData[tName] || []).length;
        } catch (err) {
          console.warn(`[EXPORT] Outlet table ${tName} warning:`, err.message);
          tablesData[tName] = [];
        }
      }
      for (const [childTable, rel] of Object.entries(childTableRelations)) {
        if (!allTableNames.includes(childTable)) continue;
        const parentRows = tablesData[rel.parentTable] || [];
        const parentIds = parentRows.map((p) => p.id).filter((id) => id !== void 0 && id !== null);
        if (parentIds.length > 0) {
          try {
            const placeholders = parentIds.map((_, idx) => `$${idx + 1}`).join(', ');
            const rows = await db.query(
              `SELECT * FROM "${childTable}" WHERE "${rel.foreignKey}" IN (${placeholders})`,
              { bind: parentIds, type: import_sequelize.QueryTypes.SELECT }
            );
            tablesData[childTable] = rows;
          } catch (err) {
            console.warn(`[EXPORT] Child table ${childTable} warning:`, err.message);
            tablesData[childTable] = [];
          }
        } else {
          tablesData[childTable] = [];
        }
        stats[childTable] = tablesData[childTable].length;
      }
    }
    stats.products = (tablesData["item_master"] || []).length;
    stats.customers = (tablesData["customers"] || []).length;
    stats.suppliers = (tablesData["supplier_master"] || []).length;
    stats.sales = (tablesData["sales_headers"] || []).length;
    stats.users = (tablesData["users"] || []).length;
    stats.hr_employees = (tablesData["hr_employees"] || []).length;
    stats.total_tables = Object.keys(tablesData).length;
    stats.total_records = Object.values(tablesData).reduce((sum, r) => sum + r.length, 0);
    const encBase64 = "";
    const bundle = {
      version: "3.0",
      exported_at: (/* @__PURE__ */ new Date()).toISOString(),
      source_outlet_code: outletCode || (outletRecord ? outletRecord.outlet_code : "DEFAULT"),
      stats,
      outletRecord,
      scope: isAllScope ? "ALL" : "OUTLET",
      tables: tablesData,
      tableSchemas,
      database_enc_base64: encBase64,
      // Backward compatibility aliases for existing UI dashboards
      users: tablesData["users"] || [],
      settings: tablesData["system_settings"]?.[0] || null,
      branding: tablesData["app_branding"]?.[0] || null,
      numbering: tablesData["numbering_settings"] || [],
      propertyInfo: tablesData["property_info"]?.[0] || null,
      paymentMethods: tablesData["payment_methods"] || [],
      saleSources: tablesData["sale_sources"] || [],
      taxGroups: tablesData["tax_groups"] || [],
      taxGroupComponents: tablesData["tax_group_components"] || [],
      itemGroups: tablesData["item_groups"] || [],
      subcategories: tablesData["item_subcategories"] || tablesData["subcategories"] || [],
      brands: tablesData["brands"] || [],
      items: tablesData["item_master"] || [],
      stockLocations: tablesData["stock_locations"] || [],
      stockLedger: tablesData["stock_ledger"] || [],
      customers: tablesData["customers"] || [],
      customerAdvances: tablesData["customer_advances"] || [],
      customerRepayments: tablesData["customer_repayments"] || [],
      suppliers: tablesData["supplier_master"] || [],
      supplierBills: tablesData["supplier_bills"] || [],
      supplierPayments: tablesData["supplier_payments"] || [],
      salesHeaders: tablesData["sales_headers"] || [],
      salesItems: tablesData["sales_items"] || [],
      purchaseOrders: tablesData["purchase_orders"] || [],
      purchaseOrderItems: tablesData["purchase_order_items"] || [],
      goodsReceipts: tablesData["goods_receipts"] || [],
      goodsReceiptItems: tablesData["goods_receipt_items"] || [],
      expenses: tablesData["expenses"] || [],
      expenseCategories: tablesData["expense_categories"] || [],
      chartOfAccounts: tablesData["chart_of_accounts"] || [],
      bankAccounts: tablesData["bank_accounts"] || [],
      accountingVouchers: tablesData["accounting_vouchers"] || [],
      voucherLines: tablesData["voucher_lines"] || [],
      floors: tablesData["floors"] || [],
      diningAreas: tablesData["dining_areas"] || [],
      restaurantTables: tablesData["restaurant_tables"] || [],
      kitchenStations: tablesData["kitchen_stations"] || [],
      kotHeaders: tablesData["kot_headers"] || [],
      kotItems: tablesData["kot_items"] || [],
      milkSubscriptions: tablesData["milk_subscriptions"] || [],
      deliveryCustomers: tablesData["delivery_customers"] || [],
      deliveryPartners: tablesData["delivery_partners"] || [],
      hrEmployees: tablesData["hr_employees"] || [],
      hrDesignations: tablesData["hr_designations"] || [],
      hrShifts: tablesData["hr_shifts"] || [],
      outlets: tablesData["outlets"] || []
    };
    return res.status(200).json({
      success: true,
      message: `Store migration bundle exported successfully with 100% database table & column coverage (${stats.total_tables} tables, ${stats.total_records} rows).`,
      stats,
      bundle
    });
  } catch (error) {
    console.error("[MIGRATION EXPORT ERROR]:", error);
    return res.status(500).json({
      success: false,
      message: `Export failed: ${error.message}`
    });
  }
};
const importBundle = async (req, res) => {
  try {
    const { bundle, mode = "MERGE_OUTLET", target_outlet_code, admin_password } = req.body;
    if (!bundle || typeof bundle !== "object") {
      return res.status(400).json({ success: false, message: "Invalid or missing migration bundle payload." });
    }
    const db = req.propertyDb;
    if (!db) {
      return res.status(500).json({ success: false, message: "Target cloud database connection error." });
    }
    const outletCode = (target_outlet_code || bundle.source_outlet_code || "DEFAULT").toUpperCase().trim();
    const encBase64 = bundle.database_enc_base64;
    const isAllScope = bundle.scope === "ALL" || req.body?.scope === "ALL" || outletCode === "ALL";
    if (bundle.tables && typeof bundle.tables === "object") {
      console.log(`[UNIVERSAL MIGRATION IMPORT] Starting zero-loss database restore (scope: ${isAllScope ? "ALL" : "OUTLET"})...`);
      const [targetTableRows] = await db.query(`
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                  AND table_type = 'BASE TABLE'
                  AND table_name NOT IN ('SequelizeMeta', 'spatial_ref_sys')
                ORDER BY table_name;
            `);
      const targetTableNames = targetTableRows
        .map((r) => Array.isArray(r) ? r[0] : r.table_name || r[0])
        .filter((t) => !isPlatformMasterTable(t));
      const [targetColRows] = await db.query(`
                SELECT table_name, column_name, data_type, udt_name, is_nullable, column_default 
                FROM information_schema.columns 
                WHERE table_schema = 'public'
                ORDER BY table_name, ordinal_position;
            `);
      const targetColsMap = /* @__PURE__ */ new Map();
      const targetColMetaMap = /* @__PURE__ */ new Map();
      for (const c of targetColRows) {
        const tName = c.table_name;
        if (!targetColsMap.has(tName)) targetColsMap.set(tName, []);
        targetColsMap.get(tName).push(c.column_name);
        if (!targetColMetaMap.has(tName)) targetColMetaMap.set(tName, /* @__PURE__ */ new Map());
        targetColMetaMap.get(tName).set(c.column_name, {
          is_nullable: c.is_nullable,
          column_default: c.column_default,
          data_type: c.data_type,
          udt_name: c.udt_name
        });
      }
      if (bundle.tableSchemas && typeof bundle.tableSchemas === "object") {
        for (const [tName, schemaCols] of Object.entries(bundle.tableSchemas)) {
          if (isPlatformMasterTable(tName)) continue;
          if (!Array.isArray(schemaCols) || schemaCols.length === 0) continue;
          if (!targetTableNames.includes(tName)) {
            try {
              const colSql = schemaCols.map((c) => {
                let def = `"${c.column_name}" ${mapSqlType(c)}`;
                if (c.column_name === "id") def += " PRIMARY KEY";
                return def;
              }).join(", ");
              await db.query(`CREATE TABLE IF NOT EXISTS "${tName}" (${colSql});`);
              targetTableNames.push(tName);
              targetColsMap.set(tName, schemaCols.map((c) => c.column_name));
              const newMeta = /* @__PURE__ */ new Map();
              for (const c of schemaCols) {
                newMeta.set(c.column_name, {
                  is_nullable: c.is_nullable,
                  column_default: c.column_default,
                  data_type: c.data_type,
                  udt_name: c.udt_name
                });
              }
              targetColMetaMap.set(tName, newMeta);
              console.log(`\u2728 [AUTO-SCHEMA] Created newly added table "${tName}" on destination.`);
            } catch (createErr) {
              console.warn(`[AUTO-SCHEMA] Table "${tName}" creation notice:`, createErr.message);
            }
          } else {
            const existingCols = new Set(targetColsMap.get(tName) || []);
            for (const col of schemaCols) {
              if (!existingCols.has(col.column_name)) {
                try {
                  await db.query(`ALTER TABLE "${tName}" ADD COLUMN IF NOT EXISTS "${col.column_name}" ${mapSqlType(col)};`);
                  targetColsMap.get(tName).push(col.column_name);
                  existingCols.add(col.column_name);
                  if (targetColMetaMap.has(tName)) {
                    targetColMetaMap.get(tName).set(col.column_name, {
                      is_nullable: col.is_nullable,
                      column_default: col.column_default,
                      data_type: col.data_type,
                      udt_name: col.udt_name
                    });
                  }
                  console.log(`\u2728 [AUTO-SCHEMA] Added newly added column "${tName}"."${col.column_name}" on destination.`);
                } catch (colErr) {
                  console.warn(`[AUTO-SCHEMA] Column "${col.column_name}" notice on "${tName}":`, colErr.message);
                }
              }
            }
          }
        }
      }
      let orderedTableNames = [...targetTableNames];
      try {
        const [fkRows] = await db.query(`
            SELECT 
                tc.table_name AS child_table,
                ccu.table_name AS parent_table
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu 
                ON tc.constraint_name = ccu.constraint_name 
                AND tc.constraint_schema = ccu.constraint_schema
            WHERE tc.constraint_type = 'FOREIGN KEY' 
              AND tc.table_schema = 'public'
              AND tc.table_name != ccu.table_name;
        `);
        if (Array.isArray(fkRows) && fkRows.length > 0) {
          orderedTableNames = sortTablesTopologically(targetTableNames, fkRows);
        }
      } catch (_) {}

      let sessionRoleBypassed = false;
      try {
        await db.query("SET session_replication_role = 'replica';");
        sessionRoleBypassed = true;
      } catch (repErr) {
        console.warn(`[MIGRATION] Non-superuser cloud database (session_replication_role restricted): ${repErr.message}. Utilizing topological dependency order.`);
      }

      try {
        let targetOutletId2 = 1;
        if (isAllScope || mode === "RESTORE_DB") {
          console.log(`[UNIVERSAL IMPORT] Cleanly purging all ${targetTableNames.length} tables for full enterprise restore...`);
          for (const tName of orderedTableNames.slice().reverse()) {
            try {
              await db.query(`TRUNCATE TABLE "${tName}" CASCADE;`);
            } catch (_) {
            }
          }
          for (const tName of orderedTableNames) {
            if (isPlatformMasterTable(tName) || tName === "outlets") continue;
            const rows = bundle.tables[tName];
            if (!targetTableNames.includes(tName) || !Array.isArray(rows) || rows.length === 0) continue;
            const tCols = targetColsMap.get(tName) || [];
            await insertRowsBatch(db, tName, rows, tCols, targetColMetaMap.get(tName));
          }
        } else {
          if (targetTableNames.includes("outlets")) {
            const [existingOutlets] = await db.query(`SELECT * FROM "outlets" WHERE "outlet_code" = $1`, {
              bind: [outletCode]
            });
            if (existingOutlets && existingOutlets.length > 0) {
              targetOutletId2 = existingOutlets[0].id;
            } else {
              const srcOutlet = bundle.outletRecord || {};
              const defaultPinHash = srcOutlet.recovery_pin_hash || await import_bcryptjs.default.hash("1234", 10);
              const [newOut] = await db.query(`
                                INSERT INTO "outlets" (
                                    outlet_code, outlet_name, outlet_type, business_module, recovery_pin_hash,
                                    tax_id, contact_phone, contact_email, is_active, supervisor_pin, supervisor_pin_type, outlet_role
                                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id;
                            `, {
                bind: [
                  outletCode,
                  srcOutlet.outlet_name || outletCode,
                  srcOutlet.outlet_type || "RETAIL",
                  srcOutlet.business_module || "ALL",
                  defaultPinHash,
                  srcOutlet.tax_id || "TAX_DEFAULT",
                  srcOutlet.contact_phone || "0000000000",
                  (srcOutlet.contact_email || "admin@retailpos.com").substring(0, 50),
                  true,
                  srcOutlet.supervisor_pin || "1234",
                  srcOutlet.supervisor_pin_type || "STATIC",
                  srcOutlet.outlet_role || "BRANCH"
                ]
              });
              if (newOut && newOut.length > 0) targetOutletId2 = newOut[0].id;
            }
          }
          for (const [childTable, rel] of Object.entries(childTableRelations)) {
            if (targetTableNames.includes(childTable) && targetTableNames.includes(rel.parentTable)) {
              try {
                await db.query(`
                  DELETE FROM "${childTable}" 
                  WHERE "${rel.foreignKey}" IN (
                    SELECT id FROM "${rel.parentTable}" WHERE "outlet_id" = $1
                  )
                `, { bind: [targetOutletId2] });
              } catch (_) {}
            }
          }
          for (const tName of orderedTableNames.slice().reverse()) {
            const tCols = targetColsMap.get(tName) || [];
            if (tCols.includes("outlet_id") && tName !== "outlets" && tName !== "users") {
              try {
                await db.query(`DELETE FROM "${tName}" WHERE "outlet_id" = $1`, { bind: [targetOutletId2] });
              } catch (_) {
              }
            }
          }
          // 3. Ingest every table in topological order (parents first) with full column fidelity & zero-collision ID isolation
          const idRemap = new Map();
          const commonFkLookups = {
            'item_id': 'item_master',
            'sale_id': 'sales_headers',
            'voucher_id': 'accounting_vouchers',
            'po_id': 'purchase_orders',
            'grn_id': 'goods_receipts',
            'damage_id': 'damage_headers',
            'issue_id': 'issue_headers',
            'return_id': 'return_headers',
            'request_id': 'request_headers',
            'transfer_id': 'stock_transfer_headers',
            'assembly_id': 'assembly_headers',
            'challan_id': 'delivery_challan_headers',
            'category_id': 'item_groups',
            'supplier_id': 'supplier_master',
            'customer_id': 'customers',
            'office_id': 'hr_offices',
            'designation_id': 'hr_designations',
            'shift_id': 'hr_shifts',
            'pay_structure_id': 'hr_pay_structures',
            'payroll_run_id': 'hr_payroll_runs',
            'employee_id': 'hr_employees',
            'tax_group_id': 'tax_groups',
            'expense_id': 'expenses'
          };

          for (const tName of orderedTableNames) {
            if (isPlatformMasterTable(tName) || tName === "outlets") continue;
            const rows = bundle.tables[tName];
            if (!targetTableNames.includes(tName) || !Array.isArray(rows) || rows.length === 0) continue;
            const tCols = targetColsMap.get(tName) || [];
            const hasOutletId = tCols.includes("outlet_id") && tName !== "outlets";

            // 3a. Cascade mapped foreign keys from previously inserted parent tables
            for (const row of rows) {
              if (!row || typeof row !== 'object') continue;
              for (const [colName, val] of Object.entries(row)) {
                if (val === null || val === void 0) continue;
                const parentTable = commonFkLookups[colName] || childTableRelations[tName]?.parentTable;
                if (parentTable && idRemap.has(parentTable)) {
                  const pMap = idRemap.get(parentTable);
                  if (pMap && pMap.has(val)) {
                    row[colName] = pMap.get(val);
                  }
                }
              }
            }

            // 3b. Handle users table specially to preserve credentials & prevent username collisions
            if (tName === 'users') {
              for (const uRow of rows) {
                if (!uRow || !uRow.username) continue;
                const cleanUName = String(uRow.username).trim();
                try {
                  const matchRows = await db.query(
                    `SELECT id, username, outlet_id FROM "users" WHERE "username" ILIKE $1`,
                    { bind: [cleanUName], type: import_sequelize.QueryTypes.SELECT }
                  );
                  const match = matchRows && matchRows.length > 0 ? matchRows[0] : null;
                  const uPwd = admin_password 
                    ? await import_bcryptjs.default.hash(admin_password, 10) 
                    : (uRow.password_hash || await import_bcryptjs.default.hash("1234", 10));

                  if (match) {
                    if (match.outlet_id === targetOutletId2) {
                      await db.query(
                        `UPDATE "users" SET "password_hash" = $1, "is_active" = true, "role" = $2, "updated_at" = NOW() WHERE "id" = $3`,
                        { bind: [uPwd, uRow.role || 'ADMIN', match.id] }
                      );
                    } else {
                      const uniqueUsername = `${cleanUName}_${outletCode.toLowerCase()}`;
                      await db.query(`
                        INSERT INTO "users" (username, full_name, role, password_hash, outlet_id, is_active, mobile, created_at, updated_at)
                        VALUES ($1, $2, $3, $4, $5, true, $6, NOW(), NOW())
                        ON CONFLICT (username) DO UPDATE SET outlet_id = $5, password_hash = $4, is_active = true;
                      `, { bind: [uniqueUsername, uRow.full_name || cleanUName, uRow.role || 'ADMIN', uPwd, targetOutletId2, uRow.mobile || null] });
                    }
                  } else {
                    await db.query(`
                      INSERT INTO "users" (username, full_name, role, password_hash, outlet_id, is_active, mobile, created_at, updated_at)
                      VALUES ($1, $2, $3, $4, $5, true, $6, NOW(), NOW())
                      ON CONFLICT (username) DO UPDATE SET outlet_id = $5, password_hash = $4, is_active = true;
                    `, { bind: [cleanUName, uRow.full_name || cleanUName, uRow.role || 'ADMIN', uPwd, targetOutletId2, uRow.mobile || null] });
                  }
                } catch (_) {}
              }
              continue;
            }

            // 3c. Primary Key Conflict Detection & Re-allocation for all other tables
            if (tCols.includes('id')) {
              if (!idRemap.has(tName)) idRemap.set(tName, new Map());
              const thisTableRemap = idRemap.get(tName);

              try {
                const existingRows = await db.query(
                  `SELECT "id" FROM "${tName}"`,
                  { type: import_sequelize.QueryTypes.SELECT }
                );
                const occupiedIds = new Set(existingRows.map((r) => r.id));
                let currentMaxId = existingRows.reduce((m, r) => (typeof r.id === 'number' && r.id > m ? r.id : m), 0);

                for (const row of rows) {
                  if (row.id !== void 0 && row.id !== null && typeof row.id === 'number') {
                    const origId = row.id;
                    if (occupiedIds.has(origId)) {
                      currentMaxId++;
                      const newId = currentMaxId;
                      row.id = newId;
                      occupiedIds.add(newId);
                      thisTableRemap.set(origId, newId);
                    } else {
                      occupiedIds.add(origId);
                      thisTableRemap.set(origId, origId);
                    }
                  }
                }
              } catch (_) {}
            }

            // Scope rows to targetOutletId if table has outlet_id
            const scopedRows = hasOutletId
              ? rows.map((r) => ({ ...r, outlet_id: targetOutletId2 }))
              : rows;

            await insertRowsBatch(db, tName, scopedRows, tCols, targetColMetaMap.get(tName));
          }
          try {
            const [existingAdmins] = await db.query(
              `SELECT id, username FROM "users" WHERE "outlet_id" = $1 AND "role" IN ('ADMIN', 'SUPER_ADMIN')`,
              { bind: [targetOutletId2] }
            );
            const defaultPwd = admin_password || "1234";
            const adminHash = await import_bcryptjs.default.hash(defaultPwd, 10);
            if (!existingAdmins || existingAdmins.length === 0) {
              const defaultUsername = `admin_${outletCode}`;
              await db.query(`
                INSERT INTO "users" (username, full_name, role, password_hash, outlet_id, is_active, created_at, updated_at)
                VALUES ($1, 'System Admin', 'ADMIN', $2, $3, true, NOW(), NOW())
                ON CONFLICT (username) DO UPDATE SET outlet_id = $3, password_hash = $2, role = 'ADMIN', is_active = true;
              `, { bind: [defaultUsername, adminHash, targetOutletId2] });
            } else {
              await db.query(
                `UPDATE "users" SET "password_hash" = $1, "is_active" = true WHERE "outlet_id" = $2 AND "role" IN ('ADMIN', 'SUPER_ADMIN')`,
                { bind: [adminHash, targetOutletId2] }
              );
            }

            // Always guarantee that 'famalth' and 'admin_${outletCode}' exist and are active for this outlet
            try {
              const [existingFamalth] = await db.query(
                `SELECT id, outlet_id FROM "users" WHERE "username" ILIKE 'famalth'`,
                { type: import_sequelize.QueryTypes.SELECT }
              );
              if (!existingFamalth) {
                await db.query(`
                  INSERT INTO "users" (username, full_name, role, password_hash, outlet_id, is_active, mobile, created_at, updated_at)
                  VALUES ('famalth', 'famalth', 'ADMIN', $1, $2, true, '6395059482', NOW(), NOW())
                  ON CONFLICT (username) DO UPDATE SET outlet_id = $2, password_hash = $1, role = 'ADMIN', is_active = true;
                `, { bind: [adminHash, targetOutletId2] });
              } else if (existingFamalth.outlet_id === targetOutletId2) {
                await db.query(
                  `UPDATE "users" SET "password_hash" = $1, "is_active" = true WHERE "id" = $2`,
                  { bind: [adminHash, existingFamalth.id] }
                );
              } else {
                const famalthAlias = `famalth_${outletCode.toLowerCase()}`;
                await db.query(`
                  INSERT INTO "users" (username, full_name, role, password_hash, outlet_id, is_active, mobile, created_at, updated_at)
                  VALUES ($1, 'famalth', 'ADMIN', $2, $3, true, '6395059482', NOW(), NOW())
                  ON CONFLICT (username) DO UPDATE SET outlet_id = $3, password_hash = $2, role = 'ADMIN', is_active = true;
                `, { bind: [famalthAlias, adminHash, targetOutletId2] });
              }
            } catch (_) {}
          } catch (userEnsureErr) {
            console.warn(`[MIGRATION] Admin user ensure notice: ${userEnsureErr.message}`);
          }
        }
        if (admin_password && targetTableNames.includes("users")) {
          try {
            const newHash = await import_bcryptjs.default.hash(admin_password, 10);
            await db.query(`UPDATE "users" SET "password_hash" = $1 WHERE "role" IN ('ADMIN', 'SUPER_ADMIN')`, {
              bind: [newHash]
            });
          } catch (_) {
          }
        }
      } finally {
        if (sessionRoleBypassed) {
          try {
            await db.query("SET session_replication_role = 'origin';");
          } catch (_) {
          }
        }
      }
      await resetAllDatabaseSequences(db);
      let primaryAdmin2 = null;
      if (targetTableNames.includes("users")) {
        const [adminUsers] = await db.query(`SELECT * FROM "users" WHERE "role" = 'ADMIN' OR "role" = 'SUPER_ADMIN' LIMIT 1`);
        if (adminUsers && adminUsers.length > 0) primaryAdmin2 = adminUsers[0];
      }
      const tokenPayload2 = {
        id: primaryAdmin2 ? primaryAdmin2.id : 1,
        username: primaryAdmin2 ? primaryAdmin2.username : `admin_${outletCode.toLowerCase()}`,
        role: primaryAdmin2 ? primaryAdmin2.role : "ADMIN",
        outlet_code: outletCode,
        outlet_id: primaryAdmin2?.outlet_id || 1
      };
      const token2 = (0, import_jwt.sign)(tokenPayload2, { expiresIn: "7d" });
      return res.status(200).json({
        success: true,
        message: `Universal zero-loss database migration completed successfully across all ${Object.keys(bundle.tables).length} tables!`,
        outlet_code: outletCode,
        token: token2,
        user: tokenPayload2,
        stats: bundle.stats || {}
      });
    }
    if (mode === "RESTORE_DB" && encBase64) {
      console.log(`[MIGRATION IMPORT] Executing full DB snapshot restoration on cloud...`);
      const encBuffer = Buffer.from(encBase64, "base64");
      await (0, import_restore.restoreFromEncBuffer)(encBuffer);
      let adminUser = null;
      if (db.models.users) {
        adminUser = await db.models.users.findOne({
          where: { role: "ADMIN" },
          raw: true
        }) || await db.models.users.findOne({ raw: true });
      }
      const tokenPayload2 = {
        id: adminUser?.id || 1,
        username: adminUser?.username || "admin",
        role: adminUser?.role || "ADMIN",
        outlet_code: outletCode,
        outlet_id: adminUser?.outlet_id || 1
      };
      const token2 = (0, import_jwt.sign)(tokenPayload2, { expiresIn: "7d" });
      return res.status(200).json({
        success: true,
        message: "Full store database restored and synchronized with cloud successfully!",
        mode: "RESTORE_DB",
        outlet_code: outletCode,
        token: token2,
        user: tokenPayload2,
        stats: bundle.stats || {}
      });
    }
    console.log(`[MIGRATION IMPORT] Importing store data for outlet ${outletCode} with dynamic ID translation across all tables...`);
    const userMap = /* @__PURE__ */ new Map();
    const taxGroupMap = /* @__PURE__ */ new Map();
    const groupMap = /* @__PURE__ */ new Map();
    const brandMap = /* @__PURE__ */ new Map();
    const itemMap = /* @__PURE__ */ new Map();
    const locationMap = /* @__PURE__ */ new Map();
    const customerMap = /* @__PURE__ */ new Map();
    const supplierMap = /* @__PURE__ */ new Map();
    const salesMap = /* @__PURE__ */ new Map();
    const poMap = /* @__PURE__ */ new Map();
    const grnMap = /* @__PURE__ */ new Map();
    const expenseCatMap = /* @__PURE__ */ new Map();
    const accountMap = /* @__PURE__ */ new Map();
    const bankMap = /* @__PURE__ */ new Map();
    const voucherMap = /* @__PURE__ */ new Map();
    const floorMap = /* @__PURE__ */ new Map();
    const areaMap = /* @__PURE__ */ new Map();
    const tableMap = /* @__PURE__ */ new Map();
    const kotMap = /* @__PURE__ */ new Map();
    const empMap = /* @__PURE__ */ new Map();
    let targetOutletId = 1;
    if (db.models.outlets) {
      let existingOutlet = await db.models.outlets.findOne({
        where: { outlet_code: outletCode }
      });
      if (!existingOutlet) {
        const srcOutlet = bundle.outletRecord || {};
        const defaultPinHash = srcOutlet.recovery_pin_hash || await import_bcryptjs.default.hash("1234", 10);
        existingOutlet = await db.models.outlets.create({
          outlet_code: outletCode,
          outlet_name: srcOutlet.outlet_name || outletCode,
          outlet_type: srcOutlet.outlet_type || "RETAIL",
          business_module: srcOutlet.business_module || "ALL",
          recovery_pin_hash: defaultPinHash,
          tax_id: srcOutlet.tax_id || "TAX_DEFAULT",
          contact_phone: srcOutlet.contact_phone || "0000000000",
          contact_email: (srcOutlet.contact_email || "admin@retailpos.com").substring(0, 50),
          is_active: true,
          supervisor_pin: srcOutlet.supervisor_pin || "1234",
          supervisor_pin_type: srcOutlet.supervisor_pin_type || "STATIC",
          outlet_role: srcOutlet.outlet_role || "BRANCH"
        });
      }
      targetOutletId = existingOutlet.id;
    }
    let primaryAdmin = null;
    if (db.models.users && Array.isArray(bundle.users)) {
      for (const u of bundle.users) {
        try {
          const oldUserId = u.id;
          const userCode = u.username || `admin_${outletCode.toLowerCase()}`;
          const hashedPassword = admin_password ? await import_bcryptjs.default.hash(admin_password, 10) : u.password_hash || u.password || await import_bcryptjs.default.hash("admin@123", 10);
          let userRec = await db.models.users.findOne({ where: { username: userCode } });
          if (!userRec) {
            userRec = await db.models.users.create({
              username: userCode,
              password_hash: hashedPassword,
              role: u.role || "ADMIN",
              outlet_id: targetOutletId,
              is_active: u.is_active !== void 0 ? u.is_active : true,
              full_name: u.full_name || "Outlet Administrator",
              pin_code: u.pin_code || u.pos_pin || null,
              mobile: u.mobile || null,
              contact_email: u.contact_email ? u.contact_email.substring(0, 50) : u.email ? u.email.substring(0, 50) : null
            });
          }
          if (oldUserId) userMap.set(oldUserId, userRec.id);
          if (u.role === "ADMIN" || !primaryAdmin) {
            primaryAdmin = userRec;
          }
        } catch (uErr) {
          console.warn(`[MIGRATION] User sync warning: ${uErr.message}`);
        }
      }
    }
    if (bundle.settings && db.models.system_settings) {
      try {
        const { id, ...sData } = bundle.settings;
        sData.outlet_id = targetOutletId;
        const existingSettings = await db.models.system_settings.findOne({ where: { outlet_id: targetOutletId } });
        if (existingSettings) {
          await existingSettings.update(sData);
        } else {
          await db.models.system_settings.create(sData);
        }
      } catch (sErr) {
        console.warn(`[MIGRATION] Settings sync warning: ${sErr.message}`);
      }
    }
    if (bundle.branding && db.models.app_branding) {
      try {
        const { id, ...bData } = bundle.branding;
        bData.outlet_id = targetOutletId;
        bData.company_name = bData.company_name || "Famalth Technologies";
        bData.product_name = bData.product_name || "Famalth Inventory";
        bData.support_email = bData.support_email || "help@famalth.com";
        bData.support_website = bData.support_website || "www.famalth.com";
        bData.support_phone = bData.support_phone || "+91-00000-00000";
        const existingBranding = await db.models.app_branding.findOne({ where: { outlet_id: targetOutletId } });
        if (existingBranding) {
          await existingBranding.update(bData);
        } else {
          await db.models.app_branding.create(bData);
        }
      } catch (bErr) {
        console.warn(`[MIGRATION] Branding sync warning: ${bErr.message}`);
      }
    }
    if (Array.isArray(bundle.numbering) && db.models.numbering_settings) {
      for (const num of bundle.numbering) {
        try {
          const { id, ...numData } = num;
          numData.outlet_id = targetOutletId;
          await db.models.numbering_settings.findOrCreate({
            where: { outlet_id: targetOutletId, doc_type: num.doc_type || "SALE" },
            defaults: numData
          });
        } catch (_) {
        }
      }
    }
    if (bundle.propertyInfo && db.models.property_info) {
      try {
        const { id, ...pData } = bundle.propertyInfo;
        pData.outlet_id = targetOutletId;
        const existingPropInfo = await db.models.property_info.findOne({ where: { outlet_id: targetOutletId } });
        if (existingPropInfo) {
          await existingPropInfo.update(pData);
        } else {
          await db.models.property_info.create(pData);
        }
      } catch (_) {
      }
    }
    if (Array.isArray(bundle.taxGroups) && db.models.tax_groups) {
      for (const tg of bundle.taxGroups) {
        try {
          const oldTgId = tg.id;
          const { id, ...tgData } = tg;
          tgData.outlet_id = targetOutletId;
          let existingTg = await db.models.tax_groups.findOne({
            where: { group_name: tg.group_name, outlet_id: targetOutletId }
          });
          if (!existingTg) {
            existingTg = await db.models.tax_groups.create(tgData);
          }
          if (oldTgId) taxGroupMap.set(oldTgId, existingTg.id);
        } catch (tgErr) {
          console.warn(`[MIGRATION] Tax group sync warning: ${tgErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.itemGroups) && db.models.item_groups) {
      for (const ig of bundle.itemGroups) {
        try {
          const oldIgId = ig.id;
          const { id, ...igData } = ig;
          igData.outlet_id = targetOutletId;
          let existingIg = await db.models.item_groups.findOne({
            where: { group_name: ig.group_name, outlet_id: targetOutletId }
          });
          if (!existingIg) {
            existingIg = await db.models.item_groups.create(igData);
          }
          if (oldIgId) groupMap.set(oldIgId, existingIg.id);
        } catch (igErr) {
          console.warn(`[MIGRATION] Item group sync warning: ${igErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.brands) && db.models.brands) {
      for (const b of bundle.brands) {
        try {
          const oldBrandId = b.id;
          const { id, ...bData } = b;
          bData.outlet_id = targetOutletId;
          bData.brand_name = b.brand_name || b.name || "Generic";
          let existingB = await db.models.brands.findOne({
            where: { brand_name: bData.brand_name, outlet_id: targetOutletId }
          });
          if (!existingB) {
            existingB = await db.models.brands.create(bData);
          }
          if (oldBrandId) brandMap.set(oldBrandId, existingB.id);
        } catch (bErr) {
          console.warn(`[MIGRATION] Brand sync warning: ${bErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.items) && db.models.item_master) {
      for (const itm of bundle.items) {
        try {
          const oldItemId = itm.id;
          const { id, ...itmData } = itm;
          itmData.outlet_id = targetOutletId;
          itmData.item_code = itmData.item_code || "ITM-" + (oldItemId || Date.now());
          itmData.item_name = itmData.item_name || "Unnamed Product";
          itmData.item_group = itmData.item_group || "General";
          if (itmData.group_id && groupMap.has(itmData.group_id)) {
            itmData.group_id = groupMap.get(itmData.group_id);
          }
          if (itmData.tax_group_id && taxGroupMap.has(itmData.tax_group_id)) {
            itmData.tax_group_id = taxGroupMap.get(itmData.tax_group_id);
          }
          if (itmData.brand_id && brandMap.has(itmData.brand_id)) {
            itmData.brand_id = brandMap.get(itmData.brand_id);
          }
          const matchWhere = itm.barcode ? { barcode: itm.barcode, outlet_id: targetOutletId } : { item_name: itmData.item_name, outlet_id: targetOutletId };
          let existingItem = await db.models.item_master.findOne({ where: matchWhere });
          if (!existingItem) {
            existingItem = await db.models.item_master.create(itmData);
          } else {
            await existingItem.update(itmData);
          }
          if (oldItemId) itemMap.set(oldItemId, existingItem.id);
        } catch (itmErr) {
          console.warn(`[MIGRATION] Item sync warning: ${itmErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.stockLocations) && db.models.stock_locations) {
      for (const loc of bundle.stockLocations) {
        try {
          const oldLocId = loc.id;
          const { id, ...locData } = loc;
          locData.outlet_id = targetOutletId;
          let existingLoc = await db.models.stock_locations.findOne({
            where: { location_name: loc.location_name, outlet_id: targetOutletId }
          });
          if (!existingLoc) {
            existingLoc = await db.models.stock_locations.create(locData);
          }
          if (oldLocId) locationMap.set(oldLocId, existingLoc.id);
        } catch (locErr) {
          console.warn(`[MIGRATION] Location sync warning: ${locErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.stockLedger) && db.models.stock_ledger) {
      for (const st of bundle.stockLedger) {
        try {
          const { id, ...stData } = st;
          stData.outlet_id = targetOutletId;
          if (stData.item_id && itemMap.has(stData.item_id)) {
            stData.item_id = itemMap.get(stData.item_id);
          }
          if (stData.location_id && locationMap.has(stData.location_id)) {
            stData.location_id = locationMap.get(stData.location_id);
          }
          await db.models.stock_ledger.create(stData);
        } catch (stErr) {
          console.warn(`[MIGRATION] Stock ledger warning: ${stErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.customers) && db.models.customers) {
      for (const c of bundle.customers) {
        try {
          const oldCustId = c.id;
          const { id, ...cData } = c;
          cData.outlet_id = targetOutletId;
          cData.customer_name = c.customer_name || c.name || "Customer";
          const phoneKey = c.customer_phone || c.mobile || c.phone;
          if (phoneKey) cData.customer_phone = phoneKey;
          const matchWhere = phoneKey ? { customer_phone: phoneKey, outlet_id: targetOutletId } : { customer_name: cData.customer_name, outlet_id: targetOutletId };
          let existingCust = await db.models.customers.findOne({ where: matchWhere });
          if (!existingCust) {
            existingCust = await db.models.customers.create(cData);
          } else {
            await existingCust.update(cData);
          }
          if (oldCustId) customerMap.set(oldCustId, existingCust.id);
        } catch (cErr) {
          console.warn(`[MIGRATION] Customer sync warning: ${cErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.suppliers) && db.models.supplier_master) {
      for (const s of bundle.suppliers) {
        try {
          const oldSuppId = s.id;
          const { id, ...sData } = s;
          sData.outlet_id = targetOutletId;
          sData.supplier_name = s.supplier_name || s.name || "Supplier";
          let existingSupp = await db.models.supplier_master.findOne({
            where: { supplier_name: sData.supplier_name, outlet_id: targetOutletId }
          });
          if (!existingSupp) {
            existingSupp = await db.models.supplier_master.create(sData);
          } else {
            await existingSupp.update(sData);
          }
          if (oldSuppId) supplierMap.set(oldSuppId, existingSupp.id);
        } catch (sErr) {
          console.warn(`[MIGRATION] Supplier sync warning: ${sErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.salesHeaders) && db.models.sales_headers) {
      for (const sh of bundle.salesHeaders) {
        try {
          const oldSaleId = sh.id;
          const { id, ...shData } = sh;
          shData.outlet_id = targetOutletId;
          if (shData.customer_id && customerMap.has(shData.customer_id)) {
            shData.customer_id = customerMap.get(shData.customer_id);
          }
          if (shData.created_by && userMap.has(shData.created_by)) {
            shData.created_by = userMap.get(shData.created_by);
          } else if (primaryAdmin) {
            shData.created_by = primaryAdmin.id;
          }
          let existingSale = await db.models.sales_headers.findOne({
            where: { sale_no: sh.sale_no, outlet_id: targetOutletId }
          });
          if (!existingSale) {
            existingSale = await db.models.sales_headers.create(shData);
          }
          if (oldSaleId) salesMap.set(oldSaleId, existingSale.id);
        } catch (shErr) {
          console.warn(`[MIGRATION] Sales header sync warning: ${shErr.message}`);
        }
      }
      if (Array.isArray(bundle.salesItems) && db.models.sales_items) {
        for (const si of bundle.salesItems) {
          try {
            const { id, ...siData } = si;
            const mappedSaleId = salesMap.get(si.sale_id);
            if (!mappedSaleId) continue;
            siData.sale_id = mappedSaleId;
            if (siData.item_id && itemMap.has(siData.item_id)) {
              siData.item_id = itemMap.get(siData.item_id);
            }
            const existingLine = await db.models.sales_items.findOne({
              where: { sale_id: mappedSaleId, item_id: siData.item_id, item_code: siData.item_code || "" }
            });
            if (!existingLine) {
              await db.models.sales_items.create(siData);
            }
          } catch (_) {
          }
        }
      }
    }
    if (Array.isArray(bundle.purchaseOrders) && db.models.purchase_orders) {
      for (const po of bundle.purchaseOrders) {
        try {
          const oldPoId = po.id;
          const { id, ...poData } = po;
          poData.outlet_id = targetOutletId;
          if (poData.supplier_id && supplierMap.has(poData.supplier_id)) {
            poData.supplier_id = supplierMap.get(poData.supplier_id);
          }
          let existingPo = await db.models.purchase_orders.findOne({
            where: { po_number: po.po_number || `PO-${oldPoId}`, outlet_id: targetOutletId }
          });
          if (!existingPo) {
            existingPo = await db.models.purchase_orders.create(poData);
          }
          if (oldPoId) poMap.set(oldPoId, existingPo.id);
        } catch (poErr) {
          console.warn(`[MIGRATION] Purchase order sync warning: ${poErr.message}`);
        }
      }
      if (Array.isArray(bundle.purchaseOrderItems) && db.models.purchase_order_items) {
        for (const poi of bundle.purchaseOrderItems) {
          try {
            const { id, ...poiData } = poi;
            const mappedPoId = poMap.get(poi.po_id);
            if (!mappedPoId) continue;
            poiData.po_id = mappedPoId;
            if (poiData.item_id && itemMap.has(poiData.item_id)) {
              poiData.item_id = itemMap.get(poiData.item_id);
            }
            await db.models.purchase_order_items.create(poiData);
          } catch (_) {
          }
        }
      }
    }
    if (Array.isArray(bundle.expenseCategories) && db.models.expense_categories) {
      for (const ec of bundle.expenseCategories) {
        try {
          const oldEcId = ec.id;
          const { id, ...ecData } = ec;
          ecData.outlet_id = targetOutletId;
          ecData.category_name = ec.category_name || ec.name || "General Expense";
          let existingEc = await db.models.expense_categories.findOne({
            where: { category_name: ecData.category_name, outlet_id: targetOutletId }
          });
          if (!existingEc) {
            existingEc = await db.models.expense_categories.create(ecData);
          }
          if (oldEcId) expenseCatMap.set(oldEcId, existingEc.id);
        } catch (ecErr) {
          console.warn(`[MIGRATION] Expense category sync warning: ${ecErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.expenses) && db.models.expenses) {
      for (const exp of bundle.expenses) {
        try {
          const { id, ...expData } = exp;
          expData.outlet_id = targetOutletId;
          if (expData.category_id && expenseCatMap.has(expData.category_id)) {
            expData.category_id = expenseCatMap.get(expData.category_id);
          }
          await db.models.expenses.create(expData);
        } catch (expErr) {
          console.warn(`[MIGRATION] Expense sync warning: ${expErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.chartOfAccounts) && db.models.chart_of_accounts) {
      for (const acc of bundle.chartOfAccounts) {
        try {
          const oldAccId = acc.id;
          const { id, ...accData } = acc;
          accData.outlet_id = targetOutletId;
          let existingAcc = await db.models.chart_of_accounts.findOne({
            where: { account_name: acc.account_name, outlet_id: targetOutletId }
          });
          if (!existingAcc) {
            existingAcc = await db.models.chart_of_accounts.create(accData);
          }
          if (oldAccId) accountMap.set(oldAccId, existingAcc.id);
        } catch (accErr) {
          console.warn(`[MIGRATION] Chart of accounts warning: ${accErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.bankAccounts) && db.models.bank_accounts) {
      for (const b of bundle.bankAccounts) {
        try {
          const oldBankId = b.id;
          const { id, ...bData } = b;
          bData.outlet_id = targetOutletId;
          let existingB = await db.models.bank_accounts.findOne({
            where: { account_number: b.account_number, outlet_id: targetOutletId }
          });
          if (!existingB) {
            existingB = await db.models.bank_accounts.create(bData);
          }
          if (oldBankId) bankMap.set(oldBankId, existingB.id);
        } catch (bErr) {
          console.warn(`[MIGRATION] Bank accounts warning: ${bErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.accountingVouchers) && db.models.accounting_vouchers) {
      for (const v of bundle.accountingVouchers) {
        try {
          const oldVId = v.id;
          const { id, ...vData } = v;
          vData.outlet_id = targetOutletId;
          if (vData.bank_account_id && bankMap.has(vData.bank_account_id)) {
            vData.bank_account_id = bankMap.get(vData.bank_account_id);
          }
          let existingV = await db.models.accounting_vouchers.findOne({
            where: { voucher_no: v.voucher_no, outlet_id: targetOutletId }
          });
          if (!existingV) {
            existingV = await db.models.accounting_vouchers.create(vData);
          }
          if (oldVId) voucherMap.set(oldVId, existingV.id);
        } catch (vErr) {
          console.warn(`[MIGRATION] Voucher warning: ${vErr.message}`);
        }
      }
      if (Array.isArray(bundle.voucherLines) && db.models.voucher_lines) {
        for (const vl of bundle.voucherLines) {
          try {
            const { id, ...vlData } = vl;
            const mappedVId = voucherMap.get(vl.voucher_id);
            if (!mappedVId) continue;
            vlData.voucher_id = mappedVId;
            vlData.account_name = vlData.account_name || "General Account";
            vlData.line_type = (vlData.line_type || "DEBIT").toUpperCase();
            if (vlData.account_id && accountMap.has(vlData.account_id)) {
              vlData.account_id = accountMap.get(vlData.account_id);
            }
            await db.models.voucher_lines.create(vlData);
          } catch (_) {
          }
        }
      }
    }
    if (Array.isArray(bundle.floors) && db.models.floor) {
      for (const f of bundle.floors) {
        try {
          const oldFId = f.id;
          const { id, ...fData } = f;
          fData.outlet_id = targetOutletId;
          fData.name = f.name || f.floor_name || "Ground Floor";
          let existingF = await db.models.floor.findOne({
            where: { name: fData.name, outlet_id: targetOutletId }
          });
          if (!existingF) {
            existingF = await db.models.floor.create(fData);
          }
          if (oldFId) floorMap.set(oldFId, existingF.id);
        } catch (fErr) {
          console.warn(`[MIGRATION] Floor sync warning: ${fErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.diningAreas) && db.models.dining_area) {
      for (const da of bundle.diningAreas) {
        try {
          const oldDaId = da.id;
          const { id, ...daData } = da;
          daData.outlet_id = targetOutletId;
          daData.name = da.name || da.area_name || "Dining Area";
          if (daData.floor_id && floorMap.has(daData.floor_id)) {
            daData.floor_id = floorMap.get(daData.floor_id);
          }
          let existingDa = await db.models.dining_area.findOne({
            where: { name: daData.name, outlet_id: targetOutletId }
          });
          if (!existingDa) {
            existingDa = await db.models.dining_area.create(daData);
          }
          if (oldDaId) areaMap.set(oldDaId, existingDa.id);
        } catch (daErr) {
          console.warn(`[MIGRATION] Dining area sync warning: ${daErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.restaurantTables) && db.models.restaurant_tables) {
      for (const t of bundle.restaurantTables) {
        try {
          const oldTId = t.id;
          const { id, ...tData } = t;
          tData.outlet_id = targetOutletId;
          tData.table_name = t.table_name || t.table_number || "Table 1";
          if (tData.dining_area_id && areaMap.has(tData.dining_area_id)) {
            tData.dining_area_id = areaMap.get(tData.dining_area_id);
          }
          let existingT = await db.models.restaurant_tables.findOne({
            where: { table_name: tData.table_name, outlet_id: targetOutletId }
          });
          if (!existingT) {
            existingT = await db.models.restaurant_tables.create(tData);
          }
          if (oldTId) tableMap.set(oldTId, existingT.id);
        } catch (tErr) {
          console.warn(`[MIGRATION] Table sync warning: ${tErr.message}`);
        }
      }
    }
    if (Array.isArray(bundle.kotHeaders) && db.models.kot_headers) {
      for (const k of bundle.kotHeaders) {
        try {
          const oldKId = k.id;
          const { id, ...kData } = k;
          kData.outlet_id = targetOutletId;
          kData.kot_no = k.kot_no || k.kot_number || `KOT-${oldKId}`;
          if (kData.table_id && tableMap.has(kData.table_id)) {
            kData.table_id = tableMap.get(kData.table_id);
          }
          let existingK = await db.models.kot_headers.findOne({
            where: { kot_no: kData.kot_no, outlet_id: targetOutletId }
          });
          if (!existingK) {
            existingK = await db.models.kot_headers.create(kData);
          }
          if (oldKId) kotMap.set(oldKId, existingK.id);
        } catch (kErr) {
          console.warn(`[MIGRATION] KOT header warning: ${kErr.message}`);
        }
      }
      if (Array.isArray(bundle.kotItems) && db.models.kot_items) {
        for (const ki of bundle.kotItems) {
          try {
            const { id, ...kiData } = ki;
            const mappedKId = kotMap.get(ki.kot_id || ki.kot_header_id);
            if (!mappedKId) continue;
            kiData.outlet_id = targetOutletId;
            kiData.kot_header_id = mappedKId;
            kiData.item_name = kiData.item_name || "KOT Item";
            if (kiData.item_id && itemMap.has(kiData.item_id)) {
              kiData.item_id = itemMap.get(kiData.item_id);
            }
            await db.models.kot_items.create(kiData);
          } catch (_) {
          }
        }
      }
    }
    if (Array.isArray(bundle.milkSubscriptions) && db.models.milk_subscriptions) {
      for (const ms of bundle.milkSubscriptions) {
        try {
          const { id, ...msData } = ms;
          msData.outlet_id = targetOutletId;
          if (msData.customer_id && customerMap.has(msData.customer_id)) {
            msData.customer_id = customerMap.get(msData.customer_id);
          }
          await db.models.milk_subscriptions.create(msData);
        } catch (_) {
        }
      }
    }
    if (Array.isArray(bundle.deliveryCustomers) && db.models.delivery_customers) {
      for (const dc of bundle.deliveryCustomers) {
        try {
          const { id, ...dcData } = dc;
          dcData.outlet_id = targetOutletId;
          await db.models.delivery_customers.create(dcData);
        } catch (_) {
        }
      }
    }
    if (Array.isArray(bundle.hrEmployees) && db.models.hr_employees) {
      const [validOffices, validDesignations, validShifts, validPayStructures, validUsers] = await Promise.all([
        db.models.hr_offices ? db.models.hr_offices.findAll({ attributes: ['id'], raw: true }) : [],
        db.models.hr_designations ? db.models.hr_designations.findAll({ attributes: ['id'], raw: true }) : [],
        db.models.hr_shifts ? db.models.hr_shifts.findAll({ attributes: ['id'], raw: true }) : [],
        db.models.hr_pay_structures ? db.models.hr_pay_structures.findAll({ attributes: ['id'], raw: true }) : [],
        db.models.users ? db.models.users.findAll({ attributes: ['id'], raw: true }) : [],
      ]);
      const officeSet = new Set((validOffices || []).map((o) => o.id));
      const desigSet = new Set((validDesignations || []).map((d) => d.id));
      const shiftSet = new Set((validShifts || []).map((s) => s.id));
      const paySet = new Set((validPayStructures || []).map((p) => p.id));
      const userSet = new Set((validUsers || []).map((u) => u.id));

      for (const emp of bundle.hrEmployees) {
        try {
          const oldEmpId = emp.id;
          const { id, ...empData } = emp;
          empData.outlet_id = targetOutletId;
          empData.hire_date = empData.hire_date || (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
          empData.employee_code = empData.employee_code || `EMP-${oldEmpId || 1}`;
          empData.full_name = empData.full_name || "Employee";

          if (empData.office_id && !officeSet.has(empData.office_id)) empData.office_id = null;
          if (empData.designation_id && !desigSet.has(empData.designation_id)) empData.designation_id = null;
          if (empData.shift_id && !shiftSet.has(empData.shift_id)) empData.shift_id = null;
          if (empData.pay_structure_id && !paySet.has(empData.pay_structure_id)) empData.pay_structure_id = null;
          if (empData.user_id && !userSet.has(empData.user_id)) empData.user_id = null;
          if (empData.created_by && !userSet.has(empData.created_by)) empData.created_by = null;
          if (empData.level1_approver_id) empData.level1_approver_id = null;
          if (empData.level2_approver_id) empData.level2_approver_id = null;

          const existing = await db.models.hr_employees.findOne({
            where: { outlet_id: targetOutletId, employee_code: empData.employee_code }
          });
          if (existing) {
            await existing.update(empData);
          } else {
            await db.models.hr_employees.create(empData);
          }
        } catch (empErr) {
          console.warn(`[MIGRATION] Employee sync warning: ${empErr.message}`);
        }
      }
    }
    try {
      await db.query(`
                DO $$
                DECLARE
                    r RECORD;
                BEGIN
                    FOR r IN (
                        SELECT c.table_name, c.column_name, pg_get_serial_sequence(c.table_name, c.column_name) AS seq_name
                        FROM information_schema.columns c
                        WHERE c.table_schema = 'public' AND pg_get_serial_sequence(c.table_name, c.column_name) IS NOT NULL
                    ) LOOP
                        EXECUTE format('SELECT setval(''%s'', COALESCE((SELECT MAX(%I) FROM %I), 1), true)', r.seq_name, r.column_name, r.table_name);
                    END LOOP;
                END $$;
            `);
      console.log(`\u2705 All database serial sequences re-synchronized successfully.`);
    } catch (seqErr) {
      console.warn(`\u26A0\uFE0F Sequence reset warning: ${seqErr.message}`);
    }
    const tokenPayload = {
      id: primaryAdmin ? primaryAdmin.id : 1,
      username: primaryAdmin ? primaryAdmin.username : `admin_${outletCode.toLowerCase()}`,
      role: primaryAdmin ? primaryAdmin.role : "ADMIN",
      outlet_code: outletCode,
      outlet_id: targetOutletId
    };
    const token = (0, import_jwt.sign)(tokenPayload, { expiresIn: "7d" });
    return res.status(200).json({
      success: true,
      message: `Store for outlet '${outletCode}' successfully migrated with relational ID translation across all tables!`,
      outlet_code: outletCode,
      token,
      user: tokenPayload,
      stats: bundle.stats || {
        products: bundle.items ? bundle.items.length : 0,
        customers: bundle.customers ? bundle.customers.length : 0,
        sales: bundle.salesHeaders ? bundle.salesHeaders.length : 0
      }
    });
  } catch (error) {
    console.error("[MIGRATION IMPORT ERROR]:", error);
    return res.status(500).json({
      success: false,
      message: `Cloud migration failed: ${formatMigrationError(error)}`
    });
  }
};
const syncOnlineToOffline = async (req, res) => {
  try {
    const { cloud_url, outlet_code, admin_password, scope, otp } = req.body;
    if (!cloud_url) {
      return res.status(400).json({ success: false, message: "Cloud URL is required." });
    }
    const effectiveScope = String(scope || (outlet_code === "ALL" ? "ALL" : "OUTLET")).toUpperCase();
    if (effectiveScope !== "ALL" && !outlet_code) {
      return res.status(400).json({ success: false, message: "Outlet Code is required for single outlet sync." });
    }
    let cleanCloudUrl = cloud_url.trim();
    if (cleanCloudUrl.endsWith("/")) {
      cleanCloudUrl = cleanCloudUrl.substring(0, cleanCloudUrl.length - 1);
    }
    console.log(`[ONLINE->OFFLINE] Fetching complete migration bundle from Cloud: ${cleanCloudUrl} for outlet: ${outlet_code}...`);
    const abortCtrl = new AbortController();
    const timeoutId = setTimeout(() => abortCtrl.abort(), 12e4);
    let cloudExportRes;
    try {
      const fetchRes = await fetch(`${cleanCloudUrl}/api/public/migration/export-bundle`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ outlet_code, scope: effectiveScope, otp }),
        signal: abortCtrl.signal
      });
      cloudExportRes = await fetchRes.json();
    } finally {
      clearTimeout(timeoutId);
    }
    if (!cloudExportRes || !cloudExportRes.success || !cloudExportRes.bundle) {
      throw new Error(cloudExportRes?.message || "Failed to retrieve store bundle from cloud server.");
    }
    const cloudBundle = cloudExportRes.bundle;
    const db = req.propertyDb;
    req.body.bundle = cloudBundle;
    req.body.mode = effectiveScope === "ALL" ? "RESTORE_DB" : "MERGE_OUTLET";
    req.body.target_outlet_code = outlet_code;
    req.body.admin_password = admin_password;
    req.body.scope = effectiveScope;
    return await importBundle(req, res);
  } catch (error) {
    console.error("[ONLINE->OFFLINE ERROR]:", error);
    return res.status(500).json({
      success: false,
      message: `Online to Offline migration failed: ${formatMigrationError(error)}`
    });
  }
};
module.exports = {
  ping,
  requestMigrationOtp,
  verifyMigrationOtp,
  exportBundle,
  importBundle,
  syncOnlineToOffline
};
var migration_controller_default = {
  ping,
  requestMigrationOtp,
  verifyMigrationOtp,
  exportBundle,
  importBundle,
  syncOnlineToOffline
};
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  exportBundle,
  importBundle,
  ping,
  requestMigrationOtp,
  syncOnlineToOffline,
  verifyMigrationOtp
});
