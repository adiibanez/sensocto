// No direct equivalent for CoreBluetooth in web context.
// This code assumes you have a way to get the data from the
// Bluetooth device.

const DataType = {
    uint8: 'uint8',
    uint16: 'uint16',
    uint32: 'uint32',
    int8: 'int8',
    int16: 'int16',
    int32: 'int32',
    float: 'float',
    double: 'double',
    boolean: 'boolean',
    utf8String: 'utf8String',
    rawData: 'rawData'
};

class BluetoothUtils {

    static expandShortUUID(uuidString) {
        if (uuidString.length === 4) {
            let expandedUuidString = `0000${uuidString}-0000-1000-8000-00805F9B34FB`.toLowerCase(); // Convert to lowercase here
            console.log(`Expanded: uuidString to ${expandedUuidString}`);
            return expandedUuidString;
        } else {
            return uuidString.toLowerCase(); // Convert to lowercase here
        }
    }

    static uuidMap = {
        // MARK: - Characteristics
        "00002a43-0000-1000-8000-00805f9b34fb": ["alertCategoryId", DataType.uint8], // Alert Category ID
        "00002a06-0000-1000-8000-00805f9b34fb": ["alertLevel", DataType.uint8], // Alert Level
        "00002a3f-0000-1000-8000-00805f9b34fb": ["alertStatus", DataType.uint8], // Alert Status
        "00002ab3-0000-1000-8000-00805f9b34fb": ["altitude", DataType.int32], // Altitude
        "00002a58-0000-1000-8000-00805f9b34fb": ["analog", DataType.rawData], // Analog
        "00002a59-0000-1000-8000-00805f9b34fb": ["analogOutput", DataType.rawData], // Analog output
        "00002a19-0000-1000-8000-00805f9b34fb": ["batteryLevel", DataType.uint8], // Battery Level
        "00002a2b-0000-1000-8000-00805f9b34fb": ["currentTime", DataType.rawData], // Current Time
        "00002a56-0000-1000-8000-00805f9b34fb": ["digital", DataType.rawData], // Digital
        "00002a57-0000-1000-8000-00805f9b34fb": ["digitalOutput", DataType.rawData], // Digital output
        "00002a26-0000-1000-8000-00805f9b34fb": ["firmwareRevisionString", DataType.utf8String], // Firmware Revision String
        "00002a8a-0000-1000-8000-00805f9b34fb": ["firstName", DataType.utf8String], // First Name
        "00002a00-0000-1000-8000-00805f9b34fb": ["deviceName", DataType.utf8String], // Device Name
        "00002a03-0000-1000-8000-00805f9b34fb": ["reconnectionAddress", DataType.rawData], // Reconnection Address
        "00002a05-0000-1000-8000-00805f9b34fb": ["serviceChanged", DataType.rawData], // Service Changed
        "00002a27-0000-1000-8000-00805f9b34fb": ["hardwareRevisionString", DataType.utf8String], // Hardware Revision String
        "00002a6f-0000-1000-8000-00805f9b34fb": ["humidity", DataType.float], // Humidity
        "00002a90-0000-1000-8000-00805f9b34fb": ["lastName", DataType.utf8String], // Last Name
        "00002aae-0000-1000-8000-00805f9b34fb": ["latitude", DataType.int32], // Latitude
        "00002aaf-0000-1000-8000-00805f9b34fb": ["longitude", DataType.int32], // Longitude
        "00002a29-0000-1000-8000-00805f9b34fb": ["manufacturerNameString", DataType.utf8String], // Manufacturer Name String
        "00002a21-0000-1000-8000-00805f9b34fb": ["measurementInterval", DataType.int32], // Measurement Interval
        "00002a24-0000-1000-8000-00805f9b34fb": ["modelNumberString", DataType.utf8String], // Model Number String
        "00002a6d-0000-1000-8000-00805f9b34fb": ["pressure", DataType.float], // Pressure
        // Thesma breathing pressure
        "61d20a90-71a1-11ea-ab12-0800200c9a66": ["pressure", DataType.float], // Pressure
        "00002a78-0000-1000-8000-00805f9b34fb": ["rainfall", DataType.int32], // Rainfall
        "00002a25-0000-1000-8000-00805f9b34fb": ["serialNumberString", DataType.utf8String], // Serial Number String
        "00002a3b-0000-1000-8000-00805f9b34fb": ["serviceRequired", DataType.boolean], // Service Required
        "00002a28-0000-1000-8000-00805f9b34fb": ["softwareRevisionString", DataType.utf8String], // Software Revision String
        "00002a3d-0000-1000-8000-00805f9b34fb": ["string", DataType.utf8String], // String
        "00002a23-0000-1000-8000-00805f9b34fb": ["systemId", DataType.rawData], // System ID
        "00002a6e-0000-1000-8000-00805f9b34fb": ["temperature", DataType.float], // Temperature
        "00002a1f-0000-1000-8000-00805f9b34fb": ["temperatureCelsius", DataType.float],// Temperature Celsius
        "00002a20-0000-1000-8000-00805f9b34fb": ["temperatureFahrenheit", DataType.float],// Temperature Fahrenheit
        "00002a15-0000-1000-8000-00805f9b34fb": ["timeBroadcast", DataType.rawData], // Time Broadcast
        "00002a37-0000-1000-8000-00805f9b34fb": ["heartRateMeasurement", DataType.rawData], // Heart Rate Measurement
        "00002a5b-0000-1000-8000-00805f9b34fb": ["cscMeasurement", DataType.rawData], // CSC Measurement
        "00002902-0000-1000-8000-00805f9b34fb": ["clientCharacteristicConfig", DataType.rawData], // Client Characteristic Config

        // MARK: - Services
        "00001800-0000-1000-8000-00805f9b34fb": ["genericAccess", DataType.rawData],//Generic Access
        "00001811-0000-1000-8000-00805f9b34fb": ["alertNotificationService", DataType.rawData], // Alert Notification Service
        "00001815-0000-1000-8000-00805f9b34fb": ["automationIO", DataType.rawData],//Automation IO
        "0000180f-0000-1000-8000-00805f9b34fb": ["batteryService", DataType.uint8], // Battery Service
        "0000183b-0000-1000-8000-00805f9b34fb": ["binarySensor", DataType.rawData],//Binary Sensor
        "00001805-0000-1000-8000-00805f9b34fb": ["currentTimeService", DataType.rawData],//Current Time Service
        "0000180a-0000-1000-8000-00805f9b34fb": ["deviceInformation", DataType.utf8String],//Device Information
        "0000183c-0000-1000-8000-00805f9b34fb": ["emergencyConfiguration", DataType.rawData],//Emergency Configuration
        "0000181a-0000-1000-8000-00805f9b34fb": ["environmentalSensing", DataType.rawData],//Environmental Sensing
        "00001801-0000-1000-8000-00805f9b34fb": ["genericAttribute", DataType.rawData],//Generic Attribute
        "00001812-0000-1000-8000-00805f9b34fb": ["humanInterfaceDevice", DataType.rawData],//Human Interface Device
        "00001802-0000-1000-8000-00805f9b34fb": ["immediateAlert", DataType.rawData],//Immediate Alert
        "00001821-0000-1000-8000-00805f9b34fb": ["indoorPositioning", DataType.rawData],//Indoor Positioning
        "00001803-0000-1000-8000-00805f9b34fb": ["linkLoss", DataType.rawData],//Link Loss
        "00001819-0000-1000-8000-00805f9b34fb": ["locationAndNavigation", DataType.rawData],// Location and Navigation
        "00001825-0000-1000-8000-00805f9b34fb": ["objectTransferService", DataType.rawData],//Object Transfer Service
        "00001824-0000-1000-8000-00805f9b34fb": ["transportDiscovery", DataType.rawData], //Transport Discovery
        "00001804-0000-1000-8000-00805f9b34fb": ["txPower", DataType.int8], //Tx Power
        "0000181c-0000-1000-8000-00805f9b34fb": ["userData", DataType.rawData], //User Data

        // BLE Mock service
        "00001523-1212-efde-1523-785feabcd123": ["nordicBlinkyService", DataType.rawData],

        // BLE Mock characteristics
        "00001524-1212-efde-1523-785feabcd123": ["buttonCharacteristic", DataType.uint8],
        "00001525-1212-efde-1523-785feabcd123": ["ledCharacteristic", DataType.uint8],
        "00002a38-0000-1000-8000-00805f9b34fb": ["bodySensorLocation", DataType.uint8] //short UUID mock for body temperature
    };

