module.exports = (sequelize: any, DataTypes: any) => {
    const TransportDriver = sequelize.define('transport_drivers', {
        id: {
            type: DataTypes.INTEGER,
            primaryKey: true,
            autoIncrement: true
        },
        outlet_id: {
            type: DataTypes.INTEGER,
            allowNull: false
        },
        driver_name: {
            type: DataTypes.STRING(100),
            allowNull: false
        },
        phone: {
            type: DataTypes.STRING(30),
            allowNull: false
        },
        email: {
            type: DataTypes.STRING(100),
            allowNull: true
        },
        password_hash: {
            type: DataTypes.STRING(255),
            allowNull: true
        },
        license_number: {
            type: DataTypes.STRING(50),
            allowNull: true
        },
        address: {
            type: DataTypes.TEXT,
            allowNull: true
        },
        status: {
            type: DataTypes.STRING(30),
            defaultValue: 'AVAILABLE' // 'AVAILABLE', 'BOOKED', 'ON_LEAVE', 'INACTIVE', 'TERMINATED'
        },
        current_vehicle_id: {
            type: DataTypes.INTEGER,
            allowNull: true
        },
        last_latitude: {
            type: DataTypes.NUMERIC(10, 6),
            allowNull: true
        },
        last_longitude: {
            type: DataTypes.NUMERIC(10, 6),
            allowNull: true
        },
        last_location_address: {
            type: DataTypes.TEXT,
            allowNull: true
        },
        last_location_updated: {
            type: DataTypes.DATE,
            allowNull: true
        },
        reset_otp: {
            type: DataTypes.STRING(10),
            allowNull: true
        },
        reset_otp_expires_at: {
            type: DataTypes.DATE,
            allowNull: true
        },
        total_consignments_completed: {
            type: DataTypes.INTEGER,
            defaultValue: 0
        },
        is_active: {
            type: DataTypes.BOOLEAN,
            defaultValue: true
        }
    }, {
        tableName: 'transport_drivers',
        timestamps: true,
        createdAt: 'created_at',
        updatedAt: 'updated_at'
    });

    TransportDriver.associate = (models: any) => {
        if (models.transport_vehicles) {
            TransportDriver.belongsTo(models.transport_vehicles, {
                foreignKey: 'current_vehicle_id',
                as: 'current_vehicle'
            });
        }
        if (models.delivery_challan_headers) {
            TransportDriver.hasMany(models.delivery_challan_headers, {
                foreignKey: 'driver_id',
                as: 'delivered_challans'
            });
        }
    };

    return TransportDriver;
};

export default module.exports;
