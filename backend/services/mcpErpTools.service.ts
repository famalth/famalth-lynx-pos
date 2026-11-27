/**
 * FAMALTH LYNX - Enterprise ERP MCP Tools (PO, KOT Table Order, Masters, Attendance)
 * Strictly scoped to authorized outletId / linked cluster.
 */

const defaultDb = require('../db/models');

function getActiveDb(db: any) {
  return db?.query ? db : (db?.sequelize || defaultDb.sequelize || defaultDb);
}

function resolveTargetOutlet(scope: any, requestedOutletId?: number): number {
  const target = Number(requestedOutletId || scope.primaryOutletId);
  if (!scope.allowedOutletIds.includes(target)) {
    throw new Error(`Security Violation: Outlet #${target} is outside your authorized cluster [${scope.allowedOutletIds.join(', ')}].`);
  }
  return target;
}

function todayYmd(): string {
  return new Date().toISOString().split('T')[0];
}

async function allocateSequentialDocNo(
  activeDb: any,
  moduleName: 'PO' | 'KOT' | 'SALES',
  outletId: number,
  dateVal: any,
  transaction?: any
): Promise<string> {
  const numberingHelper = require('../controllers/inventory/numberingSettingsV2.controller');
  const resolved = await numberingHelper.allocateNextNumber({
    db: activeDb,
    module: moduleName,
    date: dateVal || new Date(),
    outlet_id: outletId,
    transaction,
  });
  if (resolved && resolved.number) {
    return String(resolved.number);
  }
  throw new Error(`Failed to allocate sequential ${moduleName} number for outlet #${outletId}`);
}

async function getNextMasterCode(
  activeDb: any,
  tableName: 'supplier_master' | 'hr_employees' | 'item_master',
  codeCol: string,
  outletId: number,
  defaultPrefix: string,
  padLen: number = 3
): Promise<string> {
  const [rows] = await activeDb.query(
    `SELECT "${codeCol}" AS code FROM "${tableName}" WHERE outlet_id = $1 AND "${codeCol}" IS NOT NULL`,
    { bind: [outletId] }
  );
  let maxNum = 0;
  let detectedPrefix = defaultPrefix;
  let detectedPad = padLen;
  for (const r of rows || []) {
    const code = String(r.code || '').trim();
    const m = /^(.*?)(\d+)$/.exec(code);
    if (m) {
      const n = parseInt(m[2], 10);
      if (!Number.isNaN(n) && n > maxNum) {
        maxNum = n;
        if (m[1]) detectedPrefix = m[1];
        if (m[2].length > detectedPad) detectedPad = m[2].length;
      }
    }
  }
  return `${detectedPrefix}${String(maxNum + 1).padStart(detectedPad, '0')}`;
}

