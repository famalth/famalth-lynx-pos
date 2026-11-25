"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const { Op, Sequelize } = require('sequelize');
const { getOutletDateBounds } = require('../../utils/timezoneHelper');
const { resolveOutletScope } = require('../../utils/outletScopeHelper');
/**
 * Calculates stock valuation (Closing Stock) for an outlet
 */
async function getClosingStockValuation(req, inputOutletId) {
    try {
        const scope = await resolveOutletScope(req, inputOutletId);
        const items = await req.propertyDb.models.item_master.findAll({
            where: { outlet_id: scope.outlet_id, is_active: true },
            attributes: ['id', 'item_code', 'rate', 'retail_sale_price', 'mrp', 'opening_balance'],
            raw: true
        });
        if (!items || items.length === 0)
            return 0;
        const stockMovements = await req.propertyDb.models.stock_ledger.findAll({
            where: { outlet_id: scope.outlet_id },
            attributes: [
                'item_code',
                [Sequelize.fn('SUM', Sequelize.literal('qty_in - qty_out')), 'net_qty']
            ],
            group: ['item_code'],
            raw: true
        });
        const stockMap = new Map();
        stockMovements.forEach((s) => {
            stockMap.set(s.item_code, Number(s.net_qty || 0));
        });
        let totalValuation = 0;
        items.forEach((item) => {
            const movementQty = stockMap.get(item.item_code) || 0;
            const openingQty = Number(item.opening_balance || 0);
            const currentQty = Math.max(0, openingQty + movementQty);
            const costPrice = Number(item.rate || item.retail_sale_price || item.mrp || 0);
            totalValuation += currentQty * costPrice;
        });
        return Number(totalValuation.toFixed(2));
    }
    catch (err) {
        console.error('Error calculating closing stock valuation:', err);
        return 0;
    }
}
/**
 * Calculates completed sales revenue and itemized COGS for an outlet (matching Sales Report and Dashboard logic)
 */
async function getCompletedSalesMetrics(req, inputOutletId, startDateStr, endDateStr) {
    try {
        const outletTz = req.outletTimeZone || 'Asia/Kolkata';
        const scope = await resolveOutletScope(req, inputOutletId);
        const salesWhere = {
            status: { [Op.in]: ['COMPLETED', 'RETURNED'] },
            is_deleted: false,
            is_latest: true,
            outlet_id: scope.outlet_id
        };
        if (startDateStr && endDateStr) {
            const { startDate, endDate } = getOutletDateBounds(startDateStr, endDateStr, outletTz);
            if (startDate && endDate) {
                salesWhere.sale_date = {
                    [Op.between]: [startDate, endDate]
                };
            }
        }
        const sales = await req.propertyDb.models.sales_headers.findAll({
            where: salesWhere,
            include: [
                {
                    model: req.propertyDb.models.sales_items,
                    as: 'items',
                    include: [{
                            model: req.propertyDb.models.item_master,
                            as: 'item',
                            attributes: ['rate', 'retail_sale_price', 'item_group', 'sub_category', 'brand', 'is_tax_inclusive']
                        }]
                }
            ]
        });
        let totalTaxableRevenue = 0;
        let totalDiscounts = 0;
        let totalOutputTax = 0;
        let itemizedCogs = 0;
        let totalNetRevenue = 0;
        for (const sale of sales || []) {
            const items = sale.items || [];
            const subItems = items.filter(i => i.is_advance_free);
            const subscriptionTax = subItems.reduce((sum, i) => sum + Number(i.tax_amount || 0), 0);
            const subscriptionTaxable = subItems.reduce((sum, i) => sum + Number(i.taxable_amount || 0), 0);
            const subscriptionNet = subItems.reduce((sum, i) => {
                const dbNet = Number(i.net_amount || 0);
                if (dbNet > 0)
                    return sum + dbNet;
                const dbLineTotal = Number(i.line_total || 0);
                if (dbLineTotal > 0)
                    return sum + dbLineTotal;
                const isInclusive = i.tax_type === 'GST_INCLUSIVE' || i.is_tax_inclusive === true || i.isTaxInclusive === true;
                if (isInclusive) {
                    const amt = Number(i.amount || 0);
                    if (amt > 0)
                        return sum + amt;
                    const taxable = Number(i.taxable_amount || 0);
                    const taxAmt = Number(i.tax_amount || 0);
                    if (taxable > 0 && taxAmt > 0)
                        return sum + taxable + taxAmt;
                    return sum + taxable;
                }
                else {
                    const taxPct = Number(i.tax_percent || i.taxPercent || 0);
                    const taxAmt = Number(i.tax_amount || 0) > 0 ? Number(i.tax_amount || 0) : (Number(i.taxable_amount || 0) * (taxPct / 100));
                    const calcNet = Number(i.taxable_amount || 0) + taxAmt;
                    return sum + (calcNet > 0 ? calcNet : (Number(i.amount || 0) * (1 + taxPct / 100)));
                }
            }, 0);
            const isFullSubscriptionSale = sale.payment_mode === 'SUBSCRIPTION';
            const saleNetRevenue = Number(sale.net_amount || 0) + subscriptionNet;
            const saleBreakup = Array.isArray(sale.tax_breakup) ? sale.tax_breakup : [];
            let saleGst = 0;
            for (const tax of saleBreakup) {
                const code = String(tax.code || tax.label || '').toUpperCase();
                const amount = Number(tax.tax_amount || 0);
                if (code.includes('CGST') || code.includes('SGST') || code.includes('IGST') || code.includes('GST')) {
                    saleGst += amount;
                }
            }
            if (saleGst === 0 && Number(sale.total_tax || 0) > 0) {
                saleGst = Number(sale.total_tax || 0);
            }
            if (saleGst === 0 && subscriptionTax > 0) {
                saleGst = subscriptionTax;
            }
            let saleCogs = 0;
            let itemTaxableSum = 0;
            let saleItemDiscountSum = 0;
            for (const item of items) {
                const qty = Number(item.qty || 0);
                const lineAmount = Number(item.amount || 0);
                const dbLineNet = Number(item.net_amount || 0);
                const lineTaxableRaw = Number(item.taxable_amount || 0);
                const lineTax = Number(item.tax_amount || 0);
                let lineNet = dbLineNet;
                if (item.is_advance_free) {
                    const calculatedItemNet = lineTaxableRaw + lineTax;
                    lineNet = dbLineNet > 0 ? dbLineNet : (calculatedItemNet > 0 ? calculatedItemNet : lineAmount);
                }
                else {
                    const isTaxInclusive = !!(item.item?.is_tax_inclusive);
                    let effectiveDiscount = 0;
                    if (isTaxInclusive) {
                        effectiveDiscount = Math.max(lineAmount - dbLineNet, 0);
                    }
                    else {
                        const targetNetWithTax = dbLineNet > lineTaxableRaw ? dbLineNet : (lineTaxableRaw + lineTax);
                        effectiveDiscount = Math.max(lineAmount + lineTax - targetNetWithTax, 0);
                    }
                    saleItemDiscountSum += effectiveDiscount;
                }
                let lineTaxable = lineTaxableRaw;
                if (lineTaxable <= 0) {
                    lineTaxable = lineNet > 0 ? Math.max(0, lineNet - lineTax) : lineAmount;
                }
                itemTaxableSum += lineTaxable;
                const itemCost = Number(item.item?.rate || 0) * qty;
                saleCogs += itemCost;
            }
            const headerTaxable = Number(sale.taxable_amount || 0);
            let saleTaxableAmount = 0;
            if (saleNetRevenue > 0) {
                saleTaxableAmount = Math.max(0, Number((saleNetRevenue - saleGst).toFixed(2)));
            }
            else if (headerTaxable > 0) {
                saleTaxableAmount = headerTaxable;
            }
            else {
                const baseSaleTaxable = itemTaxableSum > 0 ? itemTaxableSum : 0;
                const rawTaxable = baseSaleTaxable > 0 ? Number(baseSaleTaxable.toFixed(2)) : Number(subscriptionTaxable.toFixed(2));
                const headerDisc = isFullSubscriptionSale ? 0 : Math.max(Number(sale.total_discount || 0) - subscriptionTaxable, 0);
                saleTaxableAmount = Math.max(0, Number((rawTaxable - headerDisc).toFixed(2)));
            }
            const headerDiscount = Number(sale.total_discount || 0);
            const saleTotalDiscount = isFullSubscriptionSale ? 0 : (headerDiscount > 0 ? headerDiscount : Number(saleItemDiscountSum.toFixed(2)));
            totalNetRevenue += saleNetRevenue;
            totalTaxableRevenue += saleTaxableAmount;
            totalDiscounts += saleTotalDiscount;
            totalOutputTax += saleGst;
            itemizedCogs += saleCogs;
        }
        const netSalesRevenue = Number(totalTaxableRevenue.toFixed(2));
        const salesDiscounts = Number(totalDiscounts.toFixed(2));
        const grossSalesRevenue = Number((netSalesRevenue + salesDiscounts).toFixed(2));
        return {
            netSalesRevenue,
            grossSalesRevenue,
            salesDiscounts,
            totalOutputTax: Number(totalOutputTax.toFixed(2)),
            itemizedCogs: Number(itemizedCogs.toFixed(2)),
            rawSalesNet: Number(totalNetRevenue.toFixed(2))
        };
    }
    catch (err) {
        console.error('Error in getCompletedSalesMetrics:', err);
        return {
            netSalesRevenue: 0,
            grossSalesRevenue: 0,
            salesDiscounts: 0,
            totalOutputTax: 0,
            itemizedCogs: 0,
            rawSalesNet: 0
        };
    }
}
/**
 * Classifies all business expenses into:
 * 1. Operating Expenses (Above EBITDA) - Day-to-day operational costs
 *    (Salaries, Store Rents, Utilities, Marketing, Logistics & Freight, Consumables)
 * 2. Non-Operating & Accounting Expenses (Below EBITDA)
 *    (Depreciation & Amortization [Non-Cash], Finance Costs / Interest [Cash], Tax Expenses [Cash])
 */
