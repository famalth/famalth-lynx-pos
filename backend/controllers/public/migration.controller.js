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
var import_bcryptjs = __toESM(require("bcryptjs"));
var import_backupService = require("../../modules/backupService");
var import_restore = require("../../modules/restore");
var import_jwt = require("../../utils/jwt.util");
var import_decryptConfig = __toESM(require("../../utils/decryptConfig"));
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
const exportBundle = async (req, res) => {
  try {
    const reqScope = String(req.body?.scope || "").toUpperCase();
    const isAllScope = reqScope === "ALL" || req.body?.outlet_code === "ALL";
    const outletCode = isAllScope ? "ALL" : req.user?.outlet_code || req.outlet_code || req.body.outlet_code;
    const db = req.propertyDb;
    if (!db) {
      return res.status(500).json({ success: false, message: "Database connection not available." });
    }
    const isAuthedAdmin = req.user && (req.user.role === "ADMIN" || req.user.role === "SUPER_ADMIN");
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
    let outletRecord = null;
    let outletId = null;
    let allOutlets = [];
    if (db.models.outlets) {
      allOutlets = await db.models.outlets.findAll({ raw: true }).catch(() => []);
    }
    if (!isAllScope && outletCode && outletCode !== "ALL" && db.models.outlets) {
      outletRecord = allOutlets.find((o) => o.outlet_code === outletCode) || null;
      if (outletRecord) outletId = outletRecord.id;
    }
    const outletFilter = isAllScope || !outletId ? {} : { outlet_id: outletId };
    let users = [];
    if (db.models.users) {
      users = await db.models.users.findAll({
        where: outletFilter,
        raw: true
      }).catch(async () => {
        return await db.models.users.findAll({ raw: true });
      });
      stats.users = users.length;
    }
    const settings = db.models.system_settings ? await db.models.system_settings.findOne({ raw: true }) : null;
    const branding = db.models.app_branding ? await db.models.app_branding.findOne({ raw: true }) : null;
    const numbering = db.models.numbering_settings ? await db.models.numbering_settings.findAll({ where: outletFilter, raw: true }) : [];
    const propertyInfo = db.models.property_info ? await db.models.property_info.findOne({ raw: true }) : null;
    const paymentMethods = db.models.paymentMethod ? await db.models.paymentMethod.findAll({ raw: true }) : [];
    const saleSources = db.models.saleSource ? await db.models.saleSource.findAll({ raw: true }) : [];
    const taxGroups = db.models.tax_groups ? await db.models.tax_groups.findAll({ raw: true }) : [];
    const taxGroupComponents = db.models.tax_group_components ? await db.models.tax_group_components.findAll({ raw: true }) : [];
    const itemGroups = db.models.item_groups ? await db.models.item_groups.findAll({ raw: true }) : [];
    const subcategories = db.models.subcategories ? await db.models.subcategories.findAll({ raw: true }) : [];
    const brands = db.models.brands ? await db.models.brands.findAll({ raw: true }) : [];
    const items = db.models.item_master ? await db.models.item_master.findAll({ raw: true }) : [];
    const stockLocations = db.models.stock_locations ? await db.models.stock_locations.findAll({ where: outletFilter, raw: true }) : [];
    const stockLedger = db.models.stock_ledger ? await db.models.stock_ledger.findAll({ where: outletFilter, raw: true }) : [];
    stats.products = items.length;
    const customers = db.models.customers ? await db.models.customers.findAll({ where: outletFilter, raw: true }) : [];
    const customerAdvances = db.models.customer_advances ? await db.models.customer_advances.findAll({ where: outletFilter, raw: true }) : [];
    const customerRepayments = db.models.customer_repayments ? await db.models.customer_repayments.findAll({ where: outletFilter, raw: true }) : [];
    const suppliers = db.models.supplier_master ? await db.models.supplier_master.findAll({ where: outletFilter, raw: true }) : [];
    const supplierBills = db.models.supplier_bills ? await db.models.supplier_bills.findAll({ where: outletFilter, raw: true }) : [];
    const supplierPayments = db.models.supplier_payments ? await db.models.supplier_payments.findAll({ where: outletFilter, raw: true }) : [];
    stats.customers = customers.length;
    stats.suppliers = suppliers.length;
    const salesHeaders = db.models.sales_headers ? await db.models.sales_headers.findAll({ where: outletFilter, raw: true }) : [];
    const salesHeaderIds = salesHeaders.map((sh) => sh.id);
    const { Op } = require("sequelize");
    const salesItems = db.models.sales_items && salesHeaderIds.length > 0 ? await db.models.sales_items.findAll({ where: { sale_id: { [Op.in]: salesHeaderIds } }, raw: true }) : [];
    const purchaseOrders = db.models.purchase_orders ? await db.models.purchase_orders.findAll({ where: outletFilter, raw: true }) : [];
    const poIds = purchaseOrders.map((p) => p.id);
    const purchaseOrderItems = db.models.purchase_order_items && poIds.length > 0 ? await db.models.purchase_order_items.findAll({ where: { po_id: { [Op.in]: poIds } }, raw: true }) : [];
    const goodsReceipts = db.models.goods_receipts ? await db.models.goods_receipts.findAll({ where: outletFilter, raw: true }) : [];
    const grnIds = goodsReceipts.map((g) => g.id);
    const goodsReceiptItems = db.models.goods_receipt_items && grnIds.length > 0 ? await db.models.goods_receipt_items.findAll({ where: { grn_id: { [Op.in]: grnIds } }, raw: true }) : [];
    const expenses = db.models.expenses ? await db.models.expenses.findAll({ where: outletFilter, raw: true }) : [];
    const expenseCategories = db.models.expense_categories ? await db.models.expense_categories.findAll({ raw: true }) : [];
    stats.sales = salesHeaders.length;
    stats.purchases = purchaseOrders.length;
    stats.expenses = expenses.length;
    const chartOfAccounts = db.models.chart_of_accounts ? await db.models.chart_of_accounts.findAll({ where: outletFilter, raw: true }) : [];
    const bankAccounts = db.models.bank_accounts ? await db.models.bank_accounts.findAll({ where: outletFilter, raw: true }) : [];
    const accountingVouchers = db.models.accounting_vouchers ? await db.models.accounting_vouchers.findAll({ where: outletFilter, raw: true }) : [];
    const voucherIds = accountingVouchers.map((v) => v.id);
    const voucherLines = db.models.voucher_lines && voucherIds.length > 0 ? await db.models.voucher_lines.findAll({ where: { voucher_id: { [Op.in]: voucherIds } }, raw: true }) : [];
    const floors = db.models.floor ? await db.models.floor.findAll({ where: outletFilter, raw: true }) : [];
    const diningAreas = db.models.dining_area ? await db.models.dining_area.findAll({ where: outletFilter, raw: true }) : [];
    const restaurantTables = db.models.restaurant_tables ? await db.models.restaurant_tables.findAll({ where: outletFilter, raw: true }) : [];
    const kitchenStations = db.models.kitchen_stations ? await db.models.kitchen_stations.findAll({ where: outletFilter, raw: true }) : [];
    const kotHeaders = db.models.kot_headers ? await db.models.kot_headers.findAll({ where: outletFilter, raw: true }) : [];
    const kotIds = kotHeaders.map((k) => k.id);
    const kotItems = db.models.kot_items && kotIds.length > 0 ? await db.models.kot_items.findAll({ where: { kot_id: { [Op.in]: kotIds } }, raw: true }) : [];
    const milkSubscriptions = db.models.milk_subscriptions ? await db.models.milk_subscriptions.findAll({ where: outletFilter, raw: true }) : [];
    const deliveryCustomers = db.models.delivery_customers ? await db.models.delivery_customers.findAll({ where: outletFilter, raw: true }) : [];
    const deliveryPartners = db.models.delivery_partners ? await db.models.delivery_partners.findAll({ where: outletFilter, raw: true }) : [];
    const hrEmployees = db.models.hr_employees ? await db.models.hr_employees.findAll({ where: outletFilter, raw: true }) : [];
    const hrDesignations = db.models.hr_designations ? await db.models.hr_designations.findAll({ raw: true }) : [];
    const hrShifts = db.models.hr_shifts ? await db.models.hr_shifts.findAll({ raw: true }) : [];
    let encBase64 = "";
    try {
      const dbConfig = (0, import_decryptConfig.default)();
      const dbName = req.propertyDb?.config?.database || dbConfig.db_database || process.env.DB_NAME;
      if (dbName) {
        const encPath = await (0, import_backupService.processBackup)(dbName);
        if (import_fs.default.existsSync(encPath)) {
          encBase64 = import_fs.default.readFileSync(encPath).toString("base64");
        }
      }
    } catch (encErr) {
      console.warn(`[MIGRATION EXPORT] ENC snapshot generation fallback: ${encErr.message}`);
    }
    const bundle = {
      version: "2.0",
      exported_at: (/* @__PURE__ */ new Date()).toISOString(),
      source_outlet_code: outletCode || (outletRecord ? outletRecord.outlet_code : "DEFAULT"),
      stats,
      outletRecord,
      users,
      settings,
      branding,
      numbering,
      propertyInfo,
      paymentMethods,
      saleSources,
      taxGroups,
      taxGroupComponents,
      itemGroups,
      subcategories,
      brands,
      items,
      stockLocations,
      stockLedger,
      customers,
      customerAdvances,
      customerRepayments,
      suppliers,
      supplierBills,
      supplierPayments,
      salesHeaders,
      salesItems,
      purchaseOrders,
      purchaseOrderItems,
      goodsReceipts,
      goodsReceiptItems,
      expenseCategories,
      expenses,
      chartOfAccounts,
      bankAccounts,
      accountingVouchers,
      voucherLines,
      floors,
      diningAreas,
      restaurantTables,
      kitchenStations,
      kotHeaders,
      kotItems,
      milkSubscriptions,
      deliveryCustomers,
      deliveryPartners,
      hrEmployees,
      hrDesignations,
      hrShifts,
      outlets: allOutlets,
      scope: isAllScope ? "ALL" : "OUTLET",
      database_enc_base64: encBase64
    };
    return res.status(200).json({
      success: true,
      message: "Store migration bundle exported successfully with full table coverage.",
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
      for (const emp of bundle.hrEmployees) {
        try {
          const oldEmpId = emp.id;
          const { id, ...empData } = emp;
          empData.outlet_id = targetOutletId;
          empData.hire_date = empData.hire_date || (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
          empData.employee_code = empData.employee_code || `EMP-${oldEmpId || 1}`;
          empData.full_name = empData.full_name || "Employee";
          await db.models.hr_employees.create(empData);
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
    console.log(`[ONLINE->OFFLINE] Purging all local tables in FK cascade order for clean offline restore...`);
    const tablesToPurge = [
      "voucher_lines",
      "accounting_vouchers",
      "bank_accounts",
      "chart_of_accounts",
      "kot_items",
      "kot_headers",
      "restaurant_tables",
      "dining_areas",
      "floors",
      "milk_subscriptions",
      "delivery_customers",
      "delivery_partners",
      "hr_employees",
      "stock_ledger",
      "stock_locations",
      "sales_items",
      "sales_headers",
      "goods_receipt_items",
      "goods_receipts",
      "purchase_order_items",
      "purchase_orders",
      "expenses",
      "expense_categories",
      "customers",
      "supplier_master",
      "item_master",
      "brands",
      "subcategories",
      "tax_group_components",
      "tax_groups",
      "item_groups",
      "numbering_settings"
    ];
    for (const tableName of tablesToPurge) {
      try {
        if (db.models[tableName]) {
          await db.models[tableName].destroy({ where: {}, truncate: { cascade: true } });
        }
      } catch (pErr) {
        try {
          await db.query(`TRUNCATE TABLE "${tableName}" CASCADE;`);
        } catch (_) {
        }
      }
    }
    console.log(`\u2705 Local tables purged cleanly.`);
    req.body.bundle = cloudBundle;
    req.body.mode = "MERGE_OUTLET";
    req.body.target_outlet_code = outlet_code;
    req.body.admin_password = admin_password;
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