    static name(uuid) {
        const uuidString = uuid.toLowerCase(); // Convert to lowercase here
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString]?.[0] || `unknown ${uuid} ${uuidString}`;
    }

    static dataType(uuid) {
        const uuidString = uuid.toLowerCase(); // Convert to lowercase here
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString]?.[1] || null;
    }

    static isKnown(uuid) {
        const uuidString = uuid.toLowerCase(); // Convert to lowercase here
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString] !== undefined;
    }

    static decodeHeartRate(data) {
        console.log(`Heartrate data count: ${data.byteLength}`);

        if (data.byteLength === 0) {
            console.log("Data is too short to read heartrate (no flags)");
            return null;
        }

        const flags = data.getUint8(0);
        const heartRateFormatBit = flags & 0x01;

        if (heartRateFormatBit === 0) { // uint8 format
            if (data.byteLength < 2) {
                console.log("Data is too short for uint8 heartrate (flags present, but no value)");
                return null;
            }
            const heartRateValue = data.getUint8(1); // Extract uint8
            console.log(`Decoded uint8 heartrate: ${heartRateValue}`);
            return heartRateValue.toString();
        } else { // uint16 format
            if (data.byteLength < 3) {
                console.log("Data is too short for uint16 heartrate (flags set, but no 16-bit value)");
                return null;
            }
            const heartRateValue = data.getUint16(1, true); // Extract UInt16 (little endian)

            console.log(`Decoded uint16 heartrate: ${heartRateValue}`);
            return heartRateValue.toString();
        }
    }


    static decodeValue(uuid, dataView) {
        const uuidString = uuid.toLowerCase(); // Convert to lowercase here
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        const dataType = BluetoothUtils.dataType(uuid);
        if (!dataType) {
            console.log(`Unknown data type for UUID: ${uuid}`);
            return null;
        }

        switch (dataType) {
            case DataType.uint8:
                return dataView.getUint8(0);
            case DataType.uint16:
                return dataView.getUint16(0, true); // Little endian
            case DataType.uint32:
                return dataView.getUint32(0, true); // Little endian
            case DataType.int8:
                return dataView.getInt8(0);
            case DataType.int16:
                return dataView.getInt16(0, true); // Little endian
            case DataType.int32:
                return dataView.getInt32(0, true); // Little endian
            case DataType.float:
                return dataView.getFloat32(0, true); // Little endian
            case DataType.double:
                return dataView.getFloat64(0, true); // Little endian
            case DataType.boolean:
                return dataView.getUint8(0) !== 0;
            case DataType.utf8String:
                return new TextDecoder().decode(dataView);
            case DataType.rawData:
                return dataView; // Return the raw DataView
            default:
                console.log(`Unsupported data type: ${dataType}`);
                return null;
        }
    }

    static printCharacteristicProperties(characteristic, peripheralName) {
        let properties = characteristic.properties;
        peripheralName = peripheralName || "Unnamed Peripheral"; // Provide a default value

        if (properties.broadcast) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: broadcast`);
        }
        if (properties.read) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: read`);
        }
        if (properties.writeWithoutResponse) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: writeWithoutResponse`);
        }
        if (properties.write) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: write`);
        }
        if (properties.notify) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: notify`);
        }
        if (properties.indicate) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: indicate`);
        }
        if (properties.authenticatedSignedWrites) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: authenticatedSignedWrites`);
        }
        if (properties.extendedProperties) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: extendedProperties`);
        }
        if (properties.notifyEncryptionRequired) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: notifyEncryptionRequired`);
        }
        if (properties.indicateEncryptionRequired) {
            console.log(`${peripheralName} characteristic ${characteristic.uuid} ${BluetoothUtils.name(characteristic.uuid)} has property: indicateEncryptionRequired`);
        }
    }
}

export {
    BluetoothUtils,
};