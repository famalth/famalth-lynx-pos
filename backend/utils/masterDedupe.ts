import { QueryTypes } from 'sequelize';

/**
 * Candidate natural keys (in priority order) for master tables to prevent
 * duplicate records during backup restore or local<->cloud migration when
 * primary key IDs differ from auto-created records in the target database.
 */
export const MASTER_NATURAL_KEYS: Record<string, string[][]> = {
  hr_offices: [['outlet_id', 'office_code'], ['outlet_id', 'office_name']],
  hr_departments: [['outlet_id', 'department_name']],
  hr_designations: [['outlet_id', 'name']],
  hr_shifts: [['outlet_id', 'name']],
  hr_pay_structures: [['outlet_id', 'name']],
  hr_salary_components: [['outlet_id', 'name']],
  hr_leave_types: [['outlet_id', 'name']],
  hr_holidays: [['outlet_id', 'holiday_date', 'name']],
  hr_employees: [['outlet_id', 'employee_code']],
  hr_biometric_devices: [['outlet_id', 'device_ip'], ['outlet_id', 'device_name']],
  clinic_doctors: [['outlet_id', 'name'], ['outlet_id', 'phone']],
  clinic_services: [['outlet_id', 'name']],
  clinic_patients: [['outlet_id', 'phone']],
  item_master: [['outlet_id', 'item_code']],
  product_templates: [['outlet_id', 'template_name'], ['outlet_id', 'name']],
  item_groups: [['outlet_id', 'name'], ['outlet_id', 'group_name']],
  subcategories: [['outlet_id', 'name']],
  brands: [['outlet_id', 'name']],
  customers: [['outlet_id', 'phone']],
  suppliers: [['outlet_id', 'phone'], ['outlet_id', 'name']],
  supplier_master: [['outlet_id', 'phone'], ['outlet_id', 'supplier_name'], ['outlet_id', 'name']],
  taxes_master: [['outlet_id', 'name']],
  tax_groups: [['outlet_id', 'name']],
  tax_profiles: [['outlet_id', 'name']],
  stock_locations: [['outlet_id', 'location_code'], ['outlet_id', 'name']],
  restaurant_floors: [['outlet_id', 'name'], ['outlet_id', 'floor_name']],
  restaurant_tables: [['outlet_id', 'table_number'], ['outlet_id', 'table_name']],
  kitchen_stations: [['outlet_id', 'name'], ['outlet_id', 'station_name']],
  kot_printers: [['outlet_id', 'name'], ['outlet_id', 'printer_name']],
  bank_accounts: [['outlet_id', 'account_number']],
  paymentMethod: [['outlet_id', 'name']],
  saleSource: [['outlet_id', 'name']],
  numbering_settings: [['outlet_id', 'document_type']],
  document_sequences: [['outlet_id', 'document_type']],
  system_settings: [['outlet_id', 'setting_key']],
  app_branding: [['outlet_id']],
  bill_value_promos: [['outlet_id', 'promo_name'], ['outlet_id', 'name']],
  sales_schemes: [['outlet_id', 'scheme_name'], ['outlet_id', 'name']],
  transport_vehicles: [['outlet_id', 'vehicle_number']],
  transport_drivers: [['outlet_id', 'phone']],
};

/**
 * Checks if a master row already exists in the target table by natural key.
 * Returns the existing row's `id` if found, or `null` if no duplicate exists.
 */
export async function findExistingMasterByNaturalKey(
  db: any,
  tableName: string,
  row: Record<string, any>,
  validCols?: Set<string> | Map<string, string>,
  transaction?: any
): Promise<any | null> {
  const keySets = MASTER_NATURAL_KEYS[tableName];
  if (!keySets || !row || typeof row !== 'object') return null;

  const hasCol = (col: string) => {
    if (!validCols) return true;
    return validCols instanceof Map ? validCols.has(col) : validCols.has(col);
  };

  for (const keyCols of keySets) {
    const allPresent = keyCols.every((c) => {
      if (!hasCol(c)) return false;
      const v = row[c];
      return v !== undefined && v !== null && String(v).trim() !== '';
    });
    if (!allPresent) continue;

    const whereParts: string[] = [];
    const bind: any[] = [];
    keyCols.forEach((col, idx) => {
      const val = row[col];
      if (typeof val === 'number' || col === 'outlet_id') {
        whereParts.push(`"${col}" = $${idx + 1}`);
        bind.push(Number(val));
      } else {
        whereParts.push(`LOWER(TRIM("${col}"::text)) = LOWER(TRIM($${idx + 1}::text))`);
        bind.push(String(val));
      }
    });

    const sql = `SELECT id FROM "${tableName}" WHERE ${whereParts.join(' AND ')} LIMIT 1;`;
    try {
      if (transaction) {
        await db.query('SAVEPOINT sp_nk', { transaction });
      }
      const rows: any[] = await db.query(sql, {
        bind,
        type: QueryTypes.SELECT,
        ...(transaction ? { transaction } : {}),
      });
      if (transaction) {
        await db.query('RELEASE SAVEPOINT sp_nk', { transaction });
      }
      if (Array.isArray(rows) && rows.length > 0 && rows[0]?.id !== undefined) {
        return rows[0].id;
      }
    } catch (_) {
      if (transaction) {
        await db.query('ROLLBACK TO SAVEPOINT sp_nk', { transaction }).catch(() => {});
      }
    }
  }
  return null;
}