export const MCP_ERP_TOOL_DEFINITIONS = [
  {
    name: 'get_outlet_profile',
    description: 'Fetches the full Outlet Profile & Business/Property details (outlet name, outlet code, address, city, state, owner, GSTIN, phone, email, currency, and linked branch outlets) for your authorized outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        outletId: { type: 'number', description: 'Optional outlet ID (must be in your authorized cluster)' },
      },
    },
  },
  {
    name: 'get_accounting_reports',
    description: 'Accesses the Accounting & Finance section for your authorized outlet: Trial Balance, Profit & Loss (P&L), Balance Sheet, Bank Reconciliation, Cash Ledger, Chart of Accounts, Accounting Vouchers, and Expenses.',
    inputSchema: {
      type: 'object',
      properties: {
        reportType: {
          type: 'string',
          enum: ['PROFIT_AND_LOSS', 'TRIAL_BALANCE', 'BALANCE_SHEET', 'BANK_RECONCILIATION', 'CASH_LEDGER', 'VOUCHERS', 'EXPENSES', 'CHART_OF_ACCOUNTS'],
          description: 'Accounting report or ledger to retrieve (defaults to PROFIT_AND_LOSS)',
        },
        startDate: { type: 'string', description: 'Start date YYYY-MM-DD (optional)' },
        endDate: { type: 'string', description: 'End date YYYY-MM-DD (optional)' },
        limit: { type: 'number', description: 'Max rows for ledger/voucher/expense lists (default 50)' },
        outletId: { type: 'number', description: 'Optional outlet ID (must be in your authorized cluster)' },
      },
    },
  },
  {
    name: 'create_purchase_order',
    description: 'Creates a Purchase Order (PO) in the database with auto-generated PO number and today date. Looks up supplier in supplier_master, checks item_master & live stock_ledger balance (min_level vs current stock) to suggest or validate order quantities, and submits the PO with PENDING_APPROVAL status so it can be approved and emailed.',
    inputSchema: {
      type: 'object',
      properties: {
        supplierName: { type: 'string', description: 'Supplier/vendor name or code (e.g. "ABC Traders" or "SUP001")' },
        supplierId: { type: 'number', description: 'Optional supplier ID' },
        poDate: { type: 'string', description: 'Optional PO date YYYY-MM-DD (auto-picks today if omitted)' },
        manualNo: { type: 'string', description: 'Optional manual reference number' },
        autoSuggestFromStock: { type: 'boolean', description: 'If true and items omitted, checks stock_ledger for low-stock items and asks user to confirm quantities' },
        items: {
          type: 'array',
          description: 'Items to order with quantities',
          items: {
            type: 'object',
            properties: {
              itemCode: { type: 'string' },
              name: { type: 'string' },
              quantity: { type: 'number' },
              unitCost: { type: 'number' },
            },
            required: ['quantity'],
          },
        },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'approve_purchase_order',
    description: 'Approves a pending Purchase Order (sets approval_status=APPROVED) and sends the approved PO email to the supplier (or specified recipientEmail).',
    inputSchema: {
      type: 'object',
      properties: {
        poNo: { type: 'string', description: 'PO Number (e.g. PO-20261127-1234)' },
        poId: { type: 'number', description: 'Optional PO ID' },
        recipientEmail: { type: 'string', description: 'Optional override email; defaults to supplier email in supplier_master' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'create_table_order',
    description: 'Creates a live Restaurant Table Order (KOT) in kot_headers & kot_items for a dining table and marks the table OCCUPIED.',
    inputSchema: {
      type: 'object',
      properties: {
        tableName: { type: 'string', description: 'Table name or number (e.g. "T1", "Table 4")' },
        tableId: { type: 'number', description: 'Optional table ID' },
        guestCount: { type: 'number', description: 'Number of guests (default 2)' },
        remarks: { type: 'string', description: 'Kitchen/order remarks' },
        items: {
          type: 'array',
          description: 'Menu items to order',
          items: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              itemCode: { type: 'string' },
              quantity: { type: 'number' },
              remark: { type: 'string' },
            },
            required: ['quantity'],
          },
        },
        outletId: { type: 'number' },
      },
      required: ['items'],
    },
  },
  {
    name: 'create_supplier',
    description: 'Creates a new Vendor/Supplier in supplier_master with all required fields.',
    inputSchema: {
      type: 'object',
      properties: {
        supplierName: { type: 'string', description: 'Vendor / Supplier Name (required)' },
        supplierCode: { type: 'string', description: 'Optional Vendor Code (auto-generated if omitted)' },
        phone: { type: 'string', description: 'Phone number' },
        email: { type: 'string', description: 'Email address (used for PO emails)' },
        address: { type: 'string', description: 'Address (required or empty string)' },
        state: { type: 'string' },
        gstin: { type: 'string' },
        countryCode: { type: 'string', description: 'Default IN' },
        openingBalance: { type: 'number', description: 'Opening credit balance' },
        outletId: { type: 'number' },
      },
      required: ['supplierName'],
    },
  },
  {
    name: 'get_attendance',
    description: 'Fetches employee attendance records from hr_attendance_punches and hr_employees for a date, month, or specific employee.',
    inputSchema: {
      type: 'object',
      properties: {
        date: { type: 'string', description: 'Date in YYYY-MM-DD (defaults to today if month omitted)' },
        month: { type: 'string', description: 'Month in YYYY-MM (optional)' },
        employeeName: { type: 'string', description: 'Filter by employee name or code (optional)' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'create_employee',
    description: 'Creates a new Employee in hr_employees with all Basic, Work, Leave Approver, Bank & Statutory fields (auto-resolving/creating department, designation, shift, and office if names are provided).',
    inputSchema: {
      type: 'object',
      properties: {
        fullName: { type: 'string', description: 'Employee full name (required)' },
        employeeCode: { type: 'string', description: 'Optional employee code (auto-generated if omitted)' },
        fatherName: { type: 'string', description: "Father's Name" },
        dateOfBirth: { type: 'string', description: 'Date of Birth (YYYY-MM-DD)' },
        bloodGroup: { type: 'string', description: 'Blood Group (e.g. O+, A+)' },
        mobile: { type: 'string' },
        email: { type: 'string' },
        gender: { type: 'string', enum: ['Male', 'Female', 'Other'] },
        departmentName: { type: 'string' },
        designationName: { type: 'string' },
        officeName: { type: 'string', description: 'HR Office name (optional)' },
        officeId: { type: 'number' },
        shiftName: { type: 'string', description: 'Shift name (optional)' },
        shiftId: { type: 'number' },
        hireDate: { type: 'string', description: 'Joining Date YYYY-MM-DD (defaults to today)' },
        payrollStartDate: { type: 'string', description: 'Payroll Start Date (EPD) YYYY-MM-DD' },
        baseSalary: { type: 'number', description: 'Monthly basic/base salary' },
        level1ApproverId: { type: 'number', description: 'Level 1 Leave Approver employee/user ID' },
        level2ApproverId: { type: 'number', description: 'Level 2 Leave Approver employee/user ID' },
        panNumber: { type: 'string', description: 'PAN (Income Tax)' },
        esiNumber: { type: 'string', description: 'ESI Number' },
        pfUanNumber: { type: 'string', description: 'PF UAN Number' },
        bankName: { type: 'string', description: 'Bank Name' },
        bankAccountNo: { type: 'string', description: 'Bank Account No.' },
        ifscCode: { type: 'string', description: 'IFSC Code' },
        outletId: { type: 'number' },
      },
      required: ['fullName'],
    },
  },
  {
    name: 'create_master_record',
    description: 'Creates any ERP Master record (ITEM, CUSTOMER, SUPPLIER, EMPLOYEE, DEPARTMENT, DESIGNATION, TABLE, FLOOR, DINING_AREA, OFFICE, SHIFT, LEAVE_TYPE, SALARY_COMPONENT, PAY_GRADE, STOCK_LOCATION, EXPENSE_CATEGORY). For ITEM, supports bulk import via data.items array or returns a sample Excel template. For TABLE, requires/resolves floor and area.',
    inputSchema: {
      type: 'object',
      properties: {
        masterType: {
          type: 'string',
          enum: ['ITEM', 'CUSTOMER', 'SUPPLIER', 'EMPLOYEE', 'DEPARTMENT', 'DESIGNATION', 'TABLE', 'FLOOR', 'DINING_AREA', 'OFFICE', 'SHIFT', 'LEAVE_TYPE', 'SALARY_COMPONENT', 'PAY_GRADE', 'STOCK_LOCATION', 'EXPENSE_CATEGORY'],
          description: 'Type of master record to create',
        },
        data: {
          type: 'object',
          description: 'Fields for the master record. For TABLE: table_name, capacity, floorName/floorId, areaName/diningAreaId. For ITEM: item_name, item_group/category, sub_category, rate/buy_price, retail_sale_price/sale_price, unit, mrp, tax_percent, hsn_sac_code, opening_balance, min_level, or items:[...] array for bulk import.',
        },
        outletId: { type: 'number' },
      },
      required: ['masterType', 'data'],
    },
  },
  {
    name: 'list_master_records',
    description: 'Lists existing master records (floors, dining areas, tables, items, categories, suppliers, customers, employees, departments, designations, offices, shifts, leave types, salary components, pay grades, stock dispatch locations) for your authorized outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        masterType: {
          type: 'string',
          enum: ['ITEM', 'CUSTOMER', 'SUPPLIER', 'EMPLOYEE', 'DEPARTMENT', 'DESIGNATION', 'TABLE', 'FLOOR', 'DINING_AREA', 'OFFICE', 'SHIFT', 'LEAVE_TYPE', 'SALARY_COMPONENT', 'PAY_GRADE', 'STOCK_LOCATION', 'EXPENSE_CATEGORY'],
        },
        search: { type: 'string', description: 'Optional search filter' },
        limit: { type: 'number', description: 'Max rows (default 50)' },
        outletId: { type: 'number' },
      },
      required: ['masterType'],
    },
  },
  {
    name: 'update_master_record',
    description: 'Updates an existing master record by ID (e.g. assign floorId / diningAreaId / capacity to a TABLE, update ITEM rate/price/sub_category, update STOCK_LOCATION, etc.) within your authorized outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        masterType: {
          type: 'string',
          enum: ['ITEM', 'CUSTOMER', 'SUPPLIER', 'EMPLOYEE', 'DEPARTMENT', 'DESIGNATION', 'TABLE', 'FLOOR', 'DINING_AREA', 'OFFICE', 'SHIFT', 'LEAVE_TYPE', 'SALARY_COMPONENT', 'PAY_GRADE', 'STOCK_LOCATION', 'EXPENSE_CATEGORY'],
        },
        id: { type: 'number', description: 'Record ID to update' },
        data: { type: 'object', description: 'Fields to update' },
        outletId: { type: 'number' },
      },
      required: ['masterType', 'id', 'data'],
    },
  },
  {
    name: 'manage_loyalty_program',
    description: 'Reads or configures the Loyalty Program (loyalty_master_config) for your outlet: program_status (ACTIVE/INACTIVE), min_purchase_threshold, earning_ratio, redemption_value, max_redeem_per_bill, point_expiry_days.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['GET', 'SAVE'], description: 'GET current config or SAVE/update config' },
        programStatus: { type: 'string', enum: ['ACTIVE', 'INACTIVE'] },
        minPurchaseThreshold: { type: 'number' },
        earningRatio: { type: 'number', description: 'Points earned per 100 or currency unit' },
        redemptionValue: { type: 'number', description: 'Currency value per point' },
        maxRedeemPerBill: { type: 'number' },
        pointExpiryDays: { type: 'number' },
        startDate: { type: 'string', description: 'YYYY-MM-DD' },
        endDate: { type: 'string', description: 'YYYY-MM-DD' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'manage_payment_methods',
    description: 'Lists, adds, or toggles Payment Methods (payment_methods) such as CASH, UPI, CARD, PHONEPE, GPAY, etc.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['LIST', 'ADD', 'TOGGLE'], description: 'LIST all, ADD new method, or TOGGLE active status' },
        name: { type: 'string', description: 'Payment method name (required for ADD)' },
        id: { type: 'number', description: 'Payment method ID (for TOGGLE)' },
        isActive: { type: 'boolean', description: 'Active state (for TOGGLE)' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'manage_lucky_draw_campaign',
    description: 'Lists, creates/starts, or picks a winner for a Lucky Draw Campaign (lucky_draw_campaigns): name, thresholdAmount, description, allowCreditors, startDate, drawDate.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['LIST', 'CREATE', 'PICK_WINNER'], description: 'LIST campaigns, CREATE new campaign, or PICK_WINNER for a campaign' },
        campaignId: { type: 'number', description: 'Campaign ID (for PICK_WINNER)' },
        name: { type: 'string', description: 'Campaign Name (e.g. "Diwali Mega Draw")' },
        thresholdAmount: { type: 'number', description: 'Ticket purchase threshold amount' },
        description: { type: 'string', description: 'Campaign/prize description' },
        allowCreditors: { type: 'boolean', description: 'Applicable for Creditors (Credit > 0)' },
        startDate: { type: 'string', description: 'YYYY-MM-DD' },
        drawDate: { type: 'string', description: 'YYYY-MM-DD' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'manage_bank_and_capital',
    description: 'Adds or lists Company Bank Accounts (bank_accounts), Active Business Loans (business_loans), and Capital Assets / Infrastructure (capital_assets) for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: ['LIST_BANK_ACCOUNTS', 'ADD_BANK_ACCOUNT', 'LIST_LOANS', 'ADD_LOAN', 'LIST_ASSETS', 'ADD_CAPITAL_ASSET'],
        },
        bankName: { type: 'string' },
        accountName: { type: 'string' },
        accountNumber: { type: 'string' },
        ifscCode: { type: 'string' },
        branchName: { type: 'string' },
        openingBalance: { type: 'number' },
        loanName: { type: 'string' },
        lenderName: { type: 'string' },
        principalAmount: { type: 'number' },
        interestRate: { type: 'number' },
        tenureMonths: { type: 'number' },
        monthlyEmi: { type: 'number' },
        assetName: { type: 'string' },
        assetCategory: { type: 'string' },
        purchaseCost: { type: 'number' },
        purchaseDate: { type: 'string', description: 'YYYY-MM-DD' },
        outletId: { type: 'number' },
      },
      required: ['action'],
    },
  },
  {
    name: 'record_finance_entry',
    description: 'Records an Expense (Payment), Income (Receipt), Withdrawal (Contra), or Opening Deposit (Contra) directly in expenses / cash_ledger for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        entryType: { type: 'string', enum: ['EXPENSE', 'INCOME', 'WITHDRAWAL', 'OPENING_DEPOSIT'] },
        amount: { type: 'number', description: 'Amount (required)' },
        paymentMethod: { type: 'string', description: 'CASH, UPI, BANK, CARD (default CASH)' },
        date: { type: 'string', description: 'YYYY-MM-DD (defaults to today)' },
        partyName: { type: 'string', description: 'Vendor/Received From/Purpose' },
        categoryName: { type: 'string', description: 'Expense category or Income source' },
        referenceNo: { type: 'string' },
        notes: { type: 'string' },
        status: { type: 'string', description: 'Paid or Pending (for EXPENSE, default Paid)' },
        outletId: { type: 'number' },
      },
      required: ['entryType', 'amount'],
    },
  },
  {
    name: 'get_party_ledgers',
    description: 'Retrieves Customer Credit & Ledger or Supplier/Vendor Ledger showing total invoiced/billed, total paid, advance held, and exact balance due for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        partyType: { type: 'string', enum: ['CUSTOMER', 'SUPPLIER', 'ALL'], description: 'CUSTOMER, SUPPLIER, or ALL' },
        search: { type: 'string', description: 'Optional customer/supplier name or phone filter' },
        onlyDue: { type: 'boolean', description: 'If true, only show parties with balance due > 0' },
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'manage_pricing_and_promos',
    description: 'Configures Commission Rules (commission_rules), Happy Hour Rules (happy_hours), Bill Value Promotion Rules (bill_value_promos), and Outlet Max Manual Discount % (system_settings) for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['LIST_RULES', 'ADD_COMMISSION_RULE', 'ADD_HAPPY_HOUR', 'ADD_PROMO_RULE', 'SET_MAX_DISCOUNT'] },
        platformId: { type: 'number' },
        categoryId: { type: 'number' },
        productId: { type: 'number' },
        minPrice: { type: 'number' },
        maxPrice: { type: 'number' },
        percentageFee: { type: 'number' },
        fixedFee: { type: 'number' },
        priority: { type: 'number' },
        startTime: { type: 'string', description: 'HH:MM for Happy Hour' },
        endTime: { type: 'string', description: 'HH:MM for Happy Hour' },
        daysOfWeek: { type: 'array', items: { type: 'string' }, description: 'e.g. ["Mon","Tue","Wed"]' },
        buyQty: { type: 'number' },
        freeQty: { type: 'number' },
        applyToAllHappyHourItems: { type: 'boolean' },
        freeItemId: { type: 'number' },
        promoName: { type: 'string' },
        minBillAmount: { type: 'number' },
        targetItemId: { type: 'number' },
        discountPercentage: { type: 'number' },
        maxDiscountPercent: { type: 'number' },
        isActive: { type: 'boolean' },
        outletId: { type: 'number' },
      },
      required: ['action'],
    },
  },
  {
    name: 'create_tax_group',
    description: 'Creates a Tax Group (tax_groups) with its Sub-Tax Components (tax_group_components) such as CGST + SGST for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        groupName: { type: 'string', description: 'Tax Group Name (e.g. GST 5%)' },
        groupCode: { type: 'string', description: 'Code printed on bill (e.g. GST5)' },
        isTaxInclusive: { type: 'boolean' },
        components: {
          type: 'array',
          description: 'Sub-tax components (e.g. [{ componentName: "CGST", componentCode: "CGST", rate: 2.5 }, { componentName: "SGST", componentCode: "SGST", rate: 2.5 }])',
          items: {
            type: 'object',
            properties: {
              componentName: { type: 'string' },
              componentCode: { type: 'string' },
              rate: { type: 'number' },
            },
            required: ['componentName', 'rate'],
          },
        },
        outletId: { type: 'number' },
      },
      required: ['groupName', 'components'],
    },
  },
  {
    name: 'create_outlet_backup',
    description: 'Creates an encrypted .fambak backup archive for your outlet and saves the snapshot to PostgreSQL cloud_backup_snapshots.',
    inputSchema: {
      type: 'object',
      properties: {
        outletId: { type: 'number' },
      },
    },
  },
  {
    name: 'manage_plugins',
    description: 'Creates/deploys custom TypeScript/JavaScript plugins in Plugin Developer Studio, lists marketplace/installed plugins, or installs/toggles plugins for your outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['DEPLOY_PLUGIN', 'LIST_INSTALLED', 'LIST_MARKETPLACE', 'INSTALL', 'TOGGLE'] },
        pluginId: { type: 'string', description: 'Plugin ID (e.g. plg_custom_webhook)' },
        name: { type: 'string', description: 'Display Name' },
        version: { type: 'string', description: 'Default 1.0.0' },
        category: { type: 'string' },
        author: { type: 'string' },
        description: { type: 'string' },
        language: { type: 'string', enum: ['typescript', 'javascript'] },
        code: { type: 'string', description: 'Plugin source code (export default { async onInit(ctx) {}, ... })' },
        isPublic: { type: 'boolean', description: 'false = This Outlet Only (default), true = Public' },
        isActive: { type: 'boolean' },
        outletId: { type: 'number' },
      },
      required: ['action'],
    },
  },
];

