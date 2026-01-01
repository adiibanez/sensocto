<script>
  import {
    getContext,
    createEventDispatcher,
    onDestroy,
    onMount,
  } from "svelte";

  import { logger } from "../logger_svelte.js";

  import { BluetoothUtils } from "../bluetooth-utils.js";
  import { bleDevices, bleCharacteristics, bleValues } from "./stores.js";

  let sensorService = getContext("sensorService");
  let loggerCtxName = "BluetoothClient";

  // Use stores for persistent state across LiveView navigations
  // Local reactive variables that sync with stores
  let devices = [];
  let deviceCharacteristics = {};
  let characteristicValues = {};

  // Subscribe to stores
  const unsubDevices = bleDevices.subscribe(value => devices = value);
  const unsubCharacteristics = bleCharacteristics.subscribe(value => deviceCharacteristics = value);
  const unsubValues = bleValues.subscribe(value => characteristicValues = value);

  const dispatch = createEventDispatcher();

  // On mount, restore connections and re-register attributes for existing devices
  onMount(() => {
    const globalDevices = bleDevices.getGlobal();
    if (globalDevices.length > 0) {
      logger.log(loggerCtxName, "Restoring BLE state from previous session", globalDevices.length, "devices");

      // Re-register attributes for all connected devices
      globalDevices.forEach(device => {
        if (device.gatt?.connected) {
          const deviceId = getUniqueDeviceId(device);
          const characteristics = bleCharacteristics.getGlobal()[deviceId] || [];

          // Re-register the sensor channel
          sensorService.setupChannel(deviceId);

          // Re-register each characteristic as an attribute
          characteristics.forEach(characteristic => {
            const normalizedType = BluetoothUtils.normalizedType(characteristic.uuid);
            sensorService.registerAttribute(deviceId, {
              attribute_id: normalizedType,
              attribute_type: normalizedType,
              sampling_rate: 1,
            });
          });

          logger.log(loggerCtxName, "Restored device", deviceId, "with", characteristics.length, "characteristics");
        }
      });
    }
  });

  async function requestLEScan() {
    navigator.bluetooth
      .requestLEScan({
        acceptAllAdvertisements: true,
        keepRepeatedDevices: true,
      })
      .then(() => {
        navigator.bluetooth.addEventListener(
          "advertisementreceived",
          (event) => {
            console.log("Advertisement received:", event);
            // You can process the advertisement data here
          }
        );
      })
      .catch((error) => {
        console.error("Error during LE scan:", error);
      });
  }

  async function scanDevices() {
    const newDevice = await navigator.bluetooth
      .requestDevice({
        // filters: [...] <- Prefer filters to save energy & show relevant devices.
        filters: [
          {
            namePrefix: "Puff",
          },
          {
            namePrefix: "PressureSensor",
          },
          { namePrefix: "Thingy" },
          { namePrefix: "Movesense" },
          { namePrefix: "BlueNRG" },
          { namePrefix: "FlexSenseSensor" },
          { namePrefix: "vívosmart" },
          { namePrefix: "WH-" },
          { namePrefix: "EdgeImpulse" },
          { namePrefix: "Arduino" },
        ],
        //
        // acceptAllDevices: true,
        // lowercase required
        optionalServices: [
          "0000180f-0000-1000-8000-00805f9b34fb", // Thingy main
          "ef680100-9b35-4933-9b10-52ffa9740042", // Thingy environment
          "ef680200-9b35-4933-9b10-52ffa9740042", // Thingy UI
          "ef680300-9b35-4933-9b10-52ffa9740042", // Thingy Motion
          "ef680400-9b35-4933-9b10-52ffa9740042", // Thingy sound

          "f75966a4-2f01-404b-be19-84af8df52728", // Puffer service

          "0000180f-0000-1000-8000-00805f9b34fb", // Std battery
          "00001801-0000-1000-8000-00805f9b34fb", // Std battery?
          "battery_service",

          "453b02b0-71a1-11ea-ab12-0800200c9a66", // pressure
          "heart_rate",

          "61353090-8231-49cc-b57a-886370740041",
          "a688bc90-09e2-4643-8e9a-ff3076703bc3", // oximeter
          "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
          "897fdb8d-dec3-40bc-98e8-2310a58b0189", // flexsense
          "19b10000-e8f2-537e-4f6c-d104768a1214", // Edgeimpulse testservice
          //battery characteristic
          // "00002a19-0000-1000-8000-00805f9b34fb",
        ],
        scanMode: "balanced", // Add scan mode to keep receiving advertisements
        keepRepeatedDevices: true, // Keep receiving advertisements from the same device
      })
      .then((device) => {
        bleDevices.add(device);
        device.addEventListener("gattserverdisconnected", onDisconnected);

        const sensorIdentifier = getUniqueDeviceId(device);
        const sensorType = getDeviceSensorType(device);
        const sensorSamplingRate = getDeviceSamplingRate(device);

        const metadata = {
          sensor_name: getUniqueDeviceName(device),
          sensor_id: getUniqueDeviceId(device),
          sensor_type: sensorType,
          sampling_rate: sensorSamplingRate,
        };

        sensorService.setupChannel(sensorIdentifier, metadata);

        logger.log(loggerCtxName, "Connecting to GATT Server...");
        return device.gatt.connect();
      })
      .then((server) => {
        logger.log(loggerCtxName, "server", server);
        return server.getPrimaryServices();
      })
      .then((services) => {
        //log('Getting Characteristics...');
        let queue = Promise.resolve();
        services.forEach((service) => {
          logger.log(loggerCtxName, "service", service);

          queue = queue.then((_) =>
            service.getCharacteristics().then((characteristics) => {
              logger.log(loggerCtxName, "characteristics", characteristics);

              characteristics.forEach((characteristic) => {
                logger.log(
                  loggerCtxName,
                  "discovered characteristic",
                  characteristic
                );

                if (undefined == characteristic.startNotifications) {
                  logger.log(
                    loggerCtxName,
                    "startNotifications not supported, requires polling fallback"
                  );
                }

                /*log('>> Characteristic: ' + characteristic.uuid + ' ' +
                            getSupportedProperties(characteristic));
                          */
                queue.then((_) => handleCharacteristic(characteristic));
              });
            })
          );
        });
        return queue;
      })
      .catch((error) => {
        logger.log(loggerCtxName, "Argh! " + error);
      });
  }

  function handleCharacteristic(characteristic) {
    // Use normalized type for both attribute_id and attribute_type
    // This ensures human-readable names are displayed in the UI
    // and matches Elixir's AttributeType for proper rendering
    const normalizedType = BluetoothUtils.normalizedType(characteristic.uuid);

    sensorService.registerAttribute(
      getUniqueDeviceId(characteristic.service.device),
      {
        attribute_id: normalizedType,
        attribute_type: normalizedType,
        sampling_rate: 1,
      }
    );

    logger.log(loggerCtxName, "> Service UUID:", characteristic.service.uuid);
    logger.log(
      loggerCtxName,
      "> Characteristic Name:  " + BluetoothUtils.name(characteristic.uuid)
    );
    logger.log(loggerCtxName, "> Characteristic UUID:  " + characteristic.uuid);
    logger.log(
      loggerCtxName,
      "> Broadcast:            " + characteristic.properties.broadcast
    );
    logger.log(
      loggerCtxName,
      "> Read:                 " + characteristic.properties.read
    );
    logger.log(
      loggerCtxName,
      "> Write w/o response:   " +
        characteristic.properties.writeWithoutResponse
    );
    logger.log(
      loggerCtxName,
      "> Write:                " + characteristic.properties.write
    );
    logger.log(
      loggerCtxName,
      "> Notify:               " + characteristic.properties.notify
    );
    logger.log(
      loggerCtxName,
      "> Indicate:             " + characteristic.properties.indicate
    );
    logger.log(
      loggerCtxName,
      "> Signed Write:         " +
        characteristic.properties.authenticatedSignedWrites
    );
    logger.log(
      loggerCtxName,
      "> Queued Write:         " + characteristic.properties.reliableWrite
    );
    logger.log(
      loggerCtxName,
      "> Writable Auxiliaries: " + characteristic.properties.writableAuxiliaries
    );

    if (characteristic.properties.notify == true) {
      logger.log(
        loggerCtxName,
        "Characteristic supports notifications: " + characteristic.uuid,
        characteristic
      );
      return characteristic
        .startNotifications()
        .then((_) => {
          characteristic.addEventListener(
            "characteristicvaluechanged",
            handleCharacteristicChanged
          );

          // Update the store with the new characteristic
          const deviceId = getUniqueDeviceId(characteristic.service.device);
          bleCharacteristics.update(current => {
            const existing = current[deviceId] || [];
            return { ...current, [deviceId]: [...existing, characteristic] };
          });

          logger.log(
            loggerCtxName,
            "deviceCharacteristics",
            deviceCharacteristics[deviceId]
          );
          logger.log(
            loggerCtxName,
            "Subscribed to" + characteristic.uuid,
            characteristic
          );

          return characteristic;
        })
        .then((characteristic) => {
          logger.log(
            loggerCtxName,
            "Waiting for notfications" + characteristic.uuid,
            characteristic
          );
          // if (characteristic.properties.read == true) {
          //     logger.log(
          //         loggerCtxName,
          //         "Reading  notify" + characteristic.uuid + "...",
          //     );
          //     return characteristic
          //         .readValue()
          //         .then((valueObj) => {
          //             logger.log(
          //                 loggerCtxName,
          //                 "Characteristic value:",
          //                 characteristic.uuid,
          //                 valueObj,
          //                 valueObj.getInt8(0),
          //             );
          //             characteristicValue = valueObj.getInt8(0);
          //             characteristicValues[characteristic.uuid] =
          //                 characteristicValue;
          //             var payLoad = {
          //                 payload: characteristicValue,
          //                 attribute_id: characteristic.uuid,
          //                 timestamp: Math.round(new Date().getTime()),
          //             };
          //             logger.log(
          //                 loggerCtxName,
          //                 "Sending notify single read value",
          //                 getUniqueDeviceId(
          //                     characteristic.service.device,
          //                 ),
          //                 payLoad,
          //             );
          //             sensorService.sendChannelMessage(
          //                 getUniqueDeviceId(
          //                     characteristic.service.device,
          //                 ),
          //                 payLoad,
          //             );
          //         })
          //         .catch((error) => {
          //             logger.log(
          //                 loggerCtxName,
          //                 "Error reading characteristic:",
          //                 error,
          //             );
          //         });
          // }
        })
        .catch((error) => {
          logger.log(
            loggerCtxName,
            "Argh! " + characteristic.name + " error: " + error
          );
        });
    } else if (characteristic.properties.read == true) {
      logger.log(
        loggerCtxName,
        "Reading single " + characteristic.uuid + "..."
      );
      return characteristic
        .readValue()
        .then((valueObj) => {
          logger.log(
            loggerCtxName,
            "Characteristic value:",
            characteristic.uuid,
            valueObj,
            valueObj.getInt8(0)
          );
          characteristicValue = valueObj.getInt8(0);
          bleValues.setValue(characteristic.uuid, characteristicValue);

          // Use normalized type for attribute_id to match what was registered
          const normalizedAttrId = BluetoothUtils.normalizedType(characteristic.uuid);

          var payLoad = {
            payload: characteristicValue,
            attribute_id: normalizedAttrId,
            timestamp: Math.round(new Date().getTime()),
          };

          logger.log(
            loggerCtxName,
            "Sending single read value",
            getUniqueDeviceId(characteristic.service.device),
            payLoad
          );

          sensorService.sendChannelMessage(
            getUniqueDeviceId(characteristic.service.device),
            payLoad
          );
        })
        .catch((error) => {
          logger.log(
            loggerCtxName,
            "Argh! " + characteristic.name + " error: " + error
          );
        });
    }
  }

  function handleCharacteristicChanged(event) {
    let v = event.target.value;

    let sensorValue = null;
    let debounce = false;

    sensorValue = BluetoothUtils.decodeValue(event.target.uuid, v);

    sensorType = "unknown";

    switch (event.target.uuid) {
      case "61d20a90-71a1-11ea-ab12-0800200c9a66":
        // pressure sensor
        break;
      case "00002a37-0000-1000-8000-00805f9b34fb":
        // Movesense heartrate
        break;
      case "00002a38-0000-1000-8000-00805f9b34fb":
        // Movesense body sensor location
        break;
      case "00002a19-0000-1000-8000-00805f9b34fb":
        // Movesense battery, ignore
        //sensorValue = v.getInt8(0);
        break;
      case "feb7cb83-e359-4b57-abc6-628286b7a79b":
        // flexsense
        sensorValue = Math.round(v.getFloat32(0, true) * 100) / 100; //v.getFloat32(0, true);//
        debounce = true;
        break;
      default:
        logger.log(
          loggerCtxName,
          "unknown characteristic",
          event.target.uuid,
          v
        );
    }

    if (sensorValue !== null) {
      logger.log(loggerCtxName, "sensorValue", event.target.uuid, sensorValue);

      // Use normalized type for attribute_id to match what was registered
      const normalizedAttrId = BluetoothUtils.normalizedType(event.target.uuid);

      var payLoad = {
        payload: sensorValue,
        attribute_id: normalizedAttrId,
        timestamp: Math.round(new Date().getTime()),
      };
      /*live.pushEvent("ingest", );*/
      if (
        debounce == false ||
        sensorValue != characteristicValues[event.target.uuid]
      ) {
        sensorService.sendChannelMessage(
          getUniqueDeviceId(event.target.service.device),
          payLoad
        );
      } else {
        //logger.log(loggerCtxName, "no change", event.target.uuid, sensorValue);
      }

      bleValues.setValue(event.target.uuid, sensorValue);
    }
  }

  async function onDisconnected(event) {
    var device = event.target;
    logger.log(
      loggerCtxName,
      "> Bluetooth Device disconnected " + getUniqueDeviceName(device),
      getUniqueDeviceId(device)
    );
    // TODO adjust to send arbitrary message types sensorService.sendChannelMessage(getUniqueDeviceId(event.target.service.device.id)).push("disconnect", {"deviceid": device.id});
    ensureDeviceCleanup(device);
  }

  function ensureDeviceCleanup(device) {
    const deviceId = getUniqueDeviceId(device);
    logger.log(
      loggerCtxName,
      "Device cleanup",
      device?.id,
      deviceId,
      Array.isArray(deviceCharacteristics[deviceId])
    );

    try {
      if (deviceId && Array.isArray(deviceCharacteristics[deviceId])) {
        deviceCharacteristics[deviceId].forEach(
          function (characteristic) {
            if (characteristic) {
              characteristic.removeEventListener(
                "characteristicvaluechanged",
                handleCharacteristicChanged
              );
              //await characteristic.stopNotifications();
              logger.log(
                loggerCtxName,
                "Notifications stopped and listener removed."
              );
            }
          }
        );
        // Remove from store
        bleCharacteristics.update(current => {
          const { [deviceId]: removed, ...rest } = current;
          return rest;
        });
      }

      var channelName = deviceId;
      logger.log(loggerCtxName, "Leaving channel", channelName);
      sensorService.leaveChannel(channelName);

      bleDevices.remove(device);
      logger.log(
        loggerCtxName,
        "Devices after cleanup: ",
        devices,
        deviceCharacteristics
      );
    } catch (e) {
      logger.log(loggerCtxName, "ensureDeviceCleanup error: ", e);
    }
  }

  async function disconnectBLEDevice(device) {
    if (device.gatt.connected) {
      logger.log(
        loggerCtxName,
        "Device still connected",
        getUniqueDeviceName(device)
      );
      device.gatt.disconnect();
    } else {
      logger.log(
        loggerCtxName,
        "Device is already disconnected.",
        getUniqueDeviceName(device)
      );
    }
  }

  function getUniqueDeviceName(device) {
    if (device?.name?.startsWith("Movesense")) {
      return device?.name;
    }
    return sensorService?.getDeviceId() + ":" + device?.name;
  }

  function getUniqueDeviceId(device) {
    let name = getUniqueDeviceName(device);

    return name.replace(" ", "_");
  }

  function getDeviceSamplingRate(device) {
    if (device?.name?.startsWith("Movesense")) {
      return 1;
    }
    return 10;
  }

  function getDeviceSensorType(device) {
    if (device.name.startsWith("Movesense")) {
      return "heartrate";
    }

    if (device.name.startsWith("Flex")) {
      return "flex";
    }

    if (device.name.startsWith("Pressure")) {
      return "pressure";
    }

    return device.name;
  }

  onDestroy(() => {
    // Unsubscribe from stores but DO NOT clean up devices
    // We want them to persist across LiveView navigations
    unsubDevices();
    unsubCharacteristics();
    unsubValues();

    // Only log that we're unmounting - devices stay connected
    logger.log(loggerCtxName, "Component unmounting, BLE connections preserved", devices.length, "devices");
  });
</script>

{#if "bluetooth" in navigator && "requestLEScan" in navigator.bluetooth}
  <button on:click={requestLEScan} class="btn btn-blue text-xs"
    >Request LE Scan</button
  >
{/if}

{#if "bluetooth" in navigator}
  <button on:click={scanDevices} class="btn btn-blue text-xs">Scan BLE</button>
  <ul class="flex gap-2">
    {#each devices as device}
      <li class="text-xs">
        <button
          class="text-blue-400 hover:text-blue-300 hover:underline cursor-pointer"
          on:click={() => disconnectBLEDevice(device)}
          title="Click to disconnect"
        >{getUniqueDeviceName(device)} ✕</button>
      </li>
    {/each}
  </ul>
{/if}
