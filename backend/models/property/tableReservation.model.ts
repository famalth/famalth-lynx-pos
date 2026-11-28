module.exports = (sequelize, DataTypes) => {
    const TableReservation = sequelize.define('table_reservations', {
        id: {
            type: DataTypes.INTEGER,
            primaryKey: true,
            autoIncrement: true
        },
        outlet_id: {
            type: DataTypes.INTEGER,
            allowNull: false
        },
        table_id: {
            type: DataTypes.INTEGER,
            allowNull: false
        },
        customer_name: {
            type: DataTypes.STRING(150),
            allowNull: false
        },
        customer_phone: {
            type: DataTypes.STRING(20),
            allowNull: false
        },
        reservation_time: {
            type: DataTypes.DATE,
            allowNull: false
        },
        guest_count: {
            type: DataTypes.INTEGER,
            defaultValue: 1
        },
        status: {
            type: DataTypes.STRING(30),
            defaultValue: 'Pending'
        },
        remarks: {
            type: DataTypes.TEXT,
            allowNull: true
        },
        address: {
            type: DataTypes.TEXT,
            allowNull: true
        },
        customer_email: {
            type: DataTypes.STRING(150),
            allowNull: true
        },
        reservation_date: {
            type: DataTypes.DATEONLY,
            allowNull: true
        },
        source: {
            type: DataTypes.STRING(30),
            defaultValue: 'IN_HOUSE'
        },
        gstin: {
            type: DataTypes.STRING(20),
            allowNull: true
        },
        table_ids: {
            type: DataTypes.JSONB,
            defaultValue: []
        },
        table_names: {
            type: DataTypes.TEXT,
            allowNull: true
        },
        event_type: {
            type: DataTypes.STRING(60),
            defaultValue: 'Dining'
        },
        custom_event_name: {
            type: DataTypes.STRING(150),
            allowNull: true
        },
        menu_items: {
            type: DataTypes.JSONB,
            defaultValue: []
        },
        hall_charges: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        items_total: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        booking_amount: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        advance_paid: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        total_cost: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        hall_count: {
            type: DataTypes.INTEGER,
            defaultValue: 1
        },
        hall_rate: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        pricing_mode: {
            type: DataTypes.STRING(30),
            defaultValue: 'VENUE_AND_FOOD'
        },
        per_person_rate: {
            type: DataTypes.DECIMAL(12, 2),
            defaultValue: 0
        },
        selected_slots: {
            type: DataTypes.JSONB,
            defaultValue: []
        },
        duration_hours: {
            type: DataTypes.INTEGER,
            defaultValue: 1
        },
        cancellation_reason: {
            type: DataTypes.TEXT,
            allowNull: true
        }
    }, {
        tableName: 'table_reservations',
        timestamps: true,
        createdAt: 'created_at',
        updatedAt: false
    });

    TableReservation.associate = (models) => {
        TableReservation.belongsTo(models.restaurant_tables, {
            foreignKey: 'table_id',
            as: 'table'
        });
    };

    return TableReservation;
};


export default module.exports;