export async function toolCreatePurchaseOrder(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);

  // 1. Resolve Supplier
  let supplier: any = null;
  if (args.supplierId) {
    const [rows] = await activeDb.query(
      `SELECT id, supplier_code, supplier_name, email, phone FROM supplier_master WHERE outlet_id = $1 AND id = $2 LIMIT 1`,
      { bind: [outletId, Number(args.supplierId)] }
    );
    supplier = rows?.[0];
  } else if (args.supplierName) {
    const q = String(args.supplierName).trim();
    const [rows] = await activeDb.query(
      `SELECT id, supplier_code, supplier_name, email, phone FROM supplier_master
       WHERE outlet_id = $1 AND (supplier_name ILIKE $2 OR LOWER(TRIM(supplier_code)) = LOWER(TRIM($3)))
       ORDER BY id ASC LIMIT 1`,
      { bind: [outletId, `%${q}%`, q] }
    );
    supplier = rows?.[0];
  }

  if (!supplier) {
    const [allSups] = await activeDb.query(
      `SELECT id, supplier_code, supplier_name FROM supplier_master WHERE outlet_id = $1 AND is_active = TRUE ORDER BY supplier_name ASC LIMIT 20`,
      { bind: [outletId] }
    );
    return {
      status: 'NEEDS_INPUT',
      missingField: 'supplierName',
      message: args.supplierName
        ? `Supplier "${args.supplierName}" was not found for Outlet #${outletId}. Please provide an existing supplier name or create one first using create_supplier.`
        : `Please specify which supplier to create the Purchase Order for.`,
      availableSuppliers: allSups || [],
    };
  }

  // 2. Check items & stock ledger
  const reqItems = Array.isArray(args.items) ? args.items : [];
  if (reqItems.length === 0) {
    // Auto-check stock ledger & item_master for low-stock suggestions
    const [lowStockRows] = await activeDb.query(
      `SELECT im.id, im.item_code, im.item_name, im.brand, im.unit, im.rate, im.tax_percent, im.min_level,
              (COALESCE(im.opening_balance, 0) + COALESCE(SUM(sl.qty_in - sl.qty_out), 0)) AS current_stock
       FROM item_master im
       LEFT JOIN stock_ledger sl ON sl.outlet_id = im.outlet_id AND sl.item_code = im.item_code
       WHERE im.outlet_id = $1 AND im.is_active = TRUE
       GROUP BY im.id
       HAVING (COALESCE(im.opening_balance, 0) + COALESCE(SUM(sl.qty_in - sl.qty_out), 0)) <= COALESCE(im.min_level, 5)
       ORDER BY current_stock ASC
       LIMIT 20`,
      { bind: [outletId] }
    );
    return {
      status: 'NEEDS_INPUT',
      missingField: 'items',
      supplier: { id: supplier.id, code: supplier.supplier_code, name: supplier.supplier_name },
      message: 'Please specify the items and quantities to order. Here are items currently low in stock from stock_ledger:',
      lowStockSuggestions: (lowStockRows || []).map((r: any) => ({
        itemCode: r.item_code,
        itemName: r.item_name,
        unit: r.unit,
        rate: Number(r.rate || 0),
        currentStock: Number(r.current_stock || 0),
        minLevel: Number(r.min_level || 0),
        suggestedOrderQty: Math.max(Math.ceil(Number(r.min_level || 10) - Number(r.current_stock || 0)), 1),
      })),
    };
  }

  // 3. Resolve each requested item from item_master + live stock_ledger
  const resolvedItems: any[] = [];
  let grandTotal = 0;

  for (const line of reqItems) {
    const qty = Number(line.quantity || 0);
    if (qty <= 0) continue;

    const searchCode = String(line.itemCode || '').trim();
    const searchName = String(line.name || line.itemCode || '').trim();
    const [itemRows] = await activeDb.query(
      `SELECT im.id, im.item_code, im.item_name, im.brand, im.unit, im.rate, im.tax_percent, im.item_group, im.min_level,
              (COALESCE(im.opening_balance, 0) + COALESCE((SELECT SUM(qty_in - qty_out) FROM stock_ledger sl WHERE sl.outlet_id = im.outlet_id AND sl.item_code = im.item_code), 0)) AS current_stock
       FROM item_master im
       WHERE im.outlet_id = $1 AND im.is_active = TRUE
         AND (LOWER(TRIM(im.item_code)) = LOWER(TRIM($2)) OR im.item_name ILIKE $3)
       LIMIT 1`,
      { bind: [outletId, searchCode, `%${searchName}%`] }
    );
    const item = itemRows?.[0];
    if (!item) {
      return {
        status: 'ITEM_NOT_FOUND',
        message: `Item "${searchName}" not found in item_master for Outlet #${outletId}. Create it first with create_master_record (masterType: ITEM).`,
      };
    }

    const rate = line.unitCost !== undefined ? Number(line.unitCost) : Number(item.rate || 0);
    const taxPct = Number(item.tax_percent || 0);
    const baseAmt = rate * qty;
    const taxAmt = (baseAmt * taxPct) / 100;
    const totalAfterTax = baseAmt + taxAmt;
    grandTotal += totalAfterTax;

    resolvedItems.push({
      item_id: item.id,
      item_code: item.item_code,
      item_name: item.item_name,
      brand: item.brand || '',
      unit: item.unit || 'PCS',
      department: item.item_group || 'General',
      current_stock: Number(item.current_stock || 0),
      qty,
      rate,
      tax: taxPct,
      tax_amount: Number(taxAmt.toFixed(2)),
      total_after_tax: Number(totalAfterTax.toFixed(2)),
      amount: Number(totalAfterTax.toFixed(2)),
    });
  }

  if (resolvedItems.length === 0) {
    throw new Error('At least one valid item with quantity > 0 is required.');
  }

  const poDate = args.poDate || todayYmd();

  const t = await activeDb.transaction();
  try {
    const poNo = await allocateSequentialDocNo(activeDb, 'PO', outletId, poDate, t);
    const [poInsert] = await activeDb.query(
      `INSERT INTO purchase_orders (outlet_id, po_no, manual_no, supplier_id, po_date, total_amount, round_off_amount, status, approval_status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, 0, 'OPEN', 'PENDING', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id, po_no, po_date, total_amount, status, approval_status`,
      { bind: [outletId, poNo, args.manualNo || null, supplier.id, poDate, Number(grandTotal.toFixed(2))], transaction: t }
    );
    const poHeader = poInsert[0];

    for (const ri of resolvedItems) {
      await activeDb.query(
        `INSERT INTO purchase_order_items (po_id, item_id, item_code, item_name, brand, unit, qty, rate, tax, tax_amount, total_after_tax, amount, department, line_status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'OPEN')`,
        {
          bind: [
            poHeader.id, ri.item_id, ri.item_code, ri.item_name, ri.brand, ri.unit,
            ri.qty, ri.rate, ri.tax, ri.tax_amount, ri.total_after_tax, ri.amount, ri.department,
          ],
          transaction: t,
        }
      );
    }

    await t.commit();
    return {
      status: 'PENDING_APPROVAL',
      message: `Purchase Order ${poHeader.po_no} created for ${supplier.supplier_name} and submitted for approval. Call approve_purchase_order to approve and email the supplier.`,
      po: poHeader,
      supplier: { id: supplier.id, name: supplier.supplier_name, email: supplier.email || null },
      items: resolvedItems,
    };
  } catch (err) {
    await t.rollback();
    throw err;
  }
}

export async function toolApprovePurchaseOrder(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);

  if (!args.poNo && !args.poId) {
    const [pending] = await activeDb.query(
      `SELECT po.id, po.po_no, po.po_date, po.total_amount, sm.supplier_name, sm.email
       FROM purchase_orders po
       LEFT JOIN supplier_master sm ON sm.id = po.supplier_id
       WHERE po.outlet_id = $1 AND po.approval_status IN ('PENDING', 'PENDING_APPROVAL')
       ORDER BY po.id DESC LIMIT 20`,
      { bind: [outletId] }
    );
    return {
      status: 'NEEDS_INPUT',
      message: 'Please provide poNo or poId to approve.',
      pendingPurchaseOrders: pending || [],
    };
  }

  const whereCol = args.poId ? 'po.id = $2' : 'LOWER(TRIM(po.po_no)) = LOWER(TRIM($2))';
  const whereVal = args.poId ? Number(args.poId) : String(args.poNo);

  const [poRows] = await activeDb.query(
    `SELECT po.*, sm.supplier_name, sm.email AS supplier_email
     FROM purchase_orders po
     LEFT JOIN supplier_master sm ON sm.id = po.supplier_id
     WHERE po.outlet_id = $1 AND ${whereCol} LIMIT 1`,
    { bind: [outletId, whereVal] }
  );
  const po = poRows?.[0];
  if (!po) {
    throw new Error(`Purchase Order not found for Outlet #${outletId}.`);
  }

  await activeDb.query(
    `UPDATE purchase_orders
     SET approval_status = 'APPROVED', status = 'OPEN', approved_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
     WHERE id = $1 AND outlet_id = $2`,
    { bind: [po.id, outletId] }
  );

  const [poItems] = await activeDb.query(
    `SELECT item_code, item_name, unit, qty, rate, total_after_tax FROM purchase_order_items WHERE po_id = $1`,
    { bind: [po.id] }
  );

  const targetEmail = String(args.recipientEmail || po.supplier_email || '').trim();
  let emailStatus = 'SKIPPED_NO_EMAIL';
  if (targetEmail) {
    try {
      const { sendMail } = require('./email.service');
      const linesHtml = (poItems || [])
        .map((it: any) => `<tr><td>${it.item_name} (${it.item_code})</td><td>${it.qty} ${it.unit || ''}</td><td>${it.rate}</td><td>${it.total_after_tax}</td></tr>`)
        .join('');
      await sendMail({
        to: targetEmail,
        subject: `Approved Purchase Order ${po.po_no}`,
        html: `<h3>Purchase Order ${po.po_no} Approved</h3>
               <p>Supplier: <b>${po.supplier_name || ''}</b> | Date: ${po.po_date} | Total: <b>${po.total_amount}</b></p>
               <table border="1" cellpadding="6" cellspacing="0">
                 <tr><th>Item</th><th>Qty</th><th>Rate</th><th>Total</th></tr>
                 ${linesHtml}
               </table>`,
        outletId,
      });
      emailStatus = `SENT_TO_${targetEmail}`;
    } catch (mailErr: any) {
      emailStatus = `EMAIL_FAILED: ${mailErr.message}`;
    }
  }

  return {
    status: 'APPROVED',
    poNo: po.po_no,
    totalAmount: Number(po.total_amount || 0),
    emailStatus,
    message: `Purchase Order ${po.po_no} approved. Email status: ${emailStatus}.`,
  };
}

export async function toolCreateTableOrder(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);

  let table: any = null;
  if (args.tableId) {
    const [rows] = await activeDb.query(
      `SELECT id, table_name, capacity, status FROM restaurant_tables WHERE outlet_id = $1 AND id = $2 LIMIT 1`,
      { bind: [outletId, Number(args.tableId)] }
    );
    table = rows?.[0];
  } else if (args.tableName) {
    const [rows] = await activeDb.query(
      `SELECT id, table_name, capacity, status FROM restaurant_tables WHERE outlet_id = $1 AND is_active = TRUE AND table_name ILIKE $2 LIMIT 1`,
      { bind: [outletId, `%${String(args.tableName).trim()}%`] }
    );
    table = rows?.[0];
  }

  if (!table) {
    const [tables] = await activeDb.query(
      `SELECT id, table_name, capacity, status FROM restaurant_tables WHERE outlet_id = $1 AND is_active = TRUE ORDER BY table_name ASC LIMIT 30`,
      { bind: [outletId] }
    );
    return {
      status: 'NEEDS_INPUT',
      missingField: 'tableName',
      message: args.tableName
        ? `Table "${args.tableName}" not found in Outlet #${outletId}.`
        : 'Please specify a tableName or tableId.',
      availableTables: tables || [],
    };
  }

  const reqItems = Array.isArray(args.items) ? args.items : [];
  if (reqItems.length === 0) {
    throw new Error('At least one menu item is required to place a table order.');
  }

  const resolvedItems: any[] = [];
  for (const line of reqItems) {
    const qty = Number(line.quantity || 1);
    const search = String(line.itemCode || line.name || '').trim();
    const [itemRows] = await activeDb.query(
      `SELECT id, item_code, item_name FROM item_master WHERE outlet_id = $1 AND is_active = TRUE AND (LOWER(TRIM(item_code)) = LOWER(TRIM($2)) OR item_name ILIKE $3) LIMIT 1`,
      { bind: [outletId, search, `%${search}%`] }
    );
    const item = itemRows?.[0];
    if (!item) {
      throw new Error(`Menu item "${search}" not found in item_master.`);
    }
    resolvedItems.push({ item_id: item.id, item_name: item.item_name, qty, item_remark: line.remark || null });
  }

  const guestCount = Number(args.guestCount || 2);

  const t = await activeDb.transaction();
  try {
    const kotNo = await allocateSequentialDocNo(activeDb, 'KOT', outletId, new Date(), t);
    const [kotInsert] = await activeDb.query(
      `INSERT INTO kot_headers (outlet_id, kot_no, table_id, service_type, status, guest_count, remarks, revision_no, created_time, created_at, updated_at)
       VALUES ($1, $2, $3, 'DINE_IN', 'OPEN', $4, $5, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id, kot_no, status`,
      { bind: [outletId, kotNo, table.id, guestCount, args.remarks || 'Created via AI MCP'], transaction: t }
    );
    const kot = kotInsert[0];

    for (const ri of resolvedItems) {
      await activeDb.query(
        `INSERT INTO kot_items (outlet_id, kot_header_id, item_id, item_name, qty, status, item_remark)
         VALUES ($1, $2, $3, $4, $5, 'PENDING', $6)`,
        { bind: [outletId, kot.id, ri.item_id, ri.item_name, ri.qty, ri.item_remark], transaction: t }
      );
    }

    await activeDb.query(
      `UPDATE restaurant_tables SET status = 'OCCUPIED', current_guest_count = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 AND outlet_id = $3`,
      { bind: [guestCount, table.id, outletId], transaction: t }
    );

    await t.commit();
    return {
      status: 'SUCCESS',
      kotNo: kot.kot_no,
      tableName: table.table_name,
      guestCount,
      items: resolvedItems,
      message: `KOT ${kot.kot_no} placed for Table ${table.table_name}.`,
    };
  } catch (err) {
    await t.rollback();
    throw err;
  }
}

export async function toolCreateSupplier(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);
  const name = String(args.supplierName || args.vendorName || '').trim();
  if (!name) {
    return { status: 'NEEDS_INPUT', missingField: 'supplierName', message: 'supplierName is required to create a vendor.' };
  }
  const rawCode = String(args.supplierCode || args.vendorCode || '').trim().toUpperCase();
  const code = rawCode || await getNextMasterCode(activeDb, 'supplier_master', 'supplier_code', outletId, 'SUP', 3);

  const [rows] = await activeDb.query(
    `INSERT INTO supplier_master (outlet_id, supplier_code, supplier_name, address, phone, email, state, gstin, tax_country_code, opening_balance, is_active, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     RETURNING id, supplier_code, supplier_name, phone, email, gstin`,
    {
      bind: [
        outletId, code, name, args.address || '', args.phone || null, args.email || null,
        args.state || null, args.gstin || null, args.countryCode || 'IN', Number(args.openingBalance || 0),
      ],
    }
  );
  return { status: 'CREATED', supplier: rows[0], message: `Supplier ${name} (${code}) created.` };
}

export async function toolGetAttendance(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);
  const date = args.date ? String(args.date).trim() : null;
  const month = args.month ? String(args.month).trim() : null;
  const empFilter = args.employeeName ? String(args.employeeName).trim() : null;

  const conds: string[] = ['ap.outlet_id = $1'];
  const binds: any[] = [outletId];
  let idx = 2;

  if (month) {
    conds.push(`TO_CHAR(ap.punch_date, 'YYYY-MM') = $${idx++}`);
    binds.push(month);
  } else {
    conds.push(`ap.punch_date = $${idx++}`);
    binds.push(date || todayYmd());
  }

  if (empFilter) {
    conds.push(`(e.full_name ILIKE $${idx} OR LOWER(TRIM(e.employee_code)) = LOWER(TRIM($${idx + 1})))`);
    binds.push(`%${empFilter}%`, empFilter);
    idx += 2;
  }

  const [rows] = await activeDb.query(
    `SELECT e.employee_code, e.full_name, e.department, ap.punch_date, ap.punch_in, ap.punch_out, ap.hours_worked, ap.status, ap.remarks
     FROM hr_attendance_punches ap
     JOIN hr_employees e ON e.id = ap.employee_id
     WHERE ${conds.join(' AND ')}
     ORDER BY ap.punch_date DESC, e.full_name ASC
     LIMIT 100`,
    { bind: binds }
  );

  return {
    outletId,
    filter: { date: month ? null : (date || todayYmd()), month, employeeName: empFilter },
    count: (rows || []).length,
    records: rows || [],
  };
}

export async function toolCreateEmployee(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);
  const fullName = String(args.fullName || '').trim();
  if (!fullName) {
    return { status: 'NEEDS_INPUT', missingField: 'fullName', message: 'fullName is required to create an employee.' };
  }
  const rawEmpCode = String(args.employeeCode || '').trim().toUpperCase();
  const empCode = rawEmpCode || await getNextMasterCode(activeDb, 'hr_employees', 'employee_code', outletId, 'EMP', 3);
  const hireDate = args.hireDate || todayYmd();

  let deptId: number | null = args.departmentId ? Number(args.departmentId) : null;
  const deptName = String(args.departmentName || 'General').trim();
  if (!deptId) {
    const [dRows] = await activeDb.query(
      `SELECT id FROM hr_departments WHERE outlet_id = $1 AND LOWER(TRIM(department_name)) = LOWER(TRIM($2)) LIMIT 1`,
      { bind: [outletId, deptName] }
    ).catch(() => [[]]);
    if (dRows?.[0]?.id) {
      deptId = Number(dRows[0].id);
    } else {
      const deptCode = `DEPT${Date.now().toString().slice(-4)}`;
      const [dIns] = await activeDb.query(
        `INSERT INTO hr_departments (outlet_id, department_name, department_code, is_active, created_at, updated_at) VALUES ($1, $2, $3, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id`,
        { bind: [outletId, deptName, deptCode] }
      ).catch(() => [[]]);
      if (dIns?.[0]?.id) deptId = Number(dIns[0].id);
    }
  }

  let desigId: number | null = args.designationId ? Number(args.designationId) : null;
  if (!desigId && args.designationName) {
    const desigName = String(args.designationName).trim();
    const [gRows] = await activeDb.query(
      `SELECT id FROM hr_designations WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`,
      { bind: [outletId, desigName] }
    ).catch(() => [[]]);
    if (gRows?.[0]?.id) {
      desigId = Number(gRows[0].id);
    } else {
      const [gIns] = await activeDb.query(
        `INSERT INTO hr_designations (outlet_id, name, is_active, created_at, updated_at) VALUES ($1, $2, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id`,
        { bind: [outletId, desigName] }
      ).catch(() => [[]]);
      if (gIns?.[0]?.id) desigId = Number(gIns[0].id);
    }
  }

  let officeId: number | null = args.officeId ? Number(args.officeId) : null;
  if (!officeId && args.officeName) {
    const [oRows] = await activeDb.query(
      `SELECT id FROM hr_offices WHERE outlet_id = $1 AND LOWER(TRIM(office_name)) = LOWER(TRIM($2)) LIMIT 1`,
      { bind: [outletId, String(args.officeName).trim()] }
    ).catch(() => [[]]);
    if (oRows?.[0]?.id) officeId = Number(oRows[0].id);
  }

  let shiftId: number | null = args.shiftId ? Number(args.shiftId) : null;
  if (!shiftId && args.shiftName) {
    const [sRows] = await activeDb.query(
      `SELECT id FROM hr_shifts WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`,
      { bind: [outletId, String(args.shiftName).trim()] }
    ).catch(() => [[]]);
    if (sRows?.[0]?.id) shiftId = Number(sRows[0].id);
  }

  const kycDocs = {
    pan_number: args.panNumber || args.pan_number || null,
    esi_number: args.esiNumber || args.esi_number || null,
    pf_uan_number: args.pfUanNumber || args.pf_uan_number || null,
  };

  const [rows] = await activeDb.query(
    `INSERT INTO hr_employees (
       outlet_id, employee_code, full_name, father_name, contact_email, mobile, gender,
       date_of_birth, blood_group, hire_date, payroll_start_date, base_salary, status,
       department_id, department, designation_id, office_id, shift_id,
       level1_approver_id, level2_approver_id,
       bank_name, bank_account_no, bank_ifsc,
       pan_number, esi_number, pf_uan_number, kyc_documents,
       created_at, updated_at
     )
     VALUES (
       $1, $2, $3, $4, $5, $6, $7,
       $8, $9, $10, $11, $12, 'ACTIVE',
       $13, $14, $15, $16, $17,
       $18, $19,
       $20, $21, $22,
       $23, $24, $25, $26::jsonb,
       CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
     )
     RETURNING id, employee_code, full_name, father_name, mobile, contact_email, department, base_salary, date_of_birth, blood_group, payroll_start_date, office_id, shift_id, bank_name, bank_account_no, bank_ifsc, pan_number, esi_number, pf_uan_number, status`,
    {
      bind: [
        outletId, empCode, fullName, args.fatherName || args.father_name || null,
        args.email || null, args.mobile || null, args.gender || 'Male',
        args.dateOfBirth || args.date_of_birth || null, args.bloodGroup || args.blood_group || null,
        hireDate, args.payrollStartDate || args.payroll_start_date || hireDate, Number(args.baseSalary || 0),
        deptId, deptName, desigId, officeId, shiftId,
        args.level1ApproverId ? Number(args.level1ApproverId) : null,
        args.level2ApproverId ? Number(args.level2ApproverId) : null,
        args.bankName || args.bank_name || null,
        args.bankAccountNo || args.bank_account_no || null,
        args.ifscCode || args.bank_ifsc || null,
        kycDocs.pan_number, kycDocs.esi_number, kycDocs.pf_uan_number, JSON.stringify(kycDocs),
      ],
    }
  );
  return { status: 'CREATED', employee: rows[0], message: `Employee ${fullName} (${empCode}) created.` };
}

