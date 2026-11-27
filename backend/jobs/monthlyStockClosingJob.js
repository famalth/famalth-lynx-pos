"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.closeCompletedMonthsForOutlet = closeCompletedMonthsForOutlet;
exports.runMonthlyStockClosingAllOutlets = runMonthlyStockClosingAllOutlets;
exports.startMonthlyStockClosingJob = startMonthlyStockClosingJob;
const node_cron_1 = __importDefault(require("node-cron"));
const sequelize_1 = require("sequelize");

function getMonthKey(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    return `${y}-${m}`;
}
function getMonthBounds(monthKey) {
    const [yStr, mStr] = monthKey.split('-');
    const y = Number(yStr);
    const m = Number(mStr);
    const start = `${yStr}-${mStr}-01`;
    const nextDate = new Date(y, m, 1);
    const nextY = nextDate.getFullYear();
    const nextM = String(nextDate.getMonth() + 1).padStart(2, '0');
    return { start, nextStart: `${nextY}-${nextM}-01` };
}
function nextMonthKey(monthKey) {
    const [yStr, mStr] = monthKey.split('-');
    const d = new Date(Number(yStr), Number(mStr), 1);
    return getMonthKey(d);
}
function prevMonthKey(monthKey) {
    const [yStr, mStr] = monthKey.split('-');
    const d = new Date(Number(yStr), Number(mStr) - 2, 1);
    return getMonthKey(d);
}

/**
 * Closes all completed calendar months (up to previous month) for a single outlet.
 * Previous month's closing_qty becomes this month's opening_qty.
 */
async function closeCompletedMonthsForOutlet(db, outletId, transaction) {
    const activeDb = db.sequelize || db;
    const now = new Date();
    const lastCompletedMonth = getMonthKey(new Date(now.getFullYear(), now.getMonth() - 1, 1));
    const [latestRows] = await activeDb.query(`SELECT MAX(month_key) AS max_month FROM monthly_stock_closings WHERE outlet_id = :outletId;`, { replacements: { outletId }, type: sequelize_1.QueryTypes.SELECT, transaction }).catch(() => [null]);
    let startMonth = null;
    if (latestRows && latestRows.max_month) {
        startMonth = nextMonthKey(String(latestRows.max_month));
    }
    else {
        const [earliestRow] = await activeDb.query(`SELECT TO_CHAR(MIN(created_at), 'YYYY-MM') AS min_month FROM stock_ledger WHERE outlet_id = :outletId;`, { replacements: { outletId }, type: sequelize_1.QueryTypes.SELECT, transaction }).catch(() => [null]);
        if (earliestRow && earliestRow.min_month) {
            startMonth = String(earliestRow.min_month);
        }
        else {
            startMonth = lastCompletedMonth;
        }
    }
    if (!startMonth || startMonth > lastCompletedMonth) {
        return 0;
    }
    let closedMonths = 0;
    let cursor = startMonth;
    let safetyCounter = 0;
    while (cursor <= lastCompletedMonth && safetyCounter < 120) {
        safetyCounter++;
        const { start, nextStart } = getMonthBounds(cursor);
        const prevKey = prevMonthKey(cursor);
        await activeDb.query(`
      INSERT INTO monthly_stock_closings (
        outlet_id, item_code, month_key, opening_qty, total_in, total_out, closing_qty, closing_value, closed_at
      )
      SELECT
        im.outlet_id,
        im.item_code,
        :monthKey AS month_key,
        COALESCE(
          prev.closing_qty,
          COALESCE(im.opening_balance, 0) + COALESCE(prior_ledger.net_qty, 0)
        ) AS opening_qty,
        COALESCE(curr_ledger.total_in, 0) AS total_in,
        COALESCE(curr_ledger.total_out, 0) AS total_out,
        (
          COALESCE(
            prev.closing_qty,
            COALESCE(im.opening_balance, 0) + COALESCE(prior_ledger.net_qty, 0)
          )
          + COALESCE(curr_ledger.total_in, 0)
          - COALESCE(curr_ledger.total_out, 0)
        ) AS closing_qty,
        (
          (
            COALESCE(
              prev.closing_qty,
              COALESCE(im.opening_balance, 0) + COALESCE(prior_ledger.net_qty, 0)
            )
            + COALESCE(curr_ledger.total_in, 0)
            - COALESCE(curr_ledger.total_out, 0)
          ) * COALESCE(im.rate, 0)
        ) AS closing_value,
        CURRENT_TIMESTAMP AS closed_at
      FROM item_master im
      LEFT JOIN monthly_stock_closings prev
        ON prev.outlet_id = im.outlet_id
       AND prev.item_code = im.item_code
       AND prev.month_key = :prevKey
      LEFT JOIN (
        SELECT item_code, SUM(qty_in - qty_out) AS net_qty
        FROM stock_ledger
        WHERE outlet_id = :outletId AND created_at < :monthStart::date
        GROUP BY item_code
      ) prior_ledger ON prev.id IS NULL AND prior_ledger.item_code = im.item_code
      LEFT JOIN (
        SELECT item_code, SUM(qty_in) AS total_in, SUM(qty_out) AS total_out
        FROM stock_ledger
        WHERE outlet_id = :outletId AND created_at >= :monthStart::date AND created_at < :nextMonthStart::date
        GROUP BY item_code
      ) curr_ledger ON curr_ledger.item_code = im.item_code
      WHERE im.outlet_id = :outletId AND im.is_active = TRUE
      ON CONFLICT (outlet_id, item_code, month_key) DO NOTHING;
      `, {
            replacements: {
                outletId,
                monthKey: cursor,
                prevKey,
                monthStart: start,
                nextMonthStart: nextStart,
            },
            transaction,
        });
        closedMonths++;
        cursor = nextMonthKey(cursor);
    }
    return closedMonths;
}

async function runMonthlyStockClosingAllOutlets(propertyDb) {
    const activeDb = propertyDb.sequelize || propertyDb;
    const outlets = await activeDb.query(`SELECT id FROM outlets WHERE is_active = TRUE ORDER BY id ASC;`, { type: sequelize_1.QueryTypes.SELECT }).catch(() => []);
    for (const o of outlets) {
        try {
            const closed = await closeCompletedMonthsForOutlet(activeDb, Number(o.id));
            if (closed > 0) {
                console.log(`📦 [MONTHLY STOCK CLOSING] Closed ${closed} completed month(s) for outlet_id=${o.id}`);
            }
        }
        catch (err) {
            console.warn(`⚠️ [MONTHLY STOCK CLOSING] Failed for outlet_id=${o.id}: ${err.message}`);
        }
    }
}

function startMonthlyStockClosingJob(propertyDb) {
    const { withDistributedLock } = require('../utils/distributedLock');
    setTimeout(() => {
        withDistributedLock(propertyDb, 'monthly_stock_closing_job', async () => {
            await runMonthlyStockClosingAllOutlets(propertyDb);
        }).catch(() => { });
    }, 15000);
    node_cron_1.default.schedule('15 0 * * *', async () => {
        await withDistributedLock(propertyDb, 'monthly_stock_closing_job', async () => {
            await runMonthlyStockClosingAllOutlets(propertyDb);
        });
    });
    console.log('📦 Monthly Stock Closing Scheduler initialized (daily check at 00:15).');
}
