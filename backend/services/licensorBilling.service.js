"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.licensorBillingService = void 0;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const DEFAULT_CONFIG = {
    companyName: 'Famalth Technologies',
    brandSubtitle: 'Famalth Lynx Enterprise Retail Platform',
    address: 'Dehradun, Uttarakhand 248001',
    cityStatePin: 'Dehradun, Uttarakhand 248001',
    country: 'India',
    taxIdentifier: 'GSTIN: 07AAAAF1234A1Z5',
    cin: 'U72900DL2022PTC123456',
    contactEmail: 'enterprise@famalth.com',
    contactPhone: '+91 00000 00000',
    website: 'www.famalth.com',
    bankName: '',
    accountNumber: '',
    accountName: '',
    ifscSwift: '',
    upiId: '',
    paymentTerms: 'Payment due within 15 days of invoice date. All payments subject to standard SaaS license terms.',
};
function getStoragePath() {
    const rootDir = process.pkg ? path_1.default.dirname(process.execPath) : process.cwd();
    const dirPath = path_1.default.join(rootDir, 'backend', 'data');
    if (!fs_1.default.existsSync(dirPath)) {
        try {
            fs_1.default.mkdirSync(dirPath, { recursive: true });
        }
        catch (_) { }
    }
    return path_1.default.join(dirPath, 'licensor_billing_config.json');
}
class LicensorBillingService {
    static instance;
    cachedConfig = null;
    static getInstance() {
        if (!LicensorBillingService.instance) {
            LicensorBillingService.instance = new LicensorBillingService();
        }
        return LicensorBillingService.instance;
    }
    getConfig() {
        if (this.cachedConfig) {
            return { ...this.cachedConfig };
        }
        try {
            const filePath = getStoragePath();
            if (fs_1.default.existsSync(filePath)) {
                const raw = fs_1.default.readFileSync(filePath, 'utf8');
                const parsed = JSON.parse(raw);
                this.cachedConfig = {
                    ...DEFAULT_CONFIG,
                    ...parsed,
                };
                return { ...this.cachedConfig };
            }
        }
        catch (e) {
            console.warn('⚠️ [LICENSOR_BILLING] Could not read billing config file, falling back to defaults:', e.message);
        }
        this.cachedConfig = { ...DEFAULT_CONFIG };
        return { ...this.cachedConfig };
    }
    saveConfig(updates) {
        const current = this.getConfig();
        const updated = {
            ...current,
            ...updates,
            companyName: (updates.companyName ?? current.companyName).trim(),
            brandSubtitle: (updates.brandSubtitle ?? current.brandSubtitle).trim(),
            address: (updates.address ?? current.address).trim(),
            cityStatePin: (updates.cityStatePin ?? current.cityStatePin).trim(),
            country: (updates.country ?? current.country).trim(),
            taxIdentifier: (updates.taxIdentifier ?? current.taxIdentifier).trim(),
            cin: (updates.cin ?? current.cin).trim(),
            contactEmail: (updates.contactEmail ?? current.contactEmail).trim(),
            contactPhone: (updates.contactPhone ?? current.contactPhone).trim(),
            website: (updates.website ?? current.website).trim(),
            bankName: (updates.bankName ?? current.bankName).trim(),
            accountNumber: (updates.accountNumber ?? current.accountNumber).trim(),
            accountName: (updates.accountName ?? current.accountName).trim(),
            ifscSwift: (updates.ifscSwift ?? current.ifscSwift).trim(),
            upiId: (updates.upiId ?? current.upiId).trim(),
            paymentTerms: (updates.paymentTerms ?? current.paymentTerms).trim(),
        };
        try {
            const filePath = getStoragePath();
            fs_1.default.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
            this.cachedConfig = updated;
            console.log('✅ [LICENSOR_BILLING] Licensor billing configuration updated and saved to disk.');
        }
        catch (e) {
            console.error('❌ [LICENSOR_BILLING] Failed to write billing config to disk:', e.message);
        }
        return updated;
    }
}
exports.licensorBillingService = LicensorBillingService.getInstance();
exports.default = exports.licensorBillingService;