async function getExpensesSummaryAndCategories(req, inputOutletId, startDateStr, endDateStr) {
    let totalExpenses = 0;
    const categoryMap = new Map();
    const processedIds = new Set();
    const scope = await resolveOutletScope(req, inputOutletId);
    // Classification buckets
    let totalOperatingExpenses = 0;
    const operatingCategoryMap = new Map();
    let totalDepreciation = 0;
    const depreciationBreakdown = [];
    let totalFinanceCosts = 0;
    const financeCostBreakdown = [];
    let totalTaxExpense = 0;
    const taxExpenseBreakdown = [];
    const dateWhere = {};
    if (startDateStr && endDateStr) {
        dateWhere.txn_date = {
            [Op.between]: [
                new Date(`${startDateStr}T00:00:00.000Z`),
                new Date(`${endDateStr}T23:59:59.999Z`)
            ]
        };
    }
    const classifyAndAddExpense = (catNameInput, amt) => {
        if (!amt || amt <= 0)
            return;
        totalExpenses += amt;
        let catName = catNameInput || 'General Operating Expenses';
        const lower = catName.toLowerCase();
        // Standardize Operating category names
        if (lower.includes('office') || lower.includes('rent') || lower.includes('store rent') || lower.includes('shop rent')) {
            catName = 'Store Rents & Leases';
        }
        else if (lower.includes('electricity') || lower.includes('water') || lower.includes('utility') || lower.includes('power')) {
            catName = 'Electricity & Water Charges';
        }
        else if (lower.includes('salary') || lower.includes('salaries') || lower.includes('wages') || lower.includes('payroll') || lower.includes('staff')) {
            catName = 'Employee Salaries & Wages';
        }
        else if (lower.includes('marketing') || lower.includes('advertising') || lower.includes('promotion') || lower.includes('branding')) {
            catName = 'Marketing & Sales Promotion';
        }
        else if (lower.includes('logistics') || lower.includes('transport') || lower.includes('freight') || lower.includes('delivery') || lower.includes('dispatch') || lower.includes('fuel')) {
            catName = 'Logistics & Transportation';
        }
        else if (lower.includes('packaging') || lower.includes('printing') || lower.includes('stationery')) {
            catName = 'Packaging & Printing Costs';
        }
        categoryMap.set(catName, (categoryMap.get(catName) || 0) + amt);
        // Check if Below EBITDA: Depreciation, Finance Cost, or Tax
        if (lower.includes('depreciation') || lower.includes('amortisation') || lower.includes('amortization')) {
            totalDepreciation += amt;
            depreciationBreakdown.push({ category: catName, amount: amt, isNonCash: true });
        }
        else if (lower.includes('interest') || lower.includes('finance cost') || lower.includes('bank charge') || lower.includes('loan emi') || lower.includes('borrowing')) {
            totalFinanceCosts += amt;
            financeCostBreakdown.push({ category: catName, amount: amt, isCashExpense: true });
        }
        else if (lower.includes('income tax') || lower.includes('corporate tax') || lower.includes('advance tax') || lower.includes('tax expense')) {
            totalTaxExpense += amt;
            taxExpenseBreakdown.push({ category: catName, amount: amt, isCashExpense: true });
        }
        else {
            // Above EBITDA: Pure Operating Expense
            totalOperatingExpenses += amt;
            operatingCategoryMap.set(catName, (operatingCategoryMap.get(catName) || 0) + amt);
        }
    };
    // 1. Query expenses table
    if (req.propertyDb.models.expenses) {
        try {
            const expList = await req.propertyDb.models.expenses.findAll({
                where: { outlet_id: scope.outlet_id, ...dateWhere },
                include: [{
                        model: req.propertyDb.models.expense_categories,
                        as: 'category',
                        attributes: ['category_name', 'name']
                    }],
                raw: true,
                nest: true
            });
            expList.forEach((e) => {
                const amt = Number(e.net_payable_amount || e.base_amount || 0);
                const rawCat = e.category?.category_name || e.category?.name || 'General Operating Expenses';
                if (amt > 0) {
                    classifyAndAddExpense(rawCat, amt);
                    if (e.id)
                        processedIds.add(String(e.id));
                }
            });
        }
        catch (err) {
            console.error('Error reading expenses table:', err);
        }
    }
    // 2. Query expense_entries table (Legacy / Quick Entries)
    if (req.propertyDb.models.expense_entries) {
        try {
            const legacyList = await req.propertyDb.models.expense_entries.findAll({
                where: { outlet_id: scope.outlet_id, ...dateWhere },
                raw: true
            });
            legacyList.forEach((e) => {
                const amt = Number(e.amount || 0);
                const rawCat = e.category || 'General Operating Expenses';
                if (amt > 0 && (!e.id || !processedIds.has(String(e.id)))) {
                    classifyAndAddExpense(rawCat, amt);
                    if (e.id)
                        processedIds.add(String(e.id));
                }
            });
        }
        catch (err) {
            console.error('Error reading expense_entries table:', err);
        }
    }
    // 3. Query cash_ledger table for EXPENSE transactions
    if (req.propertyDb.models.cash_ledger) {
        try {
            const cashExpWhere = { transaction_type: 'EXPENSE', outlet_id: scope.outlet_id, ...dateWhere };
            const cashExpList = await req.propertyDb.models.cash_ledger.findAll({
                where: cashExpWhere,
                raw: true
            });
            cashExpList.forEach((e) => {
                const amt = Number(e.amount_out || 0);
                const isAlreadyProcessed = e.reference_id && processedIds.has(String(e.reference_id));
                if (amt > 0 && !isAlreadyProcessed) {
                    const rawCat = e.party_name ? String(e.party_name).trim() : 'General Operating Expenses';
                    classifyAndAddExpense(rawCat, amt);
                }
            });
        }
        catch (err) {
            console.error('Error reading cash_ledger expenses:', err);
        }
    }
    // 4. Also calculate non-cash Depreciation on Fixed Assets if not explicitly posted in expenses
    if (totalDepreciation === 0 && req.propertyDb.models.capital_assets) {
        try {
            const assets = await req.propertyDb.models.capital_assets.findAll({
                where: { outlet_id: scope.outlet_id },
                raw: true
            });
            assets.forEach((a) => {
                const cost = Number(a.purchase_cost || 0);
                const curr = Number(a.current_value || cost);
                const isFixed = a.asset_category !== 'INVESTMENT_SHARES' && a.asset_category !== 'PROPERTY_REAL_ESTATE';
                if (isFixed && cost > curr) {
                    const assetDep = cost - curr;
                    totalDepreciation += assetDep;
                    depreciationBreakdown.push({
                        category: `Depreciation on ${a.asset_name || 'Machinery/Equipment'}`,
                        amount: Number(assetDep.toFixed(2)),
                        isNonCash: true
                    });
                }
            });
        }
        catch (_) { }
    }
    // 5. Also calculate loan interest expense if active business loans exist and not explicitly posted
    if (totalFinanceCosts === 0 && req.propertyDb.models.business_loans) {
        try {
            const loans = await req.propertyDb.models.business_loans.findAll({
                where: { outlet_id: scope.outlet_id, status: 'ACTIVE' },
                raw: true
            });
            loans.forEach((l) => {
                const rem = Number(l.remaining_principal || 0);
                const rate = Number(l.interest_rate || 0);
                if (rem > 0 && rate > 0) {
                    // Approximate monthly interest cost: (Principal * Rate / 100) / 12
                    const estInterest = Number(((rem * (rate / 100)) / 12).toFixed(2));
                    if (estInterest > 0) {
                        totalFinanceCosts += estInterest;
                        financeCostBreakdown.push({
                            category: `Finance Interest on ${l.loan_name || 'Bank Loan'}`,
                            amount: estInterest,
                            isCashExpense: true
                        });
                    }
                }
            });
        }
        catch (_) { }
    }
    return {
        totalExpenses: Number(totalExpenses.toFixed(2)),
        categoryMap,
        totalOperatingExpenses: Number(totalOperatingExpenses.toFixed(2)),
        operatingCategoryMap,
        totalDepreciation: Number(totalDepreciation.toFixed(2)),
        depreciationBreakdown,
        totalFinanceCosts: Number(totalFinanceCosts.toFixed(2)),
        financeCostBreakdown,
        totalTaxExpense: Number(totalTaxExpense.toFixed(2)),
        taxExpenseBreakdown
    };
}
/**
 * Aggregates Direct / Indirect Income entries
 */
