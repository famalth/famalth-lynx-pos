"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dbMiddleware = void 0;
const propertyDb = require('../db/models');
let selfHealed = false;
const dbMiddleware = async (req, res, next) => {
    try {
        req.propertyDb = propertyDb;
        if (!selfHealed) {
            selfHealed = true;
            try {
                // Ensure base tables exist on fresh database
                await propertyDb.sync().catch((err) => {
                    if (!err.message.includes('foreign key constraint')) {
                        console.warn('⚠️ Model sync notice:', err.message);
                    }
                });
                // Dynamically ensure columns exist
                await propertyDb.query(`
          ALTER TABLE outlets ADD COLUMN IF NOT EXISTS business_module VARCHAR(50) DEFAULT 'ALL';
          ALTER TABLE sales_headers ADD COLUMN IF NOT EXISTS salesman_id INTEGER NULL;
          ALTER TABLE hr_attendance_punches ADD COLUMN IF NOT EXISTS leave_type_id INTEGER NULL;
          ALTER TABLE restaurant_tables ADD COLUMN IF NOT EXISTS x_coordinate INTEGER NULL;
          ALTER TABLE restaurant_tables ADD COLUMN IF NOT EXISTS y_coordinate INTEGER NULL;
          ALTER TABLE item_master ADD COLUMN IF NOT EXISTS is_recipe_based BOOLEAN DEFAULT FALSE;
          ALTER TABLE item_master ADD COLUMN IF NOT EXISTS is_tax_inclusive BOOLEAN DEFAULT FALSE;
          ALTER TABLE sales_headers ADD COLUMN IF NOT EXISTS coupon_discount_amount DECIMAL(12, 2) NULL;
          ALTER TABLE sales_schemes ADD COLUMN IF NOT EXISTS free_item_id INTEGER NULL;
          ALTER TABLE sales_schemes ADD COLUMN IF NOT EXISTS days_of_week VARCHAR(255) NULL;
          ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS original_rate DECIMAL(12, 2) NULL;
          ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS scheme_discount_per_unit DECIMAL(12, 2) NULL;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS time_zone VARCHAR(100) DEFAULT 'Asia/Kolkata';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS enable_salesperson_tagging BOOLEAN DEFAULT FALSE;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS bill_copies_count INTEGER DEFAULT 1;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS enable_token_system BOOLEAN DEFAULT FALSE;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS token_copies_count INTEGER DEFAULT 1;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS device_printer_mappings JSONB DEFAULT '{}';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS base_currency_code VARCHAR(20) DEFAULT 'KES';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS base_currency_symbol VARCHAR(20) DEFAULT 'KSh';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS currency_symbol_position VARCHAR(20) DEFAULT 'BEFORE';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS currency_decimals INTEGER DEFAULT 2;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS receipt_template_config JSONB DEFAULT '{}';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS a4_template_config JSONB DEFAULT '{}';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS a5_template_config JSONB DEFAULT '{}';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS kot_template_config JSONB DEFAULT '{}';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS token_template_config JSONB DEFAULT '{}';
          ALTER TABLE sales_headers ADD COLUMN IF NOT EXISTS token_no VARCHAR(50) NULL;
          ALTER TABLE email_configurations ADD COLUMN IF NOT EXISTS provider_type VARCHAR(50) DEFAULT 'SMTP';
          ALTER TABLE email_configurations ADD COLUMN IF NOT EXISTS gmail_client_id TEXT NULL;
          ALTER TABLE email_configurations ADD COLUMN IF NOT EXISTS gmail_client_secret TEXT NULL;
          ALTER TABLE email_configurations ADD COLUMN IF NOT EXISTS gmail_refresh_token TEXT NULL;
          ALTER TABLE email_configurations ADD COLUMN IF NOT EXISTS resend_api_key TEXT NULL;
          ALTER TABLE outlets ADD COLUMN IF NOT EXISTS supervisor_pin VARCHAR(100) DEFAULT '1234';
          ALTER TABLE outlets ADD COLUMN IF NOT EXISTS supervisor_pin_type VARCHAR(50) DEFAULT 'STATIC';
          ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_code VARCHAR(100) DEFAULT NULL;
          ALTER TABLE users ADD COLUMN IF NOT EXISTS show_in_quick_login BOOLEAN DEFAULT FALSE;
          ALTER TABLE users ALTER COLUMN show_in_quick_login SET DEFAULT FALSE;

          -- HRMS Punches & Devices
          ALTER TABLE hr_attendance_punches ADD COLUMN IF NOT EXISTS device_id VARCHAR(255);
          ALTER TABLE hr_attendance_punches ADD COLUMN IF NOT EXISTS device_info TEXT;
          ALTER TABLE hr_attendance_punches ADD COLUMN IF NOT EXISTS remarks TEXT;
          ALTER TABLE hr_attendance_punches ADD COLUMN IF NOT EXISTS biometric_device_id INTEGER;

          -- HRMS Employees & Security
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS bound_device_id VARCHAR(255);
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS bound_device_info TEXT;
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS office_id INTEGER;
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS reset_otp VARCHAR(10);
          ALTER TABLE hr_employees ADD COLUMN IF NOT EXISTS reset_otp_expires_at TIMESTAMPTZ;

          -- Item Master & Costing
          ALTER TABLE item_master ADD COLUMN IF NOT EXISTS average_rate DECIMAL(12, 2) DEFAULT 0.00;
          ALTER TABLE item_master ADD COLUMN IF NOT EXISTS opening_rate DECIMAL(12, 2) DEFAULT NULL;

          -- Purchase Orders
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approval_status VARCHAR(20) DEFAULT 'APPROVED';
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approved_by INTEGER;
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS rejected_by INTEGER;
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;
          ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

          -- Returns, Stock Taking & Brand
          ALTER TABLE return_items ADD COLUMN IF NOT EXISTS tax DECIMAL(5, 2) DEFAULT 0.00;
          ALTER TABLE return_items ADD COLUMN IF NOT EXISTS tax_amount DECIMAL(12, 2) DEFAULT 0.00;
          ALTER TABLE return_items ADD COLUMN IF NOT EXISTS amount DECIMAL(12, 2);
          ALTER TABLE return_items ADD COLUMN IF NOT EXISTS total_after_tax DECIMAL(12, 2);
          ALTER TABLE stock_taking ADD COLUMN IF NOT EXISTS brand VARCHAR(150);
          ALTER TABLE supplier_return_items ADD COLUMN IF NOT EXISTS brand VARCHAR(150);
          ALTER TABLE supplier_return_items ADD COLUMN IF NOT EXISTS tax DECIMAL(5, 2) DEFAULT 0.00;
          ALTER TABLE supplier_return_items ADD COLUMN IF NOT EXISTS tax_amount DECIMAL(12, 2) DEFAULT 0.00;
          ALTER TABLE supplier_return_items ADD COLUMN IF NOT EXISTS total_after_tax DECIMAL(12, 2);

          -- System Settings Clinic Closure
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS clinic_closed_today BOOLEAN DEFAULT FALSE;
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS clinic_closed_date VARCHAR(20) DEFAULT '';
          ALTER TABLE system_settings ADD COLUMN IF NOT EXISTS clinic_closed_reason TEXT DEFAULT '';

          -- Customers Email Verification
          ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_email_verified BOOLEAN DEFAULT FALSE;
          ALTER TABLE customers ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;

          -- Restaurant & KOT Revisions
          ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS original_qty DECIMAL(12, 4);
          ALTER TABLE kot_headers ADD COLUMN IF NOT EXISTS guest_count INTEGER;
          ALTER TABLE kot_revisions ADD COLUMN IF NOT EXISTS reason VARCHAR(255);
          ALTER TABLE kot_revisions ADD COLUMN IF NOT EXISTS snapshot JSONB;
          ALTER TABLE property_info ADD COLUMN IF NOT EXISTS business_module VARCHAR(50) DEFAULT 'ALL';

          -- HRMS Penalties
          CREATE TABLE IF NOT EXISTS hr_penalties (
            id SERIAL PRIMARY KEY,
            outlet_id INTEGER NOT NULL,
            employee_id INTEGER NOT NULL,
            amount DECIMAL(12, 2) NOT NULL,
            reason VARCHAR(255),
            category VARCHAR(100) DEFAULT 'Disciplinary',
            penalty_date DATE DEFAULT CURRENT_DATE,
            pay_period VARCHAR(20),
            status VARCHAR(50) DEFAULT 'Pending',
            created_by INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          );
          CREATE INDEX IF NOT EXISTS idx_hr_penalties_emp ON hr_penalties (outlet_id, employee_id, status);
          ALTER TABLE property_info ADD COLUMN IF NOT EXISTS outlet_module VARCHAR(50) DEFAULT 'ALL';

          -- Supplier & Issues
          ALTER TABLE supplier_bills ADD COLUMN IF NOT EXISTS remarks TEXT;
          ALTER TABLE milk_subscription_consumptions ADD COLUMN IF NOT EXISTS notes TEXT;
          ALTER TABLE issue_items ADD COLUMN IF NOT EXISTS item_code VARCHAR(100);

          -- HRMS Additional Tables & Columns
          ALTER TABLE hr_salary_components ADD COLUMN IF NOT EXISTS created_by INTEGER;
          ALTER TABLE hr_leave_types ADD COLUMN IF NOT EXISTS created_by INTEGER;
          ALTER TABLE hr_leave_applications ADD COLUMN IF NOT EXISTS created_by INTEGER;
          ALTER TABLE hr_payroll_runs ADD COLUMN IF NOT EXISTS created_by INTEGER;
          ALTER TABLE hr_cashier_handovers ADD COLUMN IF NOT EXISTS created_by INTEGER;
          ALTER TABLE hr_loan_transactions ADD COLUMN IF NOT EXISTS outlet_id INTEGER;
          ALTER TABLE outlet_settings ADD COLUMN IF NOT EXISTS settings JSONB DEFAULT '{}';

          CREATE TABLE IF NOT EXISTS outlet_storage_quotas (
            id SERIAL PRIMARY KEY,
            outlet_id INTEGER NOT NULL,
            outlet_code VARCHAR(64) NOT NULL UNIQUE,
            base_quota_bytes BIGINT NOT NULL DEFAULT 16106127360,
            addon_quota_bytes BIGINT NOT NULL DEFAULT 0,
            promotional_bonus_bytes BIGINT NOT NULL DEFAULT 0,
            total_allocated_bytes BIGINT NOT NULL DEFAULT 16106127360,
            current_backups_bytes BIGINT NOT NULL DEFAULT 0,
            current_uploads_bytes BIGINT NOT NULL DEFAULT 0,
            current_db_bytes BIGINT NOT NULL DEFAULT 0,
            total_used_bytes BIGINT NOT NULL DEFAULT 0,
            warning_threshold_pct INTEGER NOT NULL DEFAULT 80,
            is_frozen BOOLEAN NOT NULL DEFAULT FALSE,
            active_plan_code VARCHAR(64) NOT NULL DEFAULT 'STARTER_15GB',
            plan_expires_at TIMESTAMP WITH TIME ZONE NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );

        `);
                console.log('✅ Self-healed: Checked and added missing columns to tables');
                const rawMigrationRunner = require('../utils/migrationRunner');
                const runMigrations = typeof rawMigrationRunner === 'function' ? rawMigrationRunner : (rawMigrationRunner.default || rawMigrationRunner.runMigrations);
                if (typeof runMigrations === 'function') {
                    await runMigrations(propertyDb);
                }
                console.log('✅ Self-healed: Checked and ran database schema migrations');
            }
            catch (healErr) {
                console.warn('⚠️ Self-healing column check warning:', healErr.message);
            }
        }
        next();
    }
    catch (err) {
        console.error('DB Middleware Error:', err);
        res.status(500).json({
            success: false,
            message: 'Database connection failed'
        });
    }
};
exports.dbMiddleware = dbMiddleware;
module.exports = exports.dbMiddleware;
exports.default = exports.dbMiddleware;
