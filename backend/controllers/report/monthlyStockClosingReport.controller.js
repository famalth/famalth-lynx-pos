"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const sequelize_1 = require("sequelize");
const { resolveOutletScope } = require('../../utils/outletScopeHelper');
const { closeCompletedMonthsForOutlet } = require('../../jobs/monthlyStockClosingJob');

exports.getMonthlyStockClosingReport = async (req, res) => {
    try {
        const reqOutlet = req.query.outlet_id || req.query.outletId;
        const scope = await resolveOutletScope(req, reqOutlet);
        const activeDb = req.propertyDb.sequelize || req.propertyDb;
        for (const oid of scope.outletIds) {
            await closeCompletedMonthsForOutlet(activeDb, Number(oid)).catch(() => { });
        }
        const monthKey = String(req.query.month_key || req.query.monthKey || '').trim();
        const search = String(req.query.search || '').trim();
        const whereConditions = ['msc.outlet_id IN (:outletIds)'];
        const replacements = {
            outletIds: scope.outletIds,
        };
        if (monthKey && monthKey.toUpperCase() !== 'ALL') {
            whereConditions.push('msc.month_key = :monthKey');
            replacements.monthKey = monthKey;
        }
        if (search) {
            whereConditions.push('(msc.item_code ILIKE :search OR im.item_name ILIKE :search OR im.brand ILIKE :search)');
            replacements.search = `%${search}%`;
        }
        const rows = await activeDb.query(`
      SELECT
        msc.id,
        msc.outlet_id,
        msc.item_code,
        COALESCE(im.item_name, msc.item_code) AS item_name,
        COALESCE(im.brand, '') AS brand,
        COALESCE(im.unit, '') AS unit,
        COALESCE(im.item_group, '') AS category,
        msc.month_key,
        msc.opening_qty,
        msc.total_in,
        msc.total_out,
        msc.closing_qty,
        msc.closing_value,
        msc.closed_at
      FROM monthly_stock_closings msc
      LEFT JOIN item_master im
        ON im.item_code = msc.item_code
       AND im.outlet_id = msc.outlet_id
      WHERE ${whereConditions.join(' AND ')}
      ORDER BY msc.month_key DESC, COALESCE(im.item_name, msc.item_code) ASC
      `, { replacements, type: sequelize_1.QueryTypes.SELECT });
        const monthsRows = await activeDb.query(`
      SELECT DISTINCT month_key
      FROM monthly_stock_closings
      WHERE outlet_id IN (:outletIds)
      ORDER BY month_key DESC
      `, { replacements: { outletIds: scope.outletIds }, type: sequelize_1.QueryTypes.SELECT });
        res.json({
            success: true,
            data: rows,
            months: (monthsRows || []).map((m) => m.month_key),
        });
    }
    catch (err) {
        console.error('getMonthlyStockClosingReport error:', err);
        res.status(500).json({
            success: false,
            message: err.message || 'Failed to load monthly stock closing report',
        });
    }
};

exports.runMonthlyStockClosingNow = async (req, res) => {
    try {
        const reqOutlet = req.body?.outlet_id || req.query?.outlet_id;
        const scope = await resolveOutletScope(req, reqOutlet);
        const activeDb = req.propertyDb.sequelize || req.propertyDb;
        let totalClosed = 0;
        for (const oid of scope.outletIds) {
            totalClosed += await closeCompletedMonthsForOutlet(activeDb, Number(oid));
        }
        res.json({
            success: true,
            message: totalClosed > 0
                ? `Closed ${totalClosed} pending completed month(s).`
                : 'All completed months are already closed.',
            closedMonths: totalClosed,
        });
    }
    catch (err) {
        console.error('runMonthlyStockClosingNow error:', err);
        res.status(500).json({
            success: false,
            message: err.message || 'Failed to run monthly stock closing',
        });
    }
};

module.exports = exports;
exports.default = exports;
