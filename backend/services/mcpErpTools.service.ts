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
    description: 'Creates a new Employee in hr_employees with all required fields (auto-resolving/creating department & designation if names are provided).',
    inputSchema: {
      type: 'object',
      properties: {
        fullName: { type: 'string', description: 'Employee full name (required)' },
        employeeCode: { type: 'string', description: 'Optional employee code (auto-generated if omitted)' },
        mobile: { type: 'string' },
        email: { type: 'string' },
        gender: { type: 'string', enum: ['Male', 'Female', 'Other'] },
        departmentName: { type: 'string' },
        designationName: { type: 'string' },
        hireDate: { type: 'string', description: 'YYYY-MM-DD (defaults to today)' },
        baseSalary: { type: 'number', description: 'Monthly basic/base salary' },
        outletId: { type: 'number' },
      },
      required: ['fullName'],
    },
  },
  {
    name: 'create_master_record',
    description: 'Creates any ERP Master record (ITEM, CUSTOMER, SUPPLIER, EMPLOYEE, DEPARTMENT, DESIGNATION, TABLE, EXPENSE_CATEGORY) with required fields for the authorized outlet.',
    inputSchema: {
      type: 'object',
      properties: {
        masterType: {
          type: 'string',
          enum: ['ITEM', 'CUSTOMER', 'SUPPLIER', 'EMPLOYEE', 'DEPARTMENT', 'DESIGNATION', 'TABLE', 'EXPENSE_CATEGORY'],
          description: 'Type of master record to create',
        },
        data: {
          type: 'object',
          description: 'Fields for the master record (e.g. item_name, rate, retail_sale_price, unit, customer_name, customer_phone, table_name, capacity, name)',
        },
        outletId: { type: 'number' },
      },
      required: ['masterType', 'data'],
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
       VALUES ($1, $2, $3, $4, $5, $6, 0, 'PENDING', 'PENDING_APPROVAL', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id, po_no, po_date, total_amount, status, approval_status`,
      { bind: [outletId, poNo, args.manualNo || null, supplier.id, poDate, Number(grandTotal.toFixed(2))], transaction: t }
    );
    const poHeader = poInsert[0];

    for (const ri of resolvedItems) {
      await activeDb.query(
        `INSERT INTO purchase_order_items (po_id, item_id, item_code, item_name, brand, unit, qty, rate, tax, tax_amount, total_after_tax, amount, department, line_status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'PENDING')`,
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
       WHERE po.outlet_id = $1 AND po.approval_status = 'PENDING_APPROVAL'
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
     SET approval_status = 'APPROVED', status = 'APPROVED', approved_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
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
      `SELECT id FROM hr_departments WHERE outlet_id = $1 AND LOWER(TRIM(name)) = LOWER(TRIM($2)) LIMIT 1`,
      { bind: [outletId, deptName] }
    ).catch(() => [[]]);
    if (dRows?.[0]?.id) {
      deptId = Number(dRows[0].id);
    } else {
      const [dIns] = await activeDb.query(
        `INSERT INTO hr_departments (outlet_id, name, created_at, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id`,
        { bind: [outletId, deptName] }
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
        `INSERT INTO hr_designations (outlet_id, name, created_at, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id`,
        { bind: [outletId, desigName] }
      ).catch(() => [[]]);
      if (gIns?.[0]?.id) desigId = Number(gIns[0].id);
    }
  }

  const [rows] = await activeDb.query(
    `INSERT INTO hr_employees (outlet_id, employee_code, full_name, contact_email, mobile, gender, hire_date, base_salary, status, department_id, department, designation_id, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'ACTIVE', $9, $10, $11, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     RETURNING id, employee_code, full_name, mobile, contact_email, department, base_salary, status`,
    {
      bind: [
        outletId, empCode, fullName, args.email || null, args.mobile || null,
        args.gender || 'Male', hireDate, Number(args.baseSalary || 0), deptId, deptName, desigId,
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
      const itemName = String(d.item_name || d.itemName || d.name || '').trim();
      if (!itemName) return { status: 'NEEDS_INPUT', missingField: 'item_name', message: 'item_name is required.' };
      const rawItemCode = String(d.item_code || d.itemCode || '').trim().toUpperCase();
      const itemCode = rawItemCode || await getNextMasterCode(activeDb, 'item_master', 'item_code', outletId, 'ITM', 3);
      const [rows] = await activeDb.query(
        `INSERT INTO item_master (outlet_id, item_code, item_name, hsn_sac_code, item_group, brand, unit, barcode, rate, retail_sale_price, mrp, tax_percent, opening_balance, min_level, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, item_code, item_name, unit, rate, retail_sale_price, opening_balance`,
        {
          bind: [
            outletId, itemCode, itemName, d.hsn_sac_code || null, d.item_group || 'General',
            d.brand || '', d.unit || 'PCS', d.barcode || null, Number(d.rate || 0),
            Number(d.retail_sale_price || d.rate || 0), Number(d.mrp || d.retail_sale_price || 0),
            Number(d.tax_percent || 0), Number(d.opening_balance || 0), Number(d.min_level || 5),
          ],
        }
      );
      return { status: 'CREATED', item: rows[0], message: `Item ${itemName} (${itemCode}) created.` };
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
      const name = String(d.name || d.department_name || '').trim();
      if (!name) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Department name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_departments (outlet_id, name, created_at, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id, name`,
        { bind: [outletId, name] }
      );
      return { status: 'CREATED', department: rows[0], message: `Department ${name} created.` };
    }
    case 'DESIGNATION': {
      const name = String(d.name || d.designation_name || '').trim();
      if (!name) return { status: 'NEEDS_INPUT', missingField: 'name', message: 'Designation name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO hr_designations (outlet_id, name, created_at, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id, name`,
        { bind: [outletId, name] }
      );
      return { status: 'CREATED', designation: rows[0], message: `Designation ${name} created.` };
    }
    case 'TABLE': {
      const tname = String(d.table_name || d.tableName || d.name || '').trim();
      if (!tname) return { status: 'NEEDS_INPUT', missingField: 'table_name', message: 'table_name is required.' };
      const [rows] = await activeDb.query(
        `INSERT INTO restaurant_tables (outlet_id, table_name, capacity, status, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, 'AVAILABLE', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, table_name, capacity, status`,
        { bind: [outletId, tname, Number(d.capacity || 4)] }
      );
      return { status: 'CREATED', table: rows[0], message: `Table ${tname} created.` };
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
