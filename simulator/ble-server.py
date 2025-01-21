import objc
from Foundation import NSData
from CoreBluetooth import (
    CBPeripheralManager, CBMutableCharacteristic, CBMutableService,
    CBCharacteristicPropertyRead, CBAttributePermissionsReadable
)

class BLEPeripheral:
    def __init__(self):
        # Initialize the peripheral manager
        self.manager = CBPeripheralManager.alloc().initWithDelegate_queue_(self, None)
        self.service = None
        self.characteristics = []  # Keep track of characteristics

    def peripheralManagerDidUpdateState_(self, manager):
        if manager.state() == 5:  # Powered On
            print("Peripheral Manager powered on.")
            self.setup_service()

    def setup_service(self):
        # Create a pressure characteristic
        characteristic = CBMutableCharacteristic.alloc().initWithType_properties_value_permissions_(
            "00002A6D-0000-1000-8000-00805F9B34FB",  # Pressure characteristic UUID
            CBCharacteristicPropertyRead,
            None,  # No initial value
            CBAttributePermissionsReadable,
        )
        self.characteristics.append(characteristic)

        # Create the service and retain it by setting it in the instance
        self.service = CBMutableService.alloc().initWithType_primary_(
            "0000181A-0000-1000-8000-00805F9B34FB",  # Environmental sensing service UUID
            True,  # Primary service
        )
        self.service.setCharacteristics_(self.characteristics)

        # Add service to peripheral manager
        self.manager.addService_(self.service)

        # Start advertising
        self.manager.startAdvertising_({ "CBAdvertisementDataLocalNameKey": "TestBLE" })
        print("Started Advertising")

    def peripheralManager_didAddService_error_(self, manager, service, error):
        if error:
            print("Error adding service:", error)
        else:
            print("Service added successfully.")

    def peripheralManagerDidStartAdvertising_error_(self, manager, error):
        if error:
            print("Error starting advertising:", error)
        else:
            print("Advertising started.")

    def convert_string_to_nsdata(self, value):
        """Helper method to convert a string to NSData."""
        return NSData.dataWithBytes_length_(value.encode('utf-8'), len(value))

    def update_pressure_value(self, pressure_value):
        """Method to update pressure value of characteristic."""
        ns_data = self.convert_string_to_nsdata(pressure_value)
        if self.characteristics:
            self.characteristics[0].setValue_(ns_data)  # Update the first characteristic

if __name__ == "__main__":
    from PyObjCTools.AppHelper import runConsoleEventLoop

    print("Starting BLE Peripheral...")
    peripheral = BLEPeripheral()
    peripheral.update_pressure_value("Simulated Pressure: 1013 hPa")
    runConsoleEventLoop()