async function getIndirectIncomeTotal(req, inputOutletId, startDateStr, endDateStr) {
    let totalIncome = 0;
    const scope = await resolveOutletScope(req, inputOutletId);
    const dateWhere = {};
    if (startDateStr && endDateStr) {
        dateWhere.txn_date = {
            [Op.between]: [
                new Date(`${startDateStr}T00:00:00.000Z`),
                new Date(`${endDateStr}T23:59:59.999Z`)
            ]
        };
    }
    if (req.propertyDb.models.income_entries) {
        try {
            const inc = await req.propertyDb.models.income_entries.findOne({
                where: { outlet_id: scope.outlet_id, ...dateWhere },
                attributes: [[Sequelize.fn('SUM', Sequelize.col('amount')), 'total_inc']],
                raw: true
            });
            totalIncome += Number(inc?.total_inc || 0);
        }
        catch (_) { }
    }
    try {
        const cashIncWhere = { transaction_type: 'INCOME', outlet_id: scope.outlet_id, ...dateWhere };
        const cashInc = await req.propertyDb.models.cash_ledger.findOne({
            where: cashIncWhere,
            attributes: [[Sequelize.fn('SUM', Sequelize.col('amount_in')), 'total_inc']],
            raw: true
        });
        totalIncome += Number(cashInc?.total_inc || 0);
    }
    catch (_) { }
    return Number(totalIncome.toFixed(2));
}
/**
 * Aggregates Owner Drawings / Withdrawals
 */
async function getOwnerWithdrawalsTotal(req, inputOutletId) {
    let totalWithdrawals = 0;
    const scope = await resolveOutletScope(req, inputOutletId);
    if (req.propertyDb.models.withdrawals) {
        try {
            const w = await req.propertyDb.models.withdrawals.findOne({
                where: { outlet_id: scope.outlet_id },
                attributes: [[Sequelize.fn('SUM', Sequelize.col('amount')), 'total_w']],
                raw: true
            });
            totalWithdrawals += Number(w?.total_w || 0);
        }
        catch (_) { }
    }
    try {
        const cashWWhere = { transaction_type: 'WITHDRAWAL', outlet_id: scope.outlet_id };
        const cashW = await req.propertyDb.models.cash_ledger.findOne({
            where: cashWWhere,
            attributes: [[Sequelize.fn('SUM', Sequelize.col('amount_out')), 'total_w']],
            raw: true
        });
        totalWithdrawals += Number(cashW?.total_w || 0);
    }
    catch (_) { }
    return Number(totalWithdrawals.toFixed(2));
}
/**
 * Aggregates Customer Outstanding Dues (Sundry Debtors)
 */
async function getSundryDebtorsTotal(req, inputOutletId) {
    let totalDues = 0;
    const scope = await resolveOutletScope(req, inputOutletId);
    try {
        const sWhere = { status: 'COMPLETED', outlet_id: scope.outlet_id };
        const s = await req.propertyDb.models.sales_headers.findOne({
            where: sWhere,
            attributes: [[Sequelize.fn('SUM', Sequelize.col('balance_due')), 'total_due']],
            raw: true
        });
        totalDues = Number(s?.total_due || 0);
    }
    catch (_) { }
    return Number(totalDues.toFixed(2));
}
/**
 * Aggregates Customer Advances / Subscriptions
 */
