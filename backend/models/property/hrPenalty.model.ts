export = (sequelize: any, DataTypes: any) => {
  const HrPenalty = sequelize.define('hr_penalties', {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    outlet_id: { type: DataTypes.INTEGER, allowNull: false },
    employee_id: { type: DataTypes.INTEGER, allowNull: false },
    amount: { type: DataTypes.DECIMAL(12, 2), allowNull: false },
    reason: { type: DataTypes.STRING(255), allowNull: true },
    category: { type: DataTypes.STRING(100), allowNull: true, defaultValue: 'Disciplinary' },
    penalty_date: { type: DataTypes.DATEONLY, allowNull: false, defaultValue: DataTypes.NOW },
    pay_period: { type: DataTypes.STRING(20), allowNull: true },
    status: { type: DataTypes.STRING(50), allowNull: false, defaultValue: 'Pending' },
    created_by: { type: DataTypes.INTEGER, allowNull: true }
  }, {
    tableName: 'hr_penalties',
    timestamps: true,
    createdAt: 'created_at',
    updatedAt: 'updated_at'
  });

  HrPenalty.associate = (models: any) => {
    HrPenalty.belongsTo(models.outlets, { foreignKey: 'outlet_id', as: 'outlet' });
    HrPenalty.belongsTo(models.hr_employees, { foreignKey: 'employee_id', as: 'employee' });
  };

  return HrPenalty;
};