export async function toolCreateMasterRecord(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args.outletId);
  const masterType = String(args.masterType || '').toUpperCase();
  const d = args.data || {};

  switch (masterType) {
    case 'SUPPLIER':
      return toolCreateSupplier(db, scope, { ...d, supplierName: d.supplierName || d.supplier_name || d.name, outletId });
    case 'EMPLOYEE':
      return toolCreateEmployee(db, scope, { ...d, fullName: d.fullName || d.full_name || d.name, outletId });
    case 'ITEM': {
      const bulkList = Array.isArray(d.items) ? d.items : (Array.isArray(args.items) ? args.items : null);
      if (d.getSampleTemplate === true) {
        return {
          status: 'SAMPLE_TEMPLATE',
          message: 'Fill these columns in Excel/CSV and share or paste them to bulk-import items:',
          columns: ['item_name', 'item_code', 'item_group', 'sub_category', 'brand', 'unit', 'rate (buy_price)', 'retail_sale_price (sale_price)', 'mrp', 'hsn_sac_code', 'tax_percent', 'opening_balance', 'min_level', 'barcode'],
          sampleRow: {
            item_name: 'Amul Butter 500g',
            item_code: 'ITM001',
            item_group: 'Dairy',
            sub_category: 'Butter & Cheese',
            brand: 'Amul',
            unit: 'PCS',
            rate: 240,
            retail_sale_price: 275,
            mrp: 285,
            hsn_sac_code: '0405',
            tax_percent: 12,
            opening_balance: 20,
            min_level: 5,
            barcode: '8901262010016',
          },
        };
      }

      const itemsToInsert = bulkList || [d];
      const createdItems: any[] = [];
      for (const row of itemsToInsert) {
        const itemName = String(row.item_name || row.itemName || row.name || '').trim();
        if (!itemName) {
          return {
            status: 'NEEDS_INPUT',
            missingFields: ['item_name', 'item_group (category)', 'sub_category', 'rate (buy_price)', 'retail_sale_price (sale_price)', 'unit'],
            message: 'Please provide item_name, category (item_group), sub_category, buy price (rate), sale price (retail_sale_price), and unit — or ask for a sample Excel template (getSampleTemplate: true).',
          };
        }
        const rawItemCode = String(row.item_code || row.itemCode || '').trim().toUpperCase();
        const itemCode = rawItemCode || await getNextMasterCode(activeDb, 'item_master', 'item_code', outletId, 'ITM', 3);
        const category = String(row.item_group || row.category || 'General').trim();
        const subCategory = String(row.sub_category || row.subCategory || row.subcategory || 'General').trim();
        const buyPrice = Number(row.rate ?? row.buy_price ?? row.buyPrice ?? 0);
        const salePrice = Number(row.retail_sale_price ?? row.sale_price ?? row.salePrice ?? buyPrice);
        const mrp = Number(row.mrp ?? salePrice);
        const [rows] = await activeDb.query(
          `INSERT INTO item_master (outlet_id, item_code, item_name, hsn_sac_code, item_group, sub_category, brand, unit, barcode, rate, retail_sale_price, mrp, tax_percent, opening_balance, min_level, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           RETURNING id, item_code, item_name, item_group, sub_category, unit, rate, retail_sale_price, mrp, opening_balance`,
          {
            bind: [
              outletId, itemCode, itemName, row.hsn_sac_code || row.hsnCode || null, category,
              subCategory, row.brand || '', row.unit || 'PCS', row.barcode || null, buyPrice,
              salePrice, mrp, Number(row.tax_percent ?? row.taxPercent ?? 0),
              Number(row.opening_balance ?? row.openingBalance ?? 0), Number(row.min_level ?? row.minLevel ?? 5),
            ],
          }
        );
        createdItems.push(rows[0]);
      }
      return createdItems.length === 1
        ? { status: 'CREATED', item: createdItems[0], message: `Item ${createdItems[0].item_name} (${createdItems[0].item_code}) created.` }
        : { status: 'CREATED', count: createdItems.length, items: createdItems, message: `Imported ${createdItems.length} item(s) into item_master.` };
    }
    case 'CUSTOMER': {
      const cname = String(d.customer_name || d.customerName || d.name || '').trim();
      if (!cname) return { status: 'NEEDS_INPUT', missingField: 'customer_name', message: 'customer_name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO customers (outlet_id, customer_name, customer_phone, customer_address, customer_email, customer_gstin, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, customer_name, customer_phone, customer_email`,
        { bind: [outletId, cname, d.customer_phone || d.phone || null, d.customer_address || d.address || null, d.customer_email || d.email || null, d.customer_gstin || d.gstin || null] }
      );
      return { status: 'CREATED', customer: rows[0], message: `Customer ${cname} created.` };
    }
    case 'DEPARTMENT': {
      const deptName = String(d.department_name || d.departmentName || d.name || '').trim();
      if (!deptName) return { status: 'NEEDS_INPUT', missingField: 'department_name', message: 'department_name is required.' };
      const deptCode = String(d.department_code || d.departmentCode || `DEPT${Date.now().toString().slice(-4)}`).trim().toUpperCase();
      const [rows] = await activeDb.query(
        `INSERT INTO hr_departments (outlet_id, office_id, department_name, department_code, description, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, department_name, department_code, office_id`,
        { bind: [outletId, d.office_id || d.officeId || null, deptName, deptCode, d.description || null] }
      );
      return { status: 'CREATED', department: rows[0], message: `Department ${deptName} created.` };
    }
    case 'DESIGNATION': {
      const name = String(d.name || d.designation_name || '').trim();
      if (!name) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Designation name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_designations (outlet_id, office_id, name, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id, name, office_id`,
        { bind: [outletId, d.office_id || d.officeId || null, name] }
      );
      return { status: 'CREATED', designation: rows[0], message: `Designation ${name} created.` };
    }
    case 'FLOOR': {
      const fname = String(d.name || d.floor_name || d.floorName || '').trim();
      if (!fname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Floor name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO floors (outlet_id, name, status) VALUES ($1, $2, 'ACTIVE') RETURNING id, name, status`,
        { bind: [outletId, fname] }
      );
      return { status: 'CREATED', floor: rows[0], message: `Floor ${fname} created.` };
    }
    case 'DINING_AREA': {
      const aname = String(d.name || d.area_name || d.areaName || '').trim();
      if (!aname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Dining area name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO dining_areas (outlet_id, name, description, status) VALUES ($1, $2, $3, 'ACTIVE') RETURNING id, name, description, status`,
        { bind: [outletId, aname, d.description || null] }
      );
      return { status: 'CREATED', diningArea: rows[0], message: `Dining Area ${aname} created.` };
    }
    case 'TABLE': {
      const tname = String(d.table_name || d.tableName || d.name || '').trim();
      const floorInput = String(d.floor_name || d.floorName || d.floor || '').trim();
      const areaInput = String(d.area_name || d.areaName || d.area || '').trim();
      let floorId: number | null = d.floor_id || d.floorId ? Number(d.floor_id || d.floorId) : null;
      let areaId: number | null = d.dining_area_id || d.diningAreaId || d.area_id || d.areaId ? Number(d.dining_area_id || d.diningAreaId || d.area_id || d.areaId) : null;

      if (!tname || (!floorId && !floorInput) || (!areaId && !areaInput)) {
        const [availFloors] = await activeDb.query(`SELECT id, name FROM floors WHERE outlet_id = $1 ORDER BY id ASC`, { bind: [outletId] }).catch(() => [[]]);
        const [availAreas] = await activeDb.query(`SELECT id, name FROM dining_areas WHERE outlet_id = $1 ORDER BY id ASC`, { bind: [outletId] }).catch(() => [[]]);
        return {
          status: 'NEEDS_INPUT',
          missingFields: [
            ...(!tname ? ['table_name'] : []),
            ...(!floorId && !floorInput ? ['floorName (or floorId)'] : []),
            ...(!areaId && !areaInput ? ['areaName (or diningAreaId)'] : []),
          ],
          message: 'Please provide table_name, floor (floorName/floorId), and dining area (areaName/diningAreaId).',
          availableFloors: availFloors || [],
          availableAreas: availAreas || [],
        };
      }

      if (!floorId && floorInput) {
        const [fRows] = await activeDb.query(`SELECT id FROM floors WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`, { bind: [outletId, floorInput] });
        if (fRows?.[0]?.id) floorId = Number(fRows[0].id);
        else {
          const [fIns] = await activeDb.query(`INSERT INTO floors (outlet_id, name, status) VALUES ($1, $2, 'ACTIVE') RETURNING id`, { bind: [outletId, floorInput] });
          floorId = Number(fIns[0].id);
        }
      }
      if (!areaId && areaInput) {
        const [aRows] = await activeDb.query(`SELECT id FROM dining_areas WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`, { bind: [outletId, areaInput] });
        if (aRows?.[0]?.id) areaId = Number(aRows[0].id);
        else {
          const [aIns] = await activeDb.query(`INSERT INTO dining_areas (outlet_id, name, status) VALUES ($1, $2, 'ACTIVE') RETURNING id`, { bind: [outletId, areaInput] });
          areaId = Number(aIns[0].id);
        }
      }

      const [rows] = await activeDb.query(
        `INSERT INTO restaurant_tables (outlet_id, table_name, floor_id, dining_area_id, capacity, status, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, 'AVAILABLE', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, table_name, floor_id, dining_area_id, capacity, status`,
        { bind: [outletId, tname, floorId, areaId, Number(d.capacity || 4)] }
      );
      return { status: 'CREATED', table: rows[0], message: `Table ${tname} created (floor_id=${floorId}, dining_area_id=${areaId}).` };
    }
    case 'OFFICE': {
      const oname = String(d.office_name || d.officeName || d.name || '').trim();
      if (!oname) return { status: 'NEEDS_INPUT', missingField: 'office_name', message: 'office_name is required.' };
      const ocode = String(d.office_code || d.officeCode || `OFF${Date.now().toString().slice(-4)}`).trim().toUpperCase();
      const [rows] = await activeDb.query(
        `INSERT INTO hr_offices (outlet_id, office_code, office_name, address, city, state, pincode, radius_meters, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, office_code, office_name, city, state`,
        { bind: [outletId, ocode, oname, d.address || null, d.city || null, d.state || null, d.pincode || null, Number(d.radius_meters || 100)] }
      );
      return { status: 'CREATED', office: rows[0], message: `Office ${oname} (${ocode}) created.` };
    }
    case 'SHIFT': {
      const sname = String(d.name || d.shift_name || '').trim();
      if (!sname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Shift name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_shifts (outlet_id, office_id, name, start_time, end_time, grace_period_mins, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, name, start_time, end_time, grace_period_mins`,
        { bind: [outletId, d.office_id || d.officeId || null, sname, d.start_time || d.startTime || '09:00', d.end_time || d.endTime || '18:00', Number(d.grace_period_mins || 15)] }
      );
      return { status: 'CREATED', shift: rows[0], message: `Shift ${sname} created.` };
    }
    case 'LEAVE_TYPE': {
      const lname = String(d.name || d.leave_type_name || '').trim();
      if (!lname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Leave type name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_leave_types (outlet_id, office_id, name, is_paid, annual_quota, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, name, is_paid, annual_quota`,
        { bind: [outletId, d.office_id || d.officeId || null, lname, d.is_paid !== false, Number(d.annual_quota || 12)] }
      );
      return { status: 'CREATED', leaveType: rows[0], message: `Leave Type ${lname} created.` };
    }
    case 'SALARY_COMPONENT': {
      const cname = String(d.name || d.component_name || '').trim();
      if (!cname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Salary component name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_salary_components (outlet_id, office_id, name, nature, type, formula, is_taxable, frequency, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, name, nature, type, formula`,
        { bind: [outletId, d.office_id || d.officeId || null, cname, d.nature || 'EARNING', d.type || 'FIXED', d.formula || '0', d.is_taxable === true, d.frequency || 'MONTHLY'] }
      );
      return { status: 'CREATED', salaryComponent: rows[0], message: `Salary Component ${cname} created.` };
    }
    case 'PAY_GRADE': {
      const pname = String(d.name || d.pay_grade_name || '').trim();
      if (!pname) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Pay grade name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_pay_structures (outlet_id, office_id, name, description, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, name, description`,
        { bind: [outletId, d.office_id || d.officeId || null, pname, d.description || null] }
      );
      return { status: 'CREATED', payGrade: rows[0], message: `Pay Grade ${pname} created.` };
    }
    case 'STOCK_LOCATION': {
      const locName = String(d.location_name || d.locationName || d.name || '').trim();
      if (!locName) return { status: 'NEEDS_INPUT', missingField: 'location_name', message: 'location_name is required.' };
      const locCode = String(d.location_code || d.locationCode || `LOC${Date.now().toString().slice(-3)}`).trim().toUpperCase();
      const [rows] = await activeDb.query(
        `INSERT INTO stock_locations (outlet_id, location_code, location_name, description, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, location_code, location_name, description, is_active`,
        { bind: [outletId, locCode, locName, d.description || null] }
      );
      return { status: 'CREATED', stockLocation: rows[0], message: `Stock Dispatch Location ${locName} (${locCode}) created.` };
    }
    case 'EXPENSE_CATEGORY': {
      const cname = String(d.category_name || d.name || '').trim();
      if (!cname) return { status: 'NEEDS_INPUT', missingField: 'category_name', message: 'category_name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO expense_categories (outlet_id, category_name, is_active, created_at, updated_at)
         VALUES ($1, $2, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, category_name`,
        { bind: [outletId, cname] }
      );
      return { status: 'CREATED', expenseCategory: rows[0], message: `Expense Category ${cname} created.` };
    }
    default:
      throw new Error(`Unsupported masterType: ${masterType}`);
  }
}

export async function toolGetOutletProfile(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);

  const [outletRows] = await activeDb.query(
    `SELECT id, outlet_code, outlet_name, outlet_type, is_master, outlet_role, parent_outlet_id, contact_phone, contact_email, business_module
     FROM outlets WHERE id = $1 LIMIT 1`,
    { bind: [outletId] }
  );
  const outlet = outletRows?.[0] || null;

  const [propRows] = await activeDb.query(
    `SELECT * FROM property_info WHERE outlet_id = $1 ORDER BY id ASC LIMIT 1`,
    { bind: [outletId] }
  ).catch(() => [[]]);
  const prop = propRows?.[0] || {};

  return {
    outletId,
    outletCode: outlet?.outlet_code || null,
    outletName: prop.property_name || outlet?.outlet_name || `Outlet #${outletId}`,
    outletType: outlet?.outlet_type || null,
    role: outlet?.is_master || outlet?.outlet_role === 'MASTER' ? 'MASTER' : 'BRANCH',
    businessModule: outlet?.business_module || null,
    address: [prop.address_line1 || prop.address, prop.address_line2].filter(Boolean).join(', ') || null,
    city: prop.city || null,
    state: prop.state || null,
    country: prop.country || null,
    postalCode: prop.postal_code || prop.pincode || null,
    ownerName: prop.owner_name || prop.contact_person || null,
    gstin: prop.gstin || prop.tax_id_number || null,
    phone: prop.mobile || prop.phone || outlet?.contact_phone || null,
    email: prop.email || outlet?.contact_email || null,
    currencyCode: prop.currency_code || 'INR',
    currencySymbol: prop.currency_symbol || '₹',
    linkedOutlets: scope.linkedOutlets || [],
  };
}

function invokeController(fn: Function, propertyDb: any, outletId: number, query: Record<string, any>): Promise<any> {
  return new Promise((resolve, reject) => {
    const fakeReq: any = {
      propertyDb,
      user: { outlet_id: outletId, role: 'ADMIN' },
      outlet: { id: outletId },
      query: { ...query, outlet_id: outletId },
      params: {},
      body: {},
    };
    const fakeRes: any = {
      statusCode: 200,
      status(code: number) { this.statusCode = code; return this; },
      json(payload: any) {
        if (this.statusCode >= 400) return reject(new Error(payload?.message || payload?.error || 'Controller error'));
        resolve(payload);
      },
    };
    Promise.resolve(fn(fakeReq, fakeRes)).catch(reject);
  });
}

export async function toolGetAccountingReports(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const fullDb = db?.models ? db : defaultDb;
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const reportType = String(args?.reportType || 'PROFIT_AND_LOSS').toUpperCase();
  const limit = Math.min(Math.max(Number(args?.limit || 50), 1), 200);
  const queryParams: Record<string, any> = {};
  if (args?.startDate) queryParams.startDate = String(args.startDate);
  if (args?.endDate) queryParams.endDate = String(args.endDate);

  const finCtrl = require('../controllers/finance/financialReports.controller');

  switch (reportType) {
    case 'PROFIT_AND_LOSS':
      return await invokeController(finCtrl.getProfitAndLoss, fullDb, outletId, queryParams);
    case 'TRIAL_BALANCE':
      return await invokeController(finCtrl.getTrialBalance, fullDb, outletId, queryParams);
    case 'BALANCE_SHEET':
      return await invokeController(finCtrl.getBalanceSheet, fullDb, outletId, queryParams);
    case 'BANK_RECONCILIATION':
      return await invokeController(finCtrl.getBankReconciliation, fullDb, outletId, queryParams);
    case 'CASH_LEDGER': {
      const [rows] = await activeDb.query(
        `SELECT id, transaction_type, payment_method, amount_in, amount_out, balance, description, reference_no, created_at
         FROM cash_ledger WHERE outlet_id = $1 ORDER BY id DESC LIMIT $2`,
        { bind: [outletId, limit] }
      );
      return { outletId, reportType, count: (rows || []).length, records: rows || [] };
    }
    case 'VOUCHERS': {
      const [rows] = await activeDb.query(
        `SELECT id, voucher_no, voucher_type, voucher_date, payment_mode, reference_no, total_amount, narration, status, created_at
         FROM accounting_vouchers WHERE outlet_id = $1 ORDER BY id DESC LIMIT $2`,
        { bind: [outletId, limit] }
      );
      return { outletId, reportType, count: (rows || []).length, records: rows || [] };
    }
    case 'EXPENSES': {
      const [rows] = await activeDb.query(
        `SELECT id, invoice_ref_no, payment_date, payment_method, net_payable_amount, expense_note, status, created_at
         FROM expenses WHERE outlet_id = $1 ORDER BY id DESC LIMIT $2`,
        { bind: [outletId, limit] }
      );
      return { outletId, reportType, count: (rows || []).length, records: rows || [] };
    }
    case 'CHART_OF_ACCOUNTS': {
      const [rows] = await activeDb.query(
        `SELECT id, account_code, account_name, account_type, parent_group, opening_balance, is_active
         FROM chart_of_accounts WHERE outlet_id = $1 AND is_active = TRUE ORDER BY account_code ASC`,
        { bind: [outletId] }
      );
      return { outletId, reportType, count: (rows || []).length, records: rows || [] };
    }
    default:
      throw new Error(`Unsupported reportType: ${reportType}`);
  }
}

const MASTER_TABLE_MAP: Record<string, { table: string; searchCol: string }> = {
  ITEM: { table: 'item_master', searchCol: 'item_name' },
  CUSTOMER: { table: 'customers', searchCol: 'customer_name' },
  SUPPLIER: { table: 'supplier_master', searchCol: 'supplier_name' },
  EMPLOYEE: { table: 'hr_employees', searchCol: 'full_name' },
  DEPARTMENT: { table: 'hr_departments', searchCol: 'department_name' },
  DESIGNATION: { table: 'hr_designations', searchCol: 'name' },
  TABLE: { table: 'restaurant_tables', searchCol: 'table_name' },
  FLOOR: { table: 'floors', searchCol: 'name' },
  DINING_AREA: { table: 'dining_areas', searchCol: 'name' },
  OFFICE: { table: 'hr_offices', searchCol: 'office_name' },
  SHIFT: { table: 'hr_shifts', searchCol: 'name' },
  LEAVE_TYPE: { table: 'hr_leave_types', searchCol: 'name' },
  SALARY_COMPONENT: { table: 'hr_salary_components', searchCol: 'name' },
  PAY_GRADE: { table: 'hr_pay_structures', searchCol: 'name' },
  STOCK_LOCATION: { table: 'stock_locations', searchCol: 'location_name' },
  EXPENSE_CATEGORY: { table: 'expense_categories', searchCol: 'category_name' },
};

export async function toolListMasterRecords(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const masterType = String(args?.masterType || '').toUpperCase();
  const meta = MASTER_TABLE_MAP[masterType];
  if (!meta) throw new Error(`Unsupported masterType: ${masterType}`);

  const limit = Math.min(Math.max(Number(args?.limit || 50), 1), 200);
  const search = String(args?.search || '').trim();

  if (search) {
    const [rows] = await activeDb.query(
      `SELECT * FROM "${meta.table}" WHERE outlet_id = $1 AND "${meta.searchCol}" ILIKE $2 ORDER BY id ASC LIMIT $3`,
      { bind: [outletId, `%${search}%`, limit] }
    );
    return { outletId, masterType, count: (rows || []).length, records: rows || [] };
  }

  const [rows] = await activeDb.query(
    `SELECT * FROM "${meta.table}" WHERE outlet_id = $1 ORDER BY id ASC LIMIT $2`,
    { bind: [outletId, limit] }
  );
  return { outletId, masterType, count: (rows || []).length, records: rows || [] };
}

export async function toolUpdateMasterRecord(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const masterType = String(args?.masterType || '').toUpperCase();
  const meta = MASTER_TABLE_MAP[masterType];
  if (!meta) throw new Error(`Unsupported masterType: ${masterType}`);
  const id = Number(args?.id || 0);
  if (!id) throw new Error('Valid record id is required to update.');

  const d: Record<string, any> = { ...(args?.data || {}) };
  // Resolve floorName / areaName if updating a TABLE
  if (masterType === 'TABLE') {
    if (d.floorName && !d.floor_id) {
      const [fRows] = await activeDb.query(`SELECT id FROM floors WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`, { bind: [outletId, String(d.floorName)] });
      if (fRows?.[0]?.id) d.floor_id = Number(fRows[0].id);
    }
    if (d.areaName && !d.dining_area_id) {
      const [aRows] = await activeDb.query(`SELECT id FROM dining_areas WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`, { bind: [outletId, String(d.areaName)] });
      if (aRows?.[0]?.id) d.dining_area_id = Number(aRows[0].id);
    }
    if (d.floorId !== undefined && d.floor_id === undefined) d.floor_id = Number(d.floorId);
    if (d.diningAreaId !== undefined && d.dining_area_id === undefined) d.dining_area_id = Number(d.diningAreaId);
    if (d.areaId !== undefined && d.dining_area_id === undefined) d.dining_area_id = Number(d.areaId);
    delete d.floorName;
    delete d.areaName;
    delete d.floorId;
    delete d.diningAreaId;
    delete d.areaId;
  }

  delete d.id;
  delete d.outlet_id;
  delete d.created_at;
  const keys = Object.keys(d).filter(k => /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(k));
  if (keys.length === 0) throw new Error('No valid fields provided to update.');

  const sets = keys.map((k, idx) => `"${k}" = $${idx + 3}`).join(', ');
  const binds = [id, outletId, ...keys.map(k => d[k])];
  const [rows] = await activeDb.query(
    `UPDATE "${meta.table}" SET ${sets} WHERE id = $1 AND outlet_id = $2 RETURNING *`,
    { bind: binds }
  );
  if (!rows || rows.length === 0) {
    throw new Error(`${masterType} #${id} not found for Outlet #${outletId}.`);
  }
  return { status: 'UPDATED', masterType, record: rows[0], message: `${masterType} #${id} updated.` };
}

export async function toolManageLoyaltyProgram(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || 'GET').toUpperCase();

  if (action === 'GET') {
    const [rows] = await activeDb.query(
      `SELECT * FROM loyalty_master_config WHERE outlet_id = $1 LIMIT 1`,
      { bind: [outletId] }
    );
    return { outletId, config: rows?.[0] || null };
  }

  const [existing] = await activeDb.query(
    `SELECT id FROM loyalty_master_config WHERE outlet_id = $1 LIMIT 1`,
    { bind: [outletId] }
  );
  const status = String(args.programStatus || 'ACTIVE').toUpperCase();
  const minThreshold = Number(args.minPurchaseThreshold ?? 100);
  const earningRatio = Number(args.earningRatio ?? 1);
  const redemptionVal = Number(args.redemptionValue ?? 1);
  const maxRedeem = Number(args.maxRedeemPerBill ?? 500);
  const expiryDays = Number(args.pointExpiryDays ?? 365);

  if (existing?.[0]?.id) {
    const [rows] = await activeDb.query(
      `UPDATE loyalty_master_config
       SET program_status = $1, min_purchase_threshold = $2, earning_ratio = $3, redemption_value = $4,
           max_redeem_per_bill = $5, point_expiry_days = $6, start_date = COALESCE($7, start_date),
           end_date = COALESCE($8, end_date), updated_at = CURRENT_TIMESTAMP
       WHERE outlet_id = $9 RETURNING *`,
      { bind: [status, minThreshold, earningRatio, redemptionVal, maxRedeem, expiryDays, args.startDate || null, args.endDate || null, outletId] }
    );
    return { status: 'UPDATED', config: rows[0], message: 'Loyalty program configuration updated.' };
  }

  const [rows] = await activeDb.query(
    `INSERT INTO loyalty_master_config (outlet_id, program_status, start_date, end_date, min_purchase_threshold, earning_ratio, redemption_value, max_redeem_per_bill, point_expiry_days, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
    { bind: [outletId, status, args.startDate || todayYmd(), args.endDate || null, minThreshold, earningRatio, redemptionVal, maxRedeem, expiryDays] }
  );
  return { status: 'CREATED', config: rows[0], message: 'Loyalty program configured.' };
}

export async function toolManagePaymentMethods(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || 'LIST').toUpperCase();

  if (action === 'LIST') {
    const [rows] = await activeDb.query(`SELECT id, name, is_system, is_active FROM payment_methods ORDER BY id ASC`);
    return { count: (rows || []).length, paymentMethods: rows || [] };
  }
  if (action === 'ADD') {
    const name = String(args?.name || '').trim().toUpperCase();
    if (!name) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Payment method name is required.' };
    const [rows] = await activeDb.query(
      `INSERT INTO payment_methods (name, is_system, is_active, "createdAt", "updatedAt")
       VALUES ($1, FALSE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id, name, is_active`,
      { bind: [name] }
    );
    return { status: 'CREATED', paymentMethod: rows[0], message: `Payment method ${name} added.` };
  }
  if (action === 'TOGGLE') {
    const id = Number(args?.id || 0);
    if (!id) throw new Error('Payment method id is required to toggle.');
    const [rows] = await activeDb.query(
      `UPDATE payment_methods SET is_active = $1, "updatedAt" = CURRENT_TIMESTAMP WHERE id = $2 RETURNING id, name, is_active`,
      { bind: [args.isActive !== false, id] }
    );
    return { status: 'UPDATED', paymentMethod: rows?.[0], message: `Payment method #${id} updated.` };
  }
  throw new Error(`Unsupported action: ${action}`);
}

export async function toolManageLuckyDrawCampaign(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || 'LIST').toUpperCase();

  if (action === 'LIST') {
    const [rows] = await activeDb.query(
      `SELECT * FROM lucky_draw_campaigns WHERE outlet_id = $1 ORDER BY id DESC LIMIT 30`,
      { bind: [outletId] }
    );
    return { outletId, count: (rows || []).length, campaigns: rows || [] };
  }
  if (action === 'CREATE') {
    const name = String(args?.name || '').trim();
    if (!name) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Campaign name is required.' };
    const threshold = Number(args?.thresholdAmount ?? 1000);
    const drawDate = args?.drawDate || null;
    const startDate = args?.startDate || todayYmd();
    const [rows] = await activeDb.query(
      `INSERT INTO lucky_draw_campaigns (outlet_id, name, status, threshold_amount, start_date, draw_date, description, allow_creditors, created_at, updated_at)
       VALUES ($1, $2, 'ACTIVE', $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
      { bind: [outletId, name, threshold, startDate, drawDate, args?.description || '', args?.allowCreditors === true] }
    );
    return { status: 'CREATED', campaign: rows[0], message: `Lucky Draw Campaign "${name}" started.` };
  }
  if (action === 'PICK_WINNER') {
    const cid = Number(args?.campaignId || 0);
    if (!cid) return { status: 'NEEDS_INPUT', missingField: 'campaignId', message: 'campaignId is required to pick a winner.' };
    const [vouchers] = await activeDb.query(
      `SELECT * FROM draw_vouchers WHERE outlet_id = $1 AND campaign_id = $2 ORDER BY RANDOM() LIMIT 1`,
      { bind: [outletId, cid] }
    );
    const winner = vouchers?.[0];
    if (!winner) {
      return { status: 'NO_VOUCHERS', message: `No draw vouchers found yet for campaign #${cid}.` };
    }
    await activeDb.query(`UPDATE draw_vouchers SET is_winner = TRUE WHERE id = $1`, { bind: [winner.id] });
    await activeDb.query(`UPDATE lucky_draw_campaigns SET winner_voucher_id = $1, status = 'COMPLETED', updated_at = CURRENT_TIMESTAMP WHERE id = $2 AND outlet_id = $3`, { bind: [winner.id, cid, outletId] });
    return { status: 'WINNER_PICKED', winner, message: `Winner picked for campaign #${cid}: ${winner.customer_name || winner.customer_phone} (Voucher: ${winner.voucher_code})` };
  }
  throw new Error(`Unsupported action: ${action}`);
}

export async function toolManageBankAndCapital(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || '').toUpperCase();

  switch (action) {
    case 'LIST_BANK_ACCOUNTS': {
      const [rows] = await activeDb.query(`SELECT * FROM bank_accounts WHERE outlet_id = $1 ORDER BY id ASC`, { bind: [outletId] });
      return { outletId, count: (rows || []).length, bankAccounts: rows || [] };
    }
    case 'ADD_BANK_ACCOUNT': {
      const bankName = String(args?.bankName || '').trim();
      const accountName = String(args?.accountName || '').trim();
      const accountNumber = String(args?.accountNumber || '').trim();
      if (!bankName || !accountName || !accountNumber) {
        return { status: 'NEEDS_INPUT', missingFields: ['bankName', 'accountName', 'accountNumber'], message: 'bankName, accountName, and accountNumber are required.' };
      }
      const openBal = Number(args?.openingBalance || 0);
      const [rows] = await activeDb.query(
        `INSERT INTO bank_accounts (outlet_id, bank_name, account_name, account_number, ifsc_code, branch_name, opening_balance, current_balance, is_active, is_primary, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $7, TRUE, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        { bind: [outletId, bankName, accountName, accountNumber, args?.ifscCode || null, args?.branchName || null, openBal] }
      );
      return { status: 'CREATED', bankAccount: rows[0], message: `Bank Account ${bankName} (${accountNumber}) added.` };
    }
    case 'LIST_LOANS': {
      const [rows] = await activeDb.query(`SELECT * FROM business_loans WHERE outlet_id = $1 ORDER BY id DESC`, { bind: [outletId] });
      return { outletId, count: (rows || []).length, loans: rows || [] };
    }
    case 'ADD_LOAN': {
      const loanName = String(args?.loanName || '').trim();
      const lenderName = String(args?.lenderName || '').trim();
      const principal = Number(args?.principalAmount || 0);
      if (!loanName || !lenderName || principal <= 0) {
        return { status: 'NEEDS_INPUT', missingFields: ['loanName', 'lenderName', 'principalAmount'], message: 'loanName, lenderName, and principalAmount > 0 are required.' };
      }
      const [rows] = await activeDb.query(
        `INSERT INTO business_loans (outlet_id, loan_name, lender_name, principal_amount, interest_rate, tenure_months, monthly_emi, remaining_principal, status, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $4, 'ACTIVE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        { bind: [outletId, loanName, lenderName, principal, Number(args?.interestRate || 10.5), Number(args?.tenureMonths || 36), Number(args?.monthlyEmi || 0)] }
      );
      return { status: 'CREATED', loan: rows[0], message: `Business Loan "${loanName}" added.` };
    }
    case 'LIST_ASSETS': {
      const [rows] = await activeDb.query(`SELECT * FROM capital_assets WHERE outlet_id = $1 ORDER BY id DESC`, { bind: [outletId] });
      return { outletId, count: (rows || []).length, assets: rows || [] };
    }
    case 'ADD_CAPITAL_ASSET': {
      const assetName = String(args?.assetName || '').trim();
      const cost = Number(args?.purchaseCost || 0);
      if (!assetName || cost <= 0) {
        return { status: 'NEEDS_INPUT', missingFields: ['assetName', 'purchaseCost'], message: 'assetName and purchaseCost > 0 are required.' };
      }
      const [rows] = await activeDb.query(
        `INSERT INTO capital_assets (outlet_id, asset_name, asset_category, purchase_date, purchase_cost, current_value, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        { bind: [outletId, assetName, args?.assetCategory || 'Fixed Asset (Infrastructure)', args?.purchaseDate || todayYmd(), cost] }
      );
      return { status: 'CREATED', asset: rows[0], message: `Capital Asset "${assetName}" added.` };
    }
    default:
      throw new Error(`Unsupported action: ${action}`);
  }
}

export async function toolRecordFinanceEntry(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const entryType = String(args?.entryType || '').toUpperCase();
  const amount = Number(args?.amount || 0);
  if (amount <= 0) return { status: 'NEEDS_INPUT', missingField: 'amount', message: 'amount > 0 is required.' };
  const dateStr = args?.date || todayYmd();
  const method = String(args?.paymentMethod || 'CASH').toUpperCase();

  if (entryType === 'EXPENSE') {
    let catId: number | null = null;
    if (args?.categoryName) {
      const [cRows] = await activeDb.query(
        `SELECT id FROM expense_categories WHERE outlet_id = $1 AND LOWER(TRIM(category_name)) = LOWER(TRIM($2)) LIMIT 1`,
        { bind: [outletId, String(args.categoryName)] }
      ).catch(() => [[]]);
      if (cRows?.[0]?.id) catId = Number(cRows[0].id);
    }
    const [expRows] = await activeDb.query(
      `INSERT INTO expenses (outlet_id, category_id, invoice_ref_no, payment_date, payment_method, is_tax_inclusive, base_amount, total_tax_amount, total_deduction_amount, net_payable_amount, expense_note, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, TRUE, $6, 0, 0, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
      { bind: [outletId, catId, args?.referenceNo || null, dateStr, method, amount, args?.notes || args?.partyName || 'Expense via AI', args?.status || 'Paid'] }
    );
    await activeDb.query(
      `INSERT INTO cash_ledger (outlet_id, txn_date, transaction_type, reference_type, reference_id, reference_no, party_name, payment_method, amount_in, amount_out, notes, created_at)
       VALUES ($1, $2, 'EXPENSE_PAYMENT', 'EXPENSE', $3, $4, $5, $6, 0, $7, $8, CURRENT_TIMESTAMP)`,
      { bind: [outletId, dateStr, expRows[0].id, args?.referenceNo || null, args?.partyName || null, method, amount, args?.notes || 'Expense via AI'] }
    );
    return { status: 'CREATED', entryType, expense: expRows[0], message: `Expense of Rs. ${amount.toFixed(2)} recorded.` };
  }

  const txnType = entryType === 'INCOME' ? 'INCOME_RECEIPT' : (entryType === 'WITHDRAWAL' ? 'WITHDRAWAL' : 'OPENING_BALANCE');
  const amtIn = entryType === 'WITHDRAWAL' ? 0 : amount;
  const amtOut = entryType === 'WITHDRAWAL' ? amount : 0;

  const [rows] = await activeDb.query(
    `INSERT INTO cash_ledger (outlet_id, txn_date, transaction_type, reference_no, party_name, payment_method, amount_in, amount_out, notes, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP) RETURNING *`,
    { bind: [outletId, dateStr, txnType, args?.referenceNo || null, args?.partyName || args?.categoryName || null, method, amtIn, amtOut, args?.notes || `${entryType} via AI`] }
  );
  return { status: 'CREATED', entryType, ledgerEntry: rows[0], message: `${entryType} of Rs. ${amount.toFixed(2)} recorded.` };
}

export async function toolGetPartyLedgers(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const partyType = String(args?.partyType || 'ALL').toUpperCase();
  const search = String(args?.search || '').trim();
  const onlyDue = args?.onlyDue === true;

  const result: any = { outletId };

  if (partyType === 'CUSTOMER' || partyType === 'ALL') {
    const searchCond = search ? `AND (COALESCE(sh.customer_name, '') ILIKE $2 OR COALESCE(sh.customer_phone, '') ILIKE $2)` : '';
    const binds = search ? [outletId, `%${search}%`] : [outletId];
    const [custRows] = await activeDb.query(
      `SELECT
         COALESCE(NULLIF(TRIM(sh.customer_phone), ''), NULLIF(TRIM(sh.customer_name), ''), 'Walk-in') AS party_key,
         MAX(sh.customer_name) AS customer_name,
         MAX(sh.customer_phone) AS customer_phone,
         COALESCE(SUM(sh.net_amount), 0) AS total_invoiced,
         COALESCE(SUM(CASE WHEN UPPER(COALESCE(sh.payment_mode, '')) = 'CREDIT' THEN 0 ELSE sh.net_amount END), 0) AS direct_paid,
         COALESCE(SUM(COALESCE(rep.paid_amt, 0)), 0) AS credit_repaid
       FROM sales_headers sh
       LEFT JOIN (
         SELECT sale_id, SUM(amount) AS paid_amt FROM customer_repayments WHERE outlet_id = $1 GROUP BY sale_id
       ) rep ON rep.sale_id = sh.id
       WHERE sh.outlet_id = $1 AND COALESCE(sh.is_deleted, FALSE) = FALSE ${searchCond}
       GROUP BY party_key
       ORDER BY total_invoiced DESC
       LIMIT 100`,
      { bind: binds }
    );
    const customers = (custRows || []).map((c: any) => {
      const invoiced = Number(c.total_invoiced || 0);
      const paid = Number(c.direct_paid || 0) + Number(c.credit_repaid || 0);
      const due = Math.max(0, Number((invoiced - paid).toFixed(2)));
      return {
        customerName: c.customer_name || 'Walk-in',
        customerPhone: c.customer_phone || null,
        totalInvoiced: Number(invoiced.toFixed(2)),
        totalPaid: Number(paid.toFixed(2)),
        balanceDue: due,
      };
    }).filter((c: any) => !onlyDue || c.balanceDue > 0);
    result.customers = customers;
  }

  if (partyType === 'SUPPLIER' || partyType === 'ALL') {
    const searchCond = search ? `AND (sm.supplier_name ILIKE $2 OR sm.supplier_code ILIKE $2 OR COALESCE(sm.phone, '') ILIKE $2)` : '';
    const binds = search ? [outletId, `%${search}%`] : [outletId];
    const [supRows] = await activeDb.query(
      `SELECT
         sm.id, sm.supplier_code, sm.supplier_name, sm.phone, COALESCE(sm.opening_balance, 0) AS opening_balance,
         COALESCE(bills.total_billed, 0) AS total_billed,
         COALESCE(pays.total_paid, 0) AS total_paid
       FROM supplier_master sm
       LEFT JOIN (
         SELECT supplier_id, SUM(total_amount) AS total_billed FROM supplier_bills WHERE outlet_id = $1 GROUP BY supplier_id
       ) bills ON bills.supplier_id = sm.id
       LEFT JOIN (
         SELECT supplier_id, SUM(amount + COALESCE(credit_adjusted, 0)) AS total_paid FROM supplier_payments WHERE outlet_id = $1 GROUP BY supplier_id
       ) pays ON pays.supplier_id = sm.id
       WHERE sm.outlet_id = $1 AND sm.is_active = TRUE ${searchCond}
       ORDER BY sm.supplier_name ASC
       LIMIT 100`,
      { bind: binds }
    );
    const suppliers = (supRows || []).map((s: any) => {
      const billed = Number(s.opening_balance || 0) + Number(s.total_billed || 0);
      const paid = Number(s.total_paid || 0);
      const due = Math.max(0, Number((billed - paid).toFixed(2)));
      return {
        supplierCode: s.supplier_code,
        supplierName: s.supplier_name,
        phone: s.phone || null,
        totalBilled: Number(billed.toFixed(2)),
        totalPaid: Number(paid.toFixed(2)),
        balanceDue: due,
      };
    }).filter((s: any) => !onlyDue || s.balanceDue > 0);
    result.suppliers = suppliers;
  }

  return result;
}

export async function toolManagePricingAndPromos(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || 'LIST_RULES').toUpperCase();

  switch (action) {
    case 'LIST_RULES': {
      const [commissions] = await activeDb.query(`SELECT * FROM commission_rules WHERE outlet_id = $1 ORDER BY priority DESC, id DESC`, { bind: [outletId] }).catch(() => [[]]);
      const [happyHours] = await activeDb.query(`SELECT * FROM happy_hours WHERE outlet_id = $1 ORDER BY id DESC`, { bind: [outletId] }).catch(() => [[]]);
      const [promos] = await activeDb.query(`SELECT * FROM bill_value_promos WHERE outlet_id = $1 ORDER BY id DESC`, { bind: [outletId] }).catch(() => [[]]);
      const [settings] = await activeDb.query(`SELECT outlet_max_discount_percent FROM system_settings WHERE outlet_id = $1 LIMIT 1`, { bind: [outletId] }).catch(() => [[]]);
      return {
        outletId,
        maxManualDiscountPercent: Number(settings?.[0]?.outlet_max_discount_percent ?? 100),
        commissionRules: commissions || [],
        happyHours: happyHours || [],
        billValuePromos: promos || [],
      };
    }
    case 'ADD_COMMISSION_RULE': {
      const [rows] = await activeDb.query(
        `INSERT INTO commission_rules (outlet_id, platform_id, category_id, product_id, min_price, max_price, percentage_fee, fixed_fee, priority, is_active, "createdAt", "updatedAt")
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        {
          bind: [
            outletId, args.platformId || null, args.categoryId || null, args.productId || null,
            Number(args.minPrice ?? 0), Number(args.maxPrice ?? 9999999),
            Number(args.percentageFee ?? 0), Number(args.fixedFee ?? 0),
            Number(args.priority ?? 0), args.isActive !== false,
          ],
        }
      );
      return { status: 'CREATED', commissionRule: rows[0], message: 'Commission rule created.' };
    }
    case 'ADD_HAPPY_HOUR': {
      const startTime = String(args.startTime || '15:00').trim();
      const endTime = String(args.endTime || '18:00').trim();
      const days = Array.isArray(args.daysOfWeek) ? JSON.stringify(args.daysOfWeek) : JSON.stringify(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
      const [rows] = await activeDb.query(
        `INSERT INTO happy_hours (outlet_id, start_time, end_time, days_of_week, buy_qty, free_qty, apply_to_all_happy_hour_items, free_item_id, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        {
          bind: [
            outletId, startTime, endTime, days, Number(args.buyQty ?? 2), Number(args.freeQty ?? 1),
            args.applyToAllHappyHourItems !== false, args.freeItemId || null, args.isActive !== false,
          ],
        }
      );
      return { status: 'CREATED', happyHour: rows[0], message: `Happy Hour (${startTime}-${endTime}) configured.` };
    }
    case 'ADD_PROMO_RULE': {
      const name = String(args.promoName || '').trim();
      if (!name) return { status: 'NEEDS_INPUT', missingField: 'promoName', message: 'promoName is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO bill_value_promos (outlet_id, name, min_bill_amount, target_item_id, discount_value, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        {
          bind: [
            outletId, name, Number(args.minBillAmount ?? 500),
            args.targetItemId || null, Number(args.discountPercentage ?? 100), args.isActive !== false,
          ],
        }
      );
      return { status: 'CREATED', promoRule: rows[0], message: `Promotion Rule "${name}" created.` };
    }
    case 'SET_MAX_DISCOUNT': {
      const pct = Math.min(Math.max(Number(args.maxDiscountPercent ?? 100), 0), 100);
      await activeDb.query(
        `UPDATE system_settings SET outlet_max_discount_percent = $1, updated_at = CURRENT_TIMESTAMP WHERE outlet_id = $2`,
        { bind: [pct, outletId] }
      );
      return { status: 'UPDATED', maxManualDiscountPercent: pct, message: `Outlet Max Manual Discount set to ${pct}%.` };
    }
    default:
      throw new Error(`Unsupported action: ${action}`);
  }
}

export async function toolCreateTaxGroup(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const groupName = String(args?.groupName || '').trim();
  const components = Array.isArray(args?.components) ? args.components : [];
  if (!groupName || components.length === 0) {
    return { status: 'NEEDS_INPUT', missingFields: ['groupName', 'components'], message: 'groupName and at least one tax component are required.' };
  }
  const groupCode = String(args?.groupCode || groupName.replace(/[^a-zA-Z0-9]/g, '').toUpperCase().slice(0, 12) || 'TAX').trim();
  const totalRate = components.reduce((s: number, c: any) => s + Number(c.rate || 0), 0);

  const t = await activeDb.transaction();
  try {
    const [tgRows] = await activeDb.query(
      `INSERT INTO tax_groups (outlet_id, group_name, group_code, total_rate, is_tax_inclusive, is_active, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
      { bind: [outletId, groupName, groupCode, Number(totalRate.toFixed(2)), args?.isTaxInclusive === true], transaction: t }
    );
    const tg = tgRows[0];

    const createdComps: any[] = [];
    for (let i = 0; i < components.length; i++) {
      const c = components[i];
      const cname = String(c.componentName || `Tax ${i + 1}`).trim();
      const ccode = String(c.componentCode || cname.toUpperCase().replace(/[^A-Z0-9_]/g, '').slice(0, 10) || `TAX_${i + 1}`);
      const [cRows] = await activeDb.query(
        `INSERT INTO tax_group_components (tax_group_id, component_code, component_name, rate, calculation_order, calculation_type, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, 'PERCENTAGE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING *`,
        { bind: [tg.id, ccode, cname, Number(c.rate || 0), i + 1], transaction: t }
      );
      createdComps.push(cRows[0]);
    }

    await t.commit();
    return { status: 'CREATED', taxGroup: tg, components: createdComps, message: `Tax Group "${groupName}" (${totalRate}%) created.` };
  } catch (err) {
    await t.rollback();
    throw err;
  }
}

export async function toolCreateOutletBackup(db: any, scope: any, args: any) {
  const activeDb = getActiveDb(db);
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const [oRows] = await activeDb.query(`SELECT outlet_code FROM outlets WHERE id = $1 LIMIT 1`, { bind: [outletId] });
  const outletCode = oRows?.[0]?.outlet_code || `OUT_${outletId}`;

  const { TenantBackupService } = require('./tenantBackup.service');
  const result = await TenantBackupService.createFambakBackup(activeDb, {
    scope: 'OUTLET',
    outletId,
    outletCode,
    saveToDrive: true,
  });

  return {
    status: 'BACKUP_CREATED',
    outletId,
    outletCode,
    filename: result.filename,
    sizePretty: result.sizePretty,
    totalRecords: result.totalRecords,
    message: `Encrypted .fambak backup ${result.filename} (${result.sizePretty}, ${result.totalRecords} records) created and persisted to cloud_backup_snapshots.`,
  };
}

export async function toolManagePlugins(db: any, scope: any, args: any) {
  const fullDb = db?.models ? db : defaultDb;
  const outletId = resolveTargetOutlet(scope, args?.outletId);
  const action = String(args?.action || '').toUpperCase();
  const pluginManager = require('./plugin_manager.service');

  switch (action) {
    case 'LIST_INSTALLED':
      return { outletId, plugins: await pluginManager.getInstalledPlugins(fullDb, outletId) };
    case 'LIST_MARKETPLACE':
      return { outletId, plugins: await pluginManager.getMarketplaceCatalog(fullDb, outletId) };
    case 'INSTALL': {
      const pid = String(args?.pluginId || '').trim();
      if (!pid) return { status: 'NEEDS_INPUT', missingField: 'pluginId', message: 'pluginId is required to install.' };
      const data = await pluginManager.installPlugin(fullDb, outletId, pid);
      return { status: 'INSTALLED', plugin: data, message: `Plugin ${pid} installed.` };
    }
    case 'TOGGLE': {
      const pid = String(args?.pluginId || '').trim();
      if (!pid) return { status: 'NEEDS_INPUT', missingField: 'pluginId', message: 'pluginId is required to toggle.' };
      const data = await pluginManager.togglePlugin(fullDb, outletId, pid, args?.isActive !== false);
      return { status: 'UPDATED', plugin: data, message: `Plugin ${pid} ${args?.isActive !== false ? 'enabled' : 'disabled'}.` };
    }
    case 'DEPLOY_PLUGIN': {
      const pid = String(args?.pluginId || `plg_ai_${Date.now().toString().slice(-5)}`).trim();
      const pname = String(args?.name || '').trim();
      const code = String(args?.code || '').trim();
      if (!pname || !code) {
        return {
          status: 'NEEDS_INPUT',
          missingFields: [...(!pname ? ['name'] : []), ...(!code ? ['code'] : [])],
          message: 'Please provide plugin display name and TypeScript/JavaScript source code.',
        };
      }
      const isPublic = args?.isPublic === true;
      const data = await pluginManager.deployDeveloperPlugin(fullDb, outletId, {
        id: pid,
        name: pname,
        version: args?.version || '1.0.0',
        category: args?.category || 'Custom Automation',
        author: args?.author || 'AI MCP Studio',
        description: args?.description || `Deployed via MCP for ${pname}`,
        language: args?.language === 'javascript' ? 'javascript' : 'typescript',
        code,
        isPublic,
        targetOutletId: isPublic ? 0 : outletId,
      });
      return { status: 'DEPLOYED', plugin: data, message: `Plugin "${pname}" (${pid}) deployed successfully!` };
    }
    default:
      throw new Error(`Unsupported action: ${action}`);
  }
}