async function getCustomerAdvancesTotal(req, inputOutletId) {
    let totalAdv = 0;
    const scope = await resolveOutletScope(req, inputOutletId);
    if (req.propertyDb.models.customer_advances) {
        try {
            const adv = await req.propertyDb.models.customer_advances.findOne({
                where: { outlet_id: scope.outlet_id },
                attributes: [[Sequelize.fn('SUM', Sequelize.col('available_amount')), 'total_adv']],
                raw: true
            });
            totalAdv = Number(adv?.total_adv || 0);
        }
        catch (_) { }
    }
    return Number(totalAdv.toFixed(2));
}
/**
 * Aggregates Capital Assets, Company Investments & Active Loans
 */
async function getCapitalAssetsAndLoansSummary(req, inputOutletId) {
    let totalAssetsVal = 0;
    let grossBlockVal = 0;
    let accumulatedDepreciationVal = 0;
    const assetGroupMap = new Map();
    const fixedAssetDetails = [];
    const investmentDetails = [];
    let totalLoanLiabilities = 0;
    const scope = await resolveOutletScope(req, inputOutletId);
    if (req.propertyDb.models.capital_assets) {
        try {
            const list = await req.propertyDb.models.capital_assets.findAll({
                where: { outlet_id: scope.outlet_id },
                raw: true
            });
            list.forEach((a) => {
                const cost = Number(a.purchase_cost || a.current_value || 0);
                const current = Number(a.current_value || a.purchase_cost || 0);
                const dep = Math.max(0, cost - current);
                let catName = 'Infrastructure & Fixed Assets';
                let isInvestment = false;
                if (a.asset_category === 'INVESTMENT_SHARES') {
                    catName = 'Investment in Other Companies / Shares';
                    isInvestment = true;
                }
                else if (a.asset_category === 'PROPERTY_REAL_ESTATE') {
                    catName = 'Property & Real Estate Investments';
                    isInvestment = true;
                }
                else if (a.asset_category === 'MACHINERY_EQUIPMENT') {
                    catName = 'Machinery & POS Equipment';
                }
                else if (a.asset_category === 'VEHICLE') {
                    catName = 'Commercial Vehicles';
                }
                else if (a.asset_category === 'COMPUTER_HARDWARE') {
                    catName = 'Computers & IT Hardware';
                }
                if (isInvestment) {
                    investmentDetails.push({ name: a.asset_name || catName, amount: current });
                }
                else {
                    grossBlockVal += cost;
                    accumulatedDepreciationVal += dep;
                    fixedAssetDetails.push({
                        name: a.asset_name || catName,
                        category: catName,
                        gross: cost,
                        depreciation: dep,
                        net: current
                    });
                }
                totalAssetsVal += current;
                assetGroupMap.set(catName, (assetGroupMap.get(catName) || 0) + current);
            });
        }
        catch (_) { }
    }
    if (req.propertyDb.models.business_loans) {
        try {
            const loans = await req.propertyDb.models.business_loans.findAll({
                where: { outlet_id: scope.outlet_id, status: 'ACTIVE' },
                raw: true
            });
            loans.forEach((l) => {
                totalLoanLiabilities += Number(l.remaining_principal || 0);
            });
        }
        catch (_) { }
    }
    return {
        totalAssetsVal: Number(totalAssetsVal.toFixed(2)),
        grossBlockVal: Number(grossBlockVal.toFixed(2)),
        accumulatedDepreciationVal: Number(accumulatedDepreciationVal.toFixed(2)),
        netFixedAssetsVal: Number(Math.max(0, grossBlockVal - accumulatedDepreciationVal).toFixed(2)),
        investmentsVal: Number(investmentDetails.reduce((s, i) => s + i.amount, 0).toFixed(2)),
        fixedAssetDetails,
        investmentDetails,
        assetGroupMap,
        totalLoanLiabilities: Number(totalLoanLiabilities.toFixed(2))
    };
}
function parseDateBoundsFromQuery(req) {
    const { startDate, endDate, period } = req.query;
    let startDateStr = startDate || null;
    let endDateStr = endDate || null;
    if (!startDateStr && !endDateStr && period) {
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const todayStr = `${year}-${month}-${day}`;
        const periodKey = String(period).toLowerCase();
        if (periodKey === 'today') {
            startDateStr = todayStr;
            endDateStr = todayStr;
        }
        else if (periodKey === 'yesterday') {
            const yest = new Date(now.getTime() - 86400000);
            const yY = yest.getFullYear();
            const yM = String(yest.getMonth() + 1).padStart(2, '0');
            const yD = String(yest.getDate()).padStart(2, '0');
            startDateStr = `${yY}-${yM}-${yD}`;
            endDateStr = startDateStr;
        }
        else if (periodKey === 'this_week') {
            const dayOfWeek = now.getDay();
            const diff = (dayOfWeek + 6) % 7;
            const startWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() - diff);
            const wY = startWeek.getFullYear();
            const wM = String(startWeek.getMonth() + 1).padStart(2, '0');
            const wD = String(startWeek.getDate()).padStart(2, '0');
            startDateStr = `${wY}-${wM}-${wD}`;
            endDateStr = todayStr;
        }
        else if (periodKey === 'this_month') {
            startDateStr = `${year}-${month}-01`;
            endDateStr = todayStr;
        }
        else if (periodKey === 'this_year') {
            startDateStr = `${year}-01-01`;
            endDateStr = todayStr;
        }
    }
    return { startDateStr, endDateStr };
}
exports.getTrialBalance = async (req, res) => {
    try {
        const reqOutlet = req.query.outlet_id || req.query.outletId;
        const scope = await resolveOutletScope(req, reqOutlet);
        const { startDateStr, endDateStr } = parseDateBoundsFromQuery(req);
        // 1. Fetch custom accounts from Chart of Accounts
        const customAccounts = await req.propertyDb.models.chart_of_accounts.findAll({
            where: { outlet_id: scope.outlet_id, is_active: true }
        });
        // 2. Cash Drawer Balance (Physical Cash ONLY)
        const cashWhere = {
            outlet_id: scope.outlet_id,
            [Op.or]: [
                { payment_method: 'CASH' },
                { payment_method: null },
                { transaction_type: 'SALE_CASH' }
            ]
        };
        if (startDateStr && endDateStr) {
            cashWhere.txn_date = {
                [Op.between]: [
                    new Date(`${startDateStr}T00:00:00.000Z`),
                    new Date(`${endDateStr}T23:59:59.999Z`)
                ]
            };
        }
        const cashSummary = await req.propertyDb.models.cash_ledger.findOne({
            where: cashWhere,
            attributes: [
                [Sequelize.fn('SUM', Sequelize.col('amount_in')), 'total_in'],
                [Sequelize.fn('SUM', Sequelize.col('amount_out')), 'total_out']
            ],
            raw: true
        });
        const cashIn = Number(cashSummary?.total_in || 0);
        const cashOut = Number(cashSummary?.total_out || 0);
        const cashBalance = cashIn - cashOut;
        // 3. Bank Accounts Total
        const banks = await req.propertyDb.models.bank_accounts.findAll({
            where: { outlet_id: scope.outlet_id, is_active: true }
        });
        const totalBankBalance = banks.reduce((sum, b) => sum + Number(b.current_balance || 0), 0);
        // 4. Sales Revenue & Output Tax
        const { netSalesRevenue, totalOutputTax } = await getCompletedSalesMetrics(req, reqOutlet, startDateStr, endDateStr);
        // 5. Purchases (GRN) & Input Taxes
        const grnWhere = { outlet_id: scope.outlet_id };
        if (startDateStr && endDateStr) {
            grnWhere.receipt_date = {
                [Op.between]: [startDateStr, endDateStr]
            };
        }
        const grnSummary = await req.propertyDb.models.goods_receipts.findOne({
            where: grnWhere,
            attributes: [
                [Sequelize.fn('SUM', Sequelize.col('total_amount')), 'total_amount'],
                [Sequelize.fn('SUM', Sequelize.col('total_gst')), 'total_tax'],
                [Sequelize.fn('SUM', Sequelize.col('net_amount')), 'net_amount']
            ],
            raw: true
        });
        const totalGrnSubtotal = Number(grnSummary?.total_amount || 0);
        const totalInputTax = Number(grnSummary?.total_tax || 0);
        const totalGrnNet = Number(grnSummary?.net_amount || 0);
        const netPurchases = totalGrnSubtotal > 0 ? totalGrnSubtotal : Math.max(0, totalGrnNet - totalInputTax);
        // 6. Operating Expenses
        const { totalExpenses } = await getExpensesSummaryAndCategories(req, reqOutlet, startDateStr, endDateStr);
        // 7. Customer & Supplier Balances
        const sundryDebtors = await getSundryDebtorsTotal(req, reqOutlet);
        const customerAdvances = await getCustomerAdvancesTotal(req, reqOutlet);
        let sundryCreditors = 0;
        try {
            const supplierBillsSummary = await req.propertyDb.models.supplier_bills.findOne({
                where: { outlet_id: scope.outlet_id },
                attributes: [
                    [Sequelize.fn('SUM', Sequelize.literal('bill_amount - paid_amount')), 'total_payables']
                ],
                raw: true
            });
            sundryCreditors = Math.max(0, Number(supplierBillsSummary?.total_payables || 0));
        }
        catch (_) { }
        // 8. Capital Assets & Loans
        const { assetGroupMap, totalLoanLiabilities } = await getCapitalAssetsAndLoansSummary(req, reqOutlet);
        // Build Exact Trial Balance Account Rows
        const rows = [
            {
                account_name: 'Main Cash Drawer',
                group_name: 'Current Assets',
                nature: 'ASSET',
                debit: cashBalance >= 0 ? Number(cashBalance.toFixed(2)) : 0,
                credit: cashBalance < 0 ? Number(Math.abs(cashBalance).toFixed(2)) : 0
            },
            {
                account_name: 'Bank Accounts Total',
                group_name: 'Bank Accounts',
                nature: 'ASSET',
                debit: totalBankBalance >= 0 ? Number(totalBankBalance.toFixed(2)) : 0,
                credit: totalBankBalance < 0 ? Number(Math.abs(totalBankBalance).toFixed(2)) : 0
            },
            {
                account_name: 'Purchases Account',
                group_name: 'Direct Expenses',
                nature: 'EXPENSE',
                debit: Number(netPurchases.toFixed(2)),
                credit: 0
            },
            {
                account_name: 'Input Tax (ITC) Account',
                group_name: 'Duties & Taxes (Assets)',
                nature: 'ASSET',
                debit: Number(totalInputTax.toFixed(2)),
                credit: 0
            },
            {
                account_name: 'Sales Revenue Account',
                group_name: 'Sales Income',
                nature: 'REVENUE',
                debit: 0,
                credit: Number(netSalesRevenue.toFixed(2))
            },
            {
                account_name: 'Output Tax Payable Account',
                group_name: 'Duties & Taxes (Liabilities)',
                nature: 'LIABILITY',
                debit: 0,
                credit: Number(totalOutputTax.toFixed(2))
            },
            {
                account_name: 'Operating Expenses Account',
                group_name: 'Indirect Expenses',
                nature: 'EXPENSE',
                debit: Number(totalExpenses.toFixed(2)),
                credit: 0
            }
        ];
        // Add Investments & Capital Assets to Trial Balance
        assetGroupMap.forEach((val, groupName) => {
            if (val > 0) {
                rows.push({
                    account_name: groupName,
                    group_name: 'Fixed Assets / Investments',
                    nature: 'ASSET',
                    debit: Number(val.toFixed(2)),
                    credit: 0
                });
            }
        });
        if (totalLoanLiabilities > 0) {
            rows.push({
                account_name: 'Bank / Business Loans Outstanding',
                group_name: 'Loans & Borrowings',
                nature: 'LIABILITY',
                debit: 0,
                credit: Number(totalLoanLiabilities.toFixed(2))
            });
        }
        if (sundryDebtors > 0) {
            rows.push({
                account_name: 'Sundry Debtors (Customer Dues)',
                group_name: 'Current Assets',
                nature: 'ASSET',
                debit: Number(sundryDebtors.toFixed(2)),
                credit: 0
            });
        }
        if (sundryCreditors > 0) {
            rows.push({
                account_name: 'Sundry Creditors (Vendor Dues)',
                group_name: 'Current Liabilities',
                nature: 'LIABILITY',
                debit: 0,
                credit: Number(sundryCreditors.toFixed(2))
            });
        }
        if (customerAdvances > 0) {
            rows.push({
                account_name: 'Customer Advances / Subscriptions',
                group_name: 'Current Liabilities',
                nature: 'LIABILITY',
                debit: 0,
                credit: Number(customerAdvances.toFixed(2))
            });
        }
        // Custom COA Accounts
        customAccounts.forEach(acc => {
            const deb = Number(acc.opening_debit || 0) + (acc.nature === 'ASSET' || acc.nature === 'EXPENSE' ? Number(acc.current_balance || 0) : 0);
            const cred = Number(acc.opening_credit || 0) + (acc.nature === 'REVENUE' || acc.nature === 'LIABILITY' || acc.nature === 'EQUITY' ? Number(acc.current_balance || 0) : 0);
            if (deb > 0 || cred > 0) {
                rows.push({
                    account_name: acc.account_name,
                    group_name: acc.group_name,
                    nature: acc.nature,
                    debit: Number(deb.toFixed(2)),
                    credit: Number(cred.toFixed(2))
                });
            }
        });
        // Compute Trial Balance Rule Equation
        let sumDebit = rows.reduce((s, r) => s + r.debit, 0);
        let sumCredit = rows.reduce((s, r) => s + r.credit, 0);
        const capitalDiff = sumDebit - sumCredit;
        const equityDebit = capitalDiff < 0 ? Number(Math.abs(capitalDiff).toFixed(2)) : 0;
        const equityCredit = capitalDiff >= 0 ? Number(capitalDiff.toFixed(2)) : 0;
        rows.push({
            account_name: 'Capital / Proprietor Equity Account',
            group_name: 'Capital Account',
            nature: 'EQUITY',
            debit: equityDebit,
            credit: equityCredit
        });
        const finalTotalDebit = Number((sumDebit + equityDebit).toFixed(2));
        const finalTotalCredit = Number((sumCredit + equityCredit).toFixed(2));
        res.json({
            success: true,
            summary: {
                totalDebit: finalTotalDebit,
                totalCredit: finalTotalCredit,
                difference: Number(Math.abs(finalTotalDebit - finalTotalCredit).toFixed(2)),
                isBalanced: Math.abs(finalTotalDebit - finalTotalCredit) < 0.01
            },
            data: rows
        });
    }
    catch (error) {
        console.error('getTrialBalance error:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};
exports.getProfitAndLoss = async (req, res) => {
    try {
        const reqOutlet = req.query.outlet_id || req.query.outletId;
        const scope = await resolveOutletScope(req, reqOutlet);
        const { startDateStr, endDateStr } = parseDateBoundsFromQuery(req);
        // Sales Revenue & COGS Metrics (matching Dashboard)
        const { netSalesRevenue, grossSalesRevenue, salesDiscounts, itemizedCogs } = await getCompletedSalesMetrics(req, reqOutlet, startDateStr, endDateStr);
        // Purchases & GRN
        const grnWhere = { outlet_id: scope.outlet_id };
        if (startDateStr && endDateStr) {
            grnWhere.receipt_date = {
                [Op.between]: [
                    startDateStr,
                    endDateStr
                ]
            };
        }
        const grn = await req.propertyDb.models.goods_receipts.findOne({
            where: grnWhere,
            attributes: [
                [Sequelize.fn('SUM', Sequelize.col('total_amount')), 'total_grn'],
                [Sequelize.fn('SUM', Sequelize.col('total_gst')), 'total_tax'],
                [Sequelize.fn('SUM', Sequelize.col('net_amount')), 'net_amount']
            ],
            raw: true
        });
        const grnSubTotal = Number(grn?.total_grn || 0);
        const grnTax = Number(grn?.total_tax || 0);
        const grnNet = Number(grn?.net_amount || 0);
        const purchasesNet = grnSubTotal > 0 ? grnSubTotal : Math.max(0, grnNet - grnTax);
        const openingStock = 0.00;
        const directFreight = 0.00;
        // COGS (Itemized COGS = Sold Quantity x Item Purchase Cost Rate, matching Dashboard formula)
        const cogs = itemizedCogs;
        const closingStockReal = await getClosingStockValuation(req, reqOutlet);
        const closingStock = itemizedCogs > 0
            ? Number(Math.max(0, openingStock + purchasesNet + directFreight - cogs).toFixed(2))
            : closingStockReal;
        // Gross Profit / Gross Loss:
        // Gross Profit = Net Sales Revenue (Excl. Tax) - COGS (when Net Revenue >= COGS)
        // Gross Loss = COGS - Net Sales Revenue (Excl. Tax) (when COGS > Net Revenue)
        const grossMarginValue = Number((netSalesRevenue - cogs).toFixed(2));
        const grossProfit = grossMarginValue >= 0 ? grossMarginValue : 0;
        const grossLoss = grossMarginValue < 0 ? Math.abs(grossMarginValue) : 0;
        const grossProfitMargin = netSalesRevenue > 0 ? Number(((grossMarginValue / netSalesRevenue) * 100).toFixed(2)) : 0.0;
        // Classified Expenses: Above EBITDA vs. Below EBITDA
        const { totalExpenses, categoryMap, totalOperatingExpenses, operatingCategoryMap, totalDepreciation, depreciationBreakdown, totalFinanceCosts, financeCostBreakdown, totalTaxExpense, taxExpenseBreakdown } = await getExpensesSummaryAndCategories(req, reqOutlet, startDateStr, endDateStr);
        // Operating Expenses Breakdown (Above EBITDA)
        const operatingExpenseBreakdown = [];
        operatingCategoryMap.forEach((amt, catName) => {
            operatingExpenseBreakdown.push({
                category: catName,
                amount: Number(amt.toFixed(2))
            });
        });
        // Ensure primary standard categories are represented
        const standardOperatingCats = [
            'Employee Salaries & Wages',
            'Store Rents & Leases',
            'Electricity & Water Charges',
            'Marketing & Sales Promotion',
            'Logistics & Transportation',
            'Packaging & Printing Costs'
        ];
        standardOperatingCats.forEach(cat => {
            if (!operatingCategoryMap.has(cat)) {
                operatingExpenseBreakdown.push({ category: cat, amount: 0.00 });
            }
        });
        operatingExpenseBreakdown.sort((a, b) => b.amount - a.amount);
        // Operating Income
        const indirectIncome = await getIndirectIncomeTotal(req, reqOutlet, startDateStr, endDateStr);
        const totalOperatingIncome = Number((grossProfit + indirectIncome).toFixed(2));
        // 1. EBITDA (Earnings Before Interest, Tax, Depreciation & Amortization)
        // EBITDA = Total Operating Income - Operating Expenses (Above EBITDA)
        const ebitdaValue = Number((totalOperatingIncome - totalOperatingExpenses).toFixed(2));
        const ebitda = ebitdaValue;
        const isEbitdaPositive = ebitdaValue >= 0;
        const ebitdaMargin = netSalesRevenue > 0 ? Number(((ebitdaValue / netSalesRevenue) * 100).toFixed(2)) : 0.0;
        // 2. EBIT (Operating Profit / Earnings Before Interest & Tax)
        // EBIT = EBITDA - Depreciation & Amortization (Non-Cash Expense)
        const ebitValue = Number((ebitdaValue - totalDepreciation).toFixed(2));
        const ebit = ebitValue;
        const isEbitPositive = ebitValue >= 0;
        const ebitMargin = netSalesRevenue > 0 ? Number(((ebitValue / netSalesRevenue) * 100).toFixed(2)) : 0.0;
        // 3. EBT (Profit Before Tax / Earnings Before Tax)
        // EBT = EBIT - Finance Costs (Interest Expense) + Non-Operating Income
        const nonOperatingIncome = 0.00;
        const ebtValue = Number((ebitValue - totalFinanceCosts + nonOperatingIncome).toFixed(2));
        const ebt = ebtValue;
        const isEbtPositive = ebtValue >= 0;
        // 4. Tax Expenses (Corporate Income Tax - Cash Expense)
        const taxExpense = totalTaxExpense;
        // 5. EAT / Net Profit After Tax (PAT - Bottom Line Value for Shareholders)
        // Net Profit = EBT - Tax Expense
        const netProfitMarginValue = Number((ebtValue - taxExpense).toFixed(2));
        const netProfit = netProfitMarginValue >= 0 ? netProfitMarginValue : 0;
        const netLoss = netProfitMarginValue < 0 ? Math.abs(netProfitMarginValue) : 0;
        const isNetProfit = netProfitMarginValue >= 0;
        const netProfitMargin = netSalesRevenue > 0 ? Number(((netProfitMarginValue / netSalesRevenue) * 100).toFixed(2)) : 0.0;
        res.json({
            success: true,
            data: {
                tradingAccount: {
                    totalRevenue: Number(grossSalesRevenue.toFixed(2)),
                    salesDiscounts: Number(salesDiscounts.toFixed(2)),
                    netSalesRevenue: Number(netSalesRevenue.toFixed(2)),
                    openingStock,
                    purchases: Number(purchasesNet.toFixed(2)),
                    directFreight,
                    closingStock,
                    costOfGoodsSold: cogs,
                    grossProfit,
                    grossLoss,
                    isGrossProfit: grossMarginValue >= 0,
                    grossProfitMargin
                },
                // Part 1: Operating Performance (Above EBITDA)
                operatingAccount: {
                    grossProfit,
                    indirectIncome,
                    totalOperatingIncome,
                    operatingExpenses: totalOperatingExpenses,
                    expenseBreakdown: operatingExpenseBreakdown,
                    ebitda,
                    isEbitdaPositive,
                    ebitdaMargin
                },
                // Part 2: Non-Operating & Accounting Expenses (Below EBITDA)
                nonOperatingAccount: {
                    ebitda,
                    depreciation: {
                        amount: totalDepreciation,
                        isNonCash: true,
                        breakdown: depreciationBreakdown
                    },
                    ebit,
                    isEbitPositive,
                    ebitMargin,
                    financeCosts: {
                        amount: totalFinanceCosts,
                        isCashExpense: true,
                        breakdown: financeCostBreakdown
                    },
                    nonOperatingIncome,
                    ebt,
                    isEbtPositive,
                    taxExpense: {
                        amount: taxExpense,
                        isCashExpense: true,
                        breakdown: taxExpenseBreakdown
                    },
                    netProfit,
                    netLoss,
                    isNetProfit,
                    netProfitMargin
                },
                // Backward-compatible structure
                profitAndLossAccount: {
                    grossProfit,
                    grossLoss,
                    indirectIncome,
                    totalOperatingIncome,
                    operatingExpenses: totalOperatingExpenses,
                    expenseBreakdown: operatingExpenseBreakdown,
                    ebitda,
                    ebit,
                    depreciation: totalDepreciation,
                    financeCosts: totalFinanceCosts,
                    taxExpense,
                    netProfit,
                    netLoss,
                    isNetProfit
                },
                formulaMetrics: {
                    grossSalesRevenue: Number(grossSalesRevenue.toFixed(2)),
                    salesDiscounts: Number(salesDiscounts.toFixed(2)),
                    netSalesRevenue: Number(netSalesRevenue.toFixed(2)),
                    cogs: Number(cogs.toFixed(2)),
                    grossProfit: Number(grossProfit.toFixed(2)),
                    operatingExpenses: Number(totalOperatingExpenses.toFixed(2)),
                    ebitda: Number(ebitda.toFixed(2)),
                    depreciation: Number(totalDepreciation.toFixed(2)),
                    ebit: Number(ebit.toFixed(2)),
                    financeCosts: Number(totalFinanceCosts.toFixed(2)),
                    ebt: Number(ebt.toFixed(2)),
                    taxExpense: Number(taxExpense.toFixed(2)),
                    netProfit: Number(netProfit.toFixed(2)),
                    netLoss: Number(netLoss.toFixed(2))
                }
            }
        });
    }
    catch (error) {
        console.error('getProfitAndLoss error:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};
exports.getBalanceSheet = async (req, res) => {
    try {
        const reqOutlet = req.query.outlet_id || req.query.outletId;
        const scope = await resolveOutletScope(req, reqOutlet);
        const { startDateStr, endDateStr } = parseDateBoundsFromQuery(req);
        // Cash in Hand (Physical Cash ONLY)
        const cashWhere = {
            outlet_id: scope.outlet_id,
            [Op.or]: [
                { payment_method: 'CASH' },
                { payment_method: null },
                { transaction_type: 'SALE_CASH' }
            ]
        };
        if (startDateStr && endDateStr) {
            cashWhere.txn_date = {
                [Op.between]: [
                    new Date(`${startDateStr}T00:00:00.000Z`),
                    new Date(`${endDateStr}T23:59:59.999Z`)
                ]
            };
        }
        const cashSummary = await req.propertyDb.models.cash_ledger.findOne({
            where: cashWhere,
            attributes: [
                [Sequelize.fn('SUM', Sequelize.col('amount_in')), 'total_in'],
                [Sequelize.fn('SUM', Sequelize.col('amount_out')), 'total_out']
            ],
            raw: true
        });
        const cashIn = Number(cashSummary?.total_in || 0);
        const cashOut = Number(cashSummary?.total_out || 0);
        const cashBalance = Math.max(0, cashIn - cashOut);
        // Bank Balances
        const banks = await req.propertyDb.models.bank_accounts.findAll({
            where: { outlet_id: scope.outlet_id, is_active: true }
        });
        const bankBalance = banks.reduce((sum, b) => sum + Number(b.current_balance || 0), 0);
        // Sales & Output Tax
        const { netSalesRevenue: salesNet, totalOutputTax: outputGstPayable, itemizedCogs } = await getCompletedSalesMetrics(req, reqOutlet, startDateStr, endDateStr);
        // GRN & Input Tax
        const grnWhere = { outlet_id: scope.outlet_id };
        if (startDateStr && endDateStr) {
            grnWhere.receipt_date = {
                [Op.between]: [startDateStr, endDateStr]
            };
        }
        const grnSummary = await req.propertyDb.models.goods_receipts.findOne({
            where: grnWhere,
            attributes: [
                [Sequelize.fn('SUM', Sequelize.col('total_gst')), 'total_input_tax'],
                [Sequelize.fn('SUM', Sequelize.col('total_amount')), 'total_grn'],
                [Sequelize.fn('SUM', Sequelize.col('net_amount')), 'net_amount']
            ],
            raw: true
        });
        const inputGstCredit = Number(grnSummary?.total_input_tax || 0);
        const grnSubTotal = Number(grnSummary?.total_grn || 0);
        const grnNet = Number(grnSummary?.net_amount || 0);
        const purchasesNet = grnSubTotal > 0 ? grnSubTotal : Math.max(0, grnNet - inputGstCredit);
        // Customer & Supplier Dues
        const sundryDebtors = await getSundryDebtorsTotal(req, reqOutlet);
        const customerAdvances = await getCustomerAdvancesTotal(req, reqOutlet);
        let sundryCreditors = 0;
        try {
            const supplierBillsSummary = await req.propertyDb.models.supplier_bills.findOne({
                where: { outlet_id: scope.outlet_id },
                attributes: [
                    [Sequelize.fn('SUM', Sequelize.literal('bill_amount - paid_amount')), 'total_payables']
                ],
                raw: true
            });
            sundryCreditors = Math.max(0, Number(supplierBillsSummary?.total_payables || 0));
        }
        catch (_) { }
        // Closing Stock Valuation
        const closingStock = await getClosingStockValuation(req, reqOutlet);
        // Classified Expenses & Corporate P&L Bottom Line
        const { totalOperatingExpenses, totalDepreciation, totalFinanceCosts, totalTaxExpense } = await getExpensesSummaryAndCategories(req, reqOutlet, startDateStr, endDateStr);
        const indirectIncome = await getIndirectIncomeTotal(req, reqOutlet, startDateStr, endDateStr);
        // Net Profit Calculation (Corporate EBITDA / EBIT / EBT flow)
        const cogs = itemizedCogs > 0 ? itemizedCogs : Math.max(0, purchasesNet - closingStock);
        const grossProfit = salesNet - cogs;
        const totalOperatingIncome = Number((grossProfit + indirectIncome).toFixed(2));
        const ebitda = Number((totalOperatingIncome - totalOperatingExpenses).toFixed(2));
        const ebit = Number((ebitda - totalDepreciation).toFixed(2));
        const ebt = Number((ebit - totalFinanceCosts).toFixed(2));
        const netProfit = Number((ebt - totalTaxExpense).toFixed(2));
        // Capital Assets, Investments & Loans
        const { grossBlockVal, accumulatedDepreciationVal, netFixedAssetsVal, investmentsVal, fixedAssetDetails, investmentDetails, totalLoanLiabilities } = await getCapitalAssetsAndLoansSummary(req, reqOutlet);
        // ==========================================
        // 1. ASSETS (Application of Funds)
        // ==========================================
        const nonCurrentAssetItems = [];
        fixedAssetDetails.forEach(f => {
            nonCurrentAssetItems.push({
                name: `${f.name} (Gross: ₹${f.gross.toFixed(2)} - Dep: ₹${f.depreciation.toFixed(2)})`,
                category: f.category,
                grossAmount: f.gross,
                depreciation: f.depreciation,
                amount: f.net,
                isFixedAsset: true
            });
        });
        investmentDetails.forEach(inv => {
            nonCurrentAssetItems.push({
                name: inv.name,
                category: 'Investments',
                amount: inv.amount,
                isInvestment: true
            });
        });
        const totalNonCurrentAssets = Number((netFixedAssetsVal + investmentsVal).toFixed(2));
        const currentAssetItems = [
            { name: 'Closing Stock (Unsold Goods & Raw Materials)', amount: Number(closingStock.toFixed(2)), category: 'Inventories' },
            { name: 'Trade Receivables (Sundry Debtors)', amount: Number(sundryDebtors.toFixed(2)), category: 'Receivables' },
            { name: 'Cash in Hand (Physical Drawer)', amount: Number(cashBalance.toFixed(2)), category: 'Cash & Equivalents' },
            { name: 'Bank Balances (Active Accounts)', amount: Number(bankBalance.toFixed(2)), category: 'Cash & Equivalents' },
            { name: 'Input Tax Credit (ITC Receivable)', amount: Number(inputGstCredit.toFixed(2)), category: 'Tax Credits' }
        ];
        const totalCurrentAssets = Number(currentAssetItems.reduce((s, a) => s + a.amount, 0).toFixed(2));
        const totalAssets = Number((totalNonCurrentAssets + totalCurrentAssets).toFixed(2));
        // ==========================================
        // 2. LIABILITIES & EQUITY (Source of Funds)
        // ==========================================
        const nonCurrentLiabilityItems = [];
        if (totalLoanLiabilities > 0) {
            nonCurrentLiabilityItems.push({
                name: 'Bank Term Loans & Long-Term Borrowings',
                amount: Number(totalLoanLiabilities.toFixed(2)),
                category: 'Long-Term Borrowings'
            });
        }
        const totalNonCurrentLiabilities = Number(nonCurrentLiabilityItems.reduce((s, l) => s + l.amount, 0).toFixed(2));
        const currentLiabilityItems = [
            { name: 'Trade Payables (Sundry Creditors / Vendors)', amount: Number(sundryCreditors.toFixed(2)), category: 'Payables' },
            { name: 'Output Tax Payable (Statutory GST)', amount: Number(outputGstPayable.toFixed(2)), category: 'Tax Liabilities' }
        ];
        if (customerAdvances > 0) {
            currentLiabilityItems.push({
                name: 'Customer Advances / Unearned Revenue',
                amount: Number(customerAdvances.toFixed(2)),
                category: 'Advances'
            });
        }
        const totalCurrentLiabilities = Number(currentLiabilityItems.reduce((s, l) => s + l.amount, 0).toFixed(2));
        const totalLiabilities = Number((totalNonCurrentLiabilities + totalCurrentLiabilities).toFixed(2));
        // Shareholders' Funds / Equity
        const ownerCapital = Number((totalAssets - totalLiabilities - netProfit).toFixed(2));
        const equityItems = [
            { name: "Owner's Capital Account", amount: ownerCapital, category: 'Capital' },
            { name: 'Retained Earnings / Current Period Net Profit (PAT)', amount: netProfit, category: 'Reserves & Surplus' }
        ];
        const totalEquity = Number((ownerCapital + netProfit).toFixed(2));
        const totalLiabilitiesAndEquity = Number((totalEquity + totalLiabilities).toFixed(2));
        // Flat assets & liabilities lists for backward compatibility
        const flatAssets = [
            ...nonCurrentAssetItems,
            ...currentAssetItems
        ];
        const flatLiabilities = [
            ...nonCurrentLiabilityItems,
            ...currentLiabilityItems
        ];
        res.json({
            success: true,
            data: {
                // Structured Corporate Balance Sheet
                assetsClassified: {
                    nonCurrentAssets: {
                        grossBlock: grossBlockVal,
                        accumulatedDepreciation: accumulatedDepreciationVal,
                        netFixedAssets: netFixedAssetsVal,
                        investments: investmentsVal,
                        items: nonCurrentAssetItems,
                        total: totalNonCurrentAssets
                    },
                    currentAssets: {
                        inventories: Number(closingStock.toFixed(2)),
                        tradeReceivables: Number(sundryDebtors.toFixed(2)),
                        cashAndCashEquivalents: Number((cashBalance + bankBalance).toFixed(2)),
                        inputTaxCredit: Number(inputGstCredit.toFixed(2)),
                        items: currentAssetItems,
                        total: totalCurrentAssets
                    },
                    totalAssets
                },
                liabilitiesAndEquityClassified: {
                    equity: {
                        ownerCapital,
                        retainedEarnings: netProfit,
                        items: equityItems,
                        total: totalEquity
                    },
                    nonCurrentLiabilities: {
                        totalLongTermBorrowings: totalNonCurrentLiabilities,
                        items: nonCurrentLiabilityItems,
                        total: totalNonCurrentLiabilities
                    },
                    currentLiabilities: {
                        totalTradePayables: Number(sundryCreditors.toFixed(2)),
                        totalOutputTax: Number(outputGstPayable.toFixed(2)),
                        items: currentLiabilityItems,
                        total: totalCurrentLiabilities
                    },
                    totalLiabilitiesAndEquity
                },
                // Backward-compatible fields
                assets: flatAssets,
                liabilities: flatLiabilities,
                equity: equityItems,
                totals: {
                    totalAssets,
                    totalNonCurrentAssets,
                    totalCurrentAssets,
                    totalLiabilities,
                    totalNonCurrentLiabilities,
                    totalCurrentLiabilities,
                    totalEquity,
                    isBalanced: Math.abs(totalAssets - totalLiabilitiesAndEquity) < 0.01
                }
            }
        });
    }
    catch (error) {
        console.error('getBalanceSheet error:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};
exports.getBankReconciliation = async (req, res) => {
    try {
        const reqOutlet = req.query.outlet_id || req.query.outletId;
        const scope = await resolveOutletScope(req, reqOutlet);
        const { bank_account_id } = req.query;
        const bankWhere = { is_active: true, outlet_id: scope.outlet_id };
        if (bank_account_id)
            bankWhere.id = bank_account_id;
        const bank = await req.propertyDb.models.bank_accounts.findOne({ where: bankWhere, order: [['id', 'ASC']] });
        const voucherWhere = { outlet_id: scope.outlet_id };
        if (bank?.id)
            voucherWhere.bank_account_id = bank.id;
        const vouchers = await req.propertyDb.models.accounting_vouchers.findAll({
            where: voucherWhere,
            order: [['voucher_date', 'DESC'], ['id', 'DESC']]
        });
        res.json({
            success: true,
            bankAccount: bank,
            summary: {
                bookBalance: bank ? Number(bank.current_balance) : 0,
                unclearedCheques: 0,
                reconciledBalance: bank ? Number(bank.current_balance) : 0
            },
            data: vouchers
        });
    }
    catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};
module.exports = exports;
exports.default = exports;
