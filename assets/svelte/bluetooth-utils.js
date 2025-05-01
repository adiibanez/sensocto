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
        //Characteristics
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
        "61d20a90-71a1-11ea-ab12-0800200c9a66": ["breathingPressure", DataType.float], // Pressure
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
        "00002a37-0000-1000-8000-00805f9b34fb": ["heartRateMeasurement", DataType.rawData, BluetoothUtils.decodeHeartRate], // Heart Rate Measurement
        "00002a5b-0000-1000-8000-00805f9b34fb": ["cscMeasurement", DataType.rawData], // CSC Measurement
        "00002902-0000-1000-8000-00805f9b34fb": ["clientCharacteristicConfig", DataType.rawData], // Client Characteristic Config

        // Services
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

        // https://nordicsemiconductor.github.io/Nordic-Thingy52-FW/documentation/firmware_architecture.html
        // Thingy:52 Characteristics (using full lowercase UUIDs)
        "ef680101-9b35-4933-9b10-52ffa9740042": ["temperatureCharacteristic", DataType.float],
        "ef680102-9b35-4933-9b10-52ffa9740042": ["pressureCharacteristic", DataType.float],
        "ef680103-9b35-4933-9b10-52ffa9740042": ["humidityCharacteristic", DataType.float],
        "ef680104-9b35-4933-9b10-52ffa9740042": ["airQualityCharacteristic", DataType.rawData, BluetoothUtils.decodeAirQuality], // Parse eCO2 and TVOC
        "ef680105-9b35-4933-9b10-52ffa9740042": ["colorCharacteristic", DataType.rawData, BluetoothUtils.decodeColor], // Parse R, G, B, Clear
        "ef680106-9b35-4933-9b10-52ffa9740042": ["environmentConfigCharacteristic", DataType.rawData],
        "ef680201-9b35-4933-9b10-52ffa9740042": ["ledCharacteristic", DataType.rawData, BluetoothUtils.decodeLED], // Parse RGB
        "ef680202-9b35-4933-9b10-52ffa9740042": ["buttonCharacteristic", DataType.uint8],
        "ef680203-9b35-4933-9b10-52ffa9740042": ["uiConfigCharacteristic", DataType.rawData],
        "ef680301-9b35-4933-9b10-52ffa9740042": ["tapCharacteristic", DataType.rawData],
        "ef680302-9b35-4933-9b10-52ffa9740042": ["orientationCharacteristic", DataType.uint8],
        "ef680303-9b35-4933-9b10-52ffa9740042": ["quaternionCharacteristic", DataType.rawData, BluetoothUtils.decodeQuaternion], // Parse W, X, Y, Z
        "ef680304-9b35-4933-9b10-52ffa9740042": ["stepCounterCharacteristic", DataType.rawData, BluetoothUtils.decodeStepCounter],
        "ef680305-9b35-4933-9b10-52ffa9740042": ["rawDataCharacteristic", DataType.rawData, BluetoothUtils.decodeRawMotionData], // Parse Accel, Gyro, Compass
        "ef680306-9b35-4933-9b10-52ffa9740042": ["eulerAngleCharacteristic", DataType.rawData, BluetoothUtils.decodeEuler],
        "ef680307-9b35-4933-9b10-52ffa9740042": ["rotationMatrixCharacteristic", DataType.rawData],
        "ef680308-9b35-4933-9b10-52ffa9740042": ["headingCharacteristic", DataType.float],
        "ef680309-9b35-4933-9b10-52ffa9740042": ["gravityVectorCharacteristic", DataType.rawData],
        "ef68030a-9b35-4933-9b10-52ffa9740042": ["motionConfigCharacteristic", DataType.rawData],
        "ef680401-9b35-4933-9b10-52ffa9740042": ["speakerDataCharacteristic", DataType.rawData], //  Audio data to speaker
        "ef680402-9b35-4933-9b10-52ffa9740042": ["speakerStatusCharacteristic", DataType.rawData],
        "ef680403-9b35-4933-9b10-52ffa9740042": ["microphoneCharacteristic", DataType.rawData],
        "ef680404-9b35-4933-9b10-52ffa9740042": ["soundConfigCharacteristic", DataType.rawData],


        // "00001801-0000-1000-8000-00805f9b34fb": ["batteryServicePuffer", DataType.uint8], // Battery Service
        "f75966a4-2f01-404b-be19-84af8df52728": ["pufferService", DataType.rawData], // Puffer sensor classification
        "63692f11-9daf-4c7d-ab89-45fbe50af19d": ["pufferClassification", DataType.utf8String], // Puffer sensor classification
        "56e03b21-09a3-45ae-b7bb-c3d0817f430c": ["pufferImuRawdata", DataType.rawData, BluetoothUtils.decodePufferImuPacket], // Puffer sensor classification
        // "56e03b21-09a3-45ae-b7bb-c3d0817f430c": ["imu", DataType.rawData], // Puffer sensor classification

        // Unknown sound characteristics
        "ef680407-9b35-4933-9b10-52ffa9740042": ["unknownSoundCharacteristic1", DataType.rawData],
        "ef680408-9b35-4933-9b10-52ffa9740042": ["unknownSoundCharacteristic2", DataType.rawData],
        "ef680409-9b35-4933-9b10-52ffa9740042": ["unknownSoundCharacteristic3", DataType.rawData],

        // Thingy:52 Services (using full lowercase UUIDs)
        "ef680100-9b35-4933-9b10-52ffa9740042": ["environmentService", DataType.rawData],
        "ef680200-9b35-4933-9b10-52ffa9740042": ["userInterfaceService", DataType.rawData],
        "ef680300-9b35-4933-9b10-52ffa9740042": ["motionService", DataType.rawData],
        "ef680400-9b35-4933-9b10-52ffa9740042": ["soundService", DataType.rawData],

        // BLE Mock service
        "00001523-1212-efde-1523-785feabcd123": ["nordicBlinkyService", DataType.rawData],

        // BLE Mock characteristics
        "00001524-1212-efde-1523-785feabcd123": ["buttonCharacteristic", DataType.uint8],
        "00001525-1212-efde-1523-785feabcd123": ["ledCharacteristic", DataType.uint8],
        "00002a38-0000-1000-8000-00805f9b34fb": ["bodySensorLocation", DataType.uint8] //short UUID mock for body temperature
    };

    static name(uuid) {
        const uuidString = uuid.toLowerCase();
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        let mapped = BluetoothUtils.uuidMap[expandedUuidString]?.[0] || `unknown ${uuid} ${uuidString}`;
        console.log(`Name lookup ${uuidString} ${expandedUuidString} ${mapped}`);

        return mapped;
    }

    static dataType(uuid) {
        const uuidString = uuid.toLowerCase();
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString]?.[1] || null;
    }

    static decoder(uuid) {
        const uuidString = uuid.toLowerCase();
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString]?.[2] || null;
    }

    static isKnown(uuid) {
        const uuidString = uuid.toLowerCase();
        const expandedUuidString = BluetoothUtils.expandShortUUID(uuidString);
        return BluetoothUtils.uuidMap[expandedUuidString] !== undefined;
    }

    static stdDecoder(dataView, dataType) {
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

    static decodeValue(uuid, dataView) {
        const uuidString = uuid.toLowerCase();
        const dataType = BluetoothUtils.dataType(uuid);
        if (!dataType) {
            console.log(`Unknown data type for UUID: ${uuid} ${BluetoothUtils.name(uuid)}`);
            return null;
        }

        const decoder = BluetoothUtils.decoder(uuid);

        if(decoder != null) {
            return decoder(dataView);
        }
        return this.stdDecoder(dataView, dataType)
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

    // Heartrate
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

    // Thingy decoders

    static decodeTemperature(dataView) {
        // Thingy:52 temperature is a float (Celsius)
        return dataView.getFloat32(0, true);
    }

    static decodePressure(dataView) {
        // Thingy:52 pressure is a float (Pascals)
        return dataView.getFloat32(0, true);
    }

    static decodeHumidity(dataView) {
        // Thingy:52 humidity is a float (%)
        return dataView.getFloat32(0, true);
    }

    static decodeAirQuality(dataView) {
        // Thingy:52 air quality has eCO2 (uint16) and TVOC (uint16)
        if (dataView.byteLength < 4) {
            console.error("DataView too short for air quality data.");
            return null;
          }
        const eCO2 = dataView.getUint16(0, true); // Little endian
        const TVOC = dataView.getUint16(2, true); // Little endian
        return { eCO2, TVOC };
    }
    
    static decodeColor(dataView) {
        // Thingy:52 color has Red (uint16), Green (uint16), Blue (uint16), Clear (uint16)
        if (dataView.byteLength < 8) {
            console.error("DataView too short for color data.");
            return null;
        }
        const red = dataView.getUint16(0, true);
        const green = dataView.getUint16(2, true);
        const blue = dataView.getUint16(4, true);
        const clear = dataView.getUint16(6, true);
        return { red, green, blue, clear };
    }

    static decodeLED(dataView) {
      // Assuming a simple RGB structure: R(8), G(8), B(8)
      if (dataView.byteLength < 3) {
          console.error("DataView too short for LED data.");
          return null;
      }
        const red = dataView.getUint8(0);
        const green = dataView.getUint8(1);
        const blue = dataView.getUint8(2);
      return { red, green, blue };
    }

    static decodeButton(dataView) {
      if (dataView.byteLength < 1) {
        console.error("DataView too short for button data.");
        return null;
      }
        return dataView.getUint8(0); // 0 or 1
    }

    static decodeOrientation(dataView) {
        // Decode orientation (assuming a single byte value, adjust as needed)
        return dataView.getUint8(0);
    }

    static decodeQuaternion(dataView) {
      if (dataView.byteLength < 16) {
        console.error("DataView too short for quaternion data.");
        return null;
    }
        // Thingy:52 quaternions are floats (W, X, Y, Z)
        const w = dataView.getFloat32(0, true);
        const x = dataView.getFloat32(4, true);
        const y = dataView.getFloat32(8, true);
        const z = dataView.getFloat32(12, true);
        return { w, x, y, z };
    }
    
    static decodeStepCounter(dataView) {
        // Decode step counter data (adjust based on actual format)
        if (dataView.byteLength < 6) {
          console.error("DataView too short for step counter data.");
          return null;
        }
        const steps = dataView.getUint32(0, true);
        const time = dataView.getUint16(4, true);
        return { steps, time };
    }

    static decodeRawMotionData(dataView) {
        // Decode raw accelerometer, gyroscope, and magnetometer data
        // Assuming 2 bytes (int16) per component, per sensor.  Adjust as needed.
        if (dataView.byteLength < 18) {
          console.error("DataView too short for raw motion data.");
            return null;
        }
        const accelX = dataView.getInt16(0, true);
        const accelY = dataView.getInt16(2, true);
        const accelZ = dataView.getInt16(4, true);
        const gyroX = dataView.getInt16(6, true);
        const gyroY = dataView.getInt16(8, true);
        const gyroZ = dataView.getInt16(10, true);
        const compassX = dataView.getInt16(12, true);
        const compassY = dataView.getInt16(14, true);
        const compassZ = dataView.getInt16(16, true);

        return {
            accelerometer: { x: accelX, y: accelY, z: accelZ },
            gyroscope: { x: gyroX, y: gyroY, z: gyroZ },
            compass: { x: compassX, y: compassY, z: compassZ },
        };
    }

    static decodePufferImuPacket(dataView) {
            // Check if dataView has enough bytes for 6 float values (6 * 4 = 24 bytes)
        if (dataView.byteLength < 24) {
            console.error("DataView too short for IMU float data.");
            return null;
        }

        // Decode 4-byte float values for accelerometer and gyroscope
        const accX = dataView.getFloat32(0, true);   // Little-endian
        const accY = dataView.getFloat32(4, true);
        const accZ = dataView.getFloat32(8, true);
        const gyroX = dataView.getFloat32(12, true);
        const gyroY = dataView.getFloat32(16, true);
        const gyroZ = dataView.getFloat32(20, true);

        return {
            acc: { x: accX, y: accY, z: accZ },
            gyro: { x: gyroX, y: gyroY, z: gyroZ }
        };
    }

    
    
    static decodeTap(dataView) {
        // Assuming 1 byte for direction and 1 byte for count.
      if (dataView.byteLength < 2) {
          console.error("DataView too short for tap data.");
            return null;
        }
        const direction = dataView.getUint8(0);
        const count = dataView.getUint8(1);
        return { direction, count };
    }
    
    static decodeEuler(dataView) {
      if (dataView.byteLength < 12) {
          console.error("DataView too short for euler angle data.");
            return null;
        }
        const roll  = dataView.getFloat32(0, true);
        const pitch = dataView.getFloat32(4, true);
        const yaw   = dataView.getFloat32(8, true);
      return { roll, pitch, yaw };
    }

    static decodeHeading(dataView) {
        return dataView.getFloat32(0, true);
    }
      
    static decodeGravity(dataView) {
      if (dataView.byteLength < 12) {
        console.error("DataView too short for gravity vector data.");
          return null;
        }
      const x = dataView.getFloat32(0, true);
      const y = dataView.getFloat32(4, true);
      const z = dataView.getFloat32(8, true);
      return {x, y, z};
    }
}

export {
    BluetoothUtils,
};