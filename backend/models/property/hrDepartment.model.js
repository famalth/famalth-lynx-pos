"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
module.exports = (sequelize, DataTypes) => {
    const HrDepartment = sequelize.define('hr_departments', {
        id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
        outlet_id: { type: DataTypes.INTEGER, allowNull: false },
        office_id: { type: DataTypes.INTEGER, allowNull: true },
        department_name: { type: DataTypes.STRING(100), allowNull: false },
        department_code: { type: DataTypes.STRING(50), allowNull: true },
        description: { type: DataTypes.TEXT, allowNull: true },
        is_active: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true },
        created_by: { type: DataTypes.INTEGER, allowNull: true }
    }, {
        tableName: 'hr_departments',
        timestamps: true,
        createdAt: 'created_at',
        updatedAt: 'updated_at'
    });
    HrDepartment.associate = (models) => {
        if (models.outlets) {
            HrDepartment.belongsTo(models.outlets, { foreignKey: 'outlet_id', as: 'outlet' });
        }
        if (models.hr_offices) {
            HrDepartment.belongsTo(models.hr_offices, { foreignKey: 'office_id', as: 'office' });
        }
        if (models.hr_employees) {
            HrDepartment.hasMany(models.hr_employees, { foreignKey: 'department_id', as: 'employees' });
        }
    };
    return HrDepartment;
};
exports.default = module.exports;
