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

  export let compact = false;

  let sensorService = getContext("sensorService");
  let loggerCtxName = "BluetoothClient";

  // Thingy:52 motion characteristic UUIDs - defined early for use in scanDevices
  const MOTION_CONFIG_UUID = "ef68030a-9b35-4933-9b10-52ffa9740042";
  const QUATERNION_UUID = "ef680303-9b35-4933-9b10-52ffa9740042";
  const EULER_UUID = "ef680306-9b35-4933-9b10-52ffa9740042";
  const RAW_MOTION_UUID = "ef680305-9b35-4933-9b10-52ffa9740042";

  // Polling intervals for read-only characteristics (like some Thingy IMU chars)
  const pollingIntervals = new Map();
  const IMU_POLL_INTERVAL_MS = 100; // 10Hz polling for IMU

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
            service.getCharacteristics().then(async (characteristics) => {
              logger.log(loggerCtxName, "characteristics", characteristics);

              // IMPORTANT: First, find and configure motion config before other characteristics
              // This ensures motion processing is enabled before we subscribe to IMU notifications
              const motionConfigChar = characteristics.find(
                c => c.uuid.toLowerCase() === MOTION_CONFIG_UUID
              );
              if (motionConfigChar) {
                logger.log(loggerCtxName, "Found motion config, configuring FIRST...");
                await configureThingyMotion(motionConfigChar);
                logger.log(loggerCtxName, "Motion config done, now processing other characteristics");
              }

              // Now process all other characteristics
              for (const characteristic of characteristics) {
                // Skip motion config since we already handled it
                if (characteristic.uuid.toLowerCase() === MOTION_CONFIG_UUID) {
                  continue;
                }

                await handleCharacteristic(characteristic);
              }
            })
          );
        });
        return queue;
      })
      .catch((error) => {
        logger.log(loggerCtxName, "Argh! " + error);
      });
  }

  // Configure Thingy:52 motion service to enable IMU data
  async function configureThingyMotion(characteristic) {
    if (characteristic.uuid.toLowerCase() !== MOTION_CONFIG_UUID) return;

    logger.log(loggerCtxName, "Motion config characteristic found!", {
      uuid: characteristic.uuid,
      read: characteristic.properties.read,
      write: characteristic.properties.write,
      writeWithoutResponse: characteristic.properties.writeWithoutResponse,
      notify: characteristic.properties.notify
    });

    if (!characteristic.properties.write && !characteristic.properties.writeWithoutResponse) {
      logger.log(loggerCtxName, "Motion config characteristic not writable");
      return;
    }

    try {
      // Motion config format (9 bytes):
      // - Step counter interval: 100ms (uint16 LE)
      // - Temp compensation interval: 5000ms (uint16 LE)
      // - Mag compensation interval: 5000ms (uint16 LE)
      // - Motion processing freq: 20Hz (uint16 LE) - enables quaternion/euler output
      // - Wake on motion: 0 (uint8)
      const config = new Uint8Array([
        0x64, 0x00,  // Step interval: 100ms
        0x88, 0x13,  // Temp comp: 5000ms
        0x88, 0x13,  // Mag comp: 5000ms
        0x14, 0x00,  // Motion freq: 20Hz (enables motion processing!)
        0x00         // Wake on motion: off
      ]);

      logger.log(loggerCtxName, "Configuring Thingy motion at 20Hz...");
      await characteristic.writeValue(config);
      logger.log(loggerCtxName, "Thingy motion configured successfully!");
    } catch (error) {
      logger.log(loggerCtxName, "Failed to configure Thingy motion:", error);
    }
  }

  function handleCharacteristic(characteristic) {
    // Handle motion configuration characteristic - write to enable motion
    if (characteristic.uuid.toLowerCase() === MOTION_CONFIG_UUID) {
      configureThingyMotion(characteristic);
      return;  // Don't register as a sensor attribute
    }

    // Log IMU characteristic properties for debugging
    const uuid = characteristic.uuid.toLowerCase();
    if (uuid === QUATERNION_UUID || uuid === EULER_UUID || uuid === RAW_MOTION_UUID) {
      logger.log(loggerCtxName, "IMU characteristic found!", {
        name: BluetoothUtils.name(characteristic.uuid),
        uuid: characteristic.uuid,
        read: characteristic.properties.read,
        write: characteristic.properties.write,
        notify: characteristic.properties.notify,
        indicate: characteristic.properties.indicate
      });
    }

    // Skip other config-only characteristics that never produce readable data
    if (BluetoothUtils.isConfigOnly(characteristic.uuid)) {
      logger.log(
        loggerCtxName,
        "Skipping config-only characteristic: " + BluetoothUtils.name(characteristic.uuid)
      );
      return;
    }

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

    // Handle both notify and indicate - startNotifications() works for both
    if (characteristic.properties.notify == true || characteristic.properties.indicate == true) {
      const charUuid = characteristic.uuid.toLowerCase();
      const isIMU = charUuid === QUATERNION_UUID || charUuid === EULER_UUID || charUuid === RAW_MOTION_UUID;
      if (isIMU) {
        logger.log(loggerCtxName, "IMU starting notifications...", BluetoothUtils.name(characteristic.uuid));
      }

      return characteristic
        .startNotifications()
        .then((_) => {
          if (isIMU) {
            logger.log(loggerCtxName, "IMU notifications STARTED!", BluetoothUtils.name(characteristic.uuid));
          }
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

          return characteristic;
        })
        .then((characteristic) => {
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
          if (isIMU) {
            logger.log(loggerCtxName, "IMU notification FAILED!", BluetoothUtils.name(characteristic.uuid), error);
          } else {
            logger.log(
              loggerCtxName,
              "Argh! " + characteristic.name + " error: " + error
            );
          }
        });
    } else if (characteristic.properties.read == true) {
      const charUuid = characteristic.uuid.toLowerCase();
      const isIMU = charUuid === QUATERNION_UUID || charUuid === EULER_UUID || charUuid === RAW_MOTION_UUID;

      if (isIMU) {
        logger.log(loggerCtxName, "IMU using POLLING (no notify)", BluetoothUtils.name(characteristic.uuid));
        startPollingCharacteristic(characteristic);
        return;
      }

      return characteristic
        .readValue()
        .then((valueObj) => {
          let decodedValue = BluetoothUtils.decodeValue(characteristic.uuid, valueObj);
          if (decodedValue === null) {
            decodedValue = valueObj.getInt8(0);
          }
          characteristicValue = decodedValue;
          bleValues.setValue(characteristic.uuid, characteristicValue);
          const normalizedAttrId = BluetoothUtils.normalizedType(characteristic.uuid);
          var payLoad = {
            payload: characteristicValue,
            attribute_id: normalizedAttrId,
            timestamp: Math.round(new Date().getTime()),
          };
          sensorService.sendChannelMessage(
            getUniqueDeviceId(characteristic.service.device),
            payLoad
          );
        })
        .catch((error) => {
          logger.log(loggerCtxName, "Argh! " + characteristic.name + " error: " + error);
        });
    } else {
      const charUuid = characteristic.uuid.toLowerCase();
      if (charUuid === QUATERNION_UUID || charUuid === EULER_UUID || charUuid === RAW_MOTION_UUID) {
        logger.log(loggerCtxName, "WARNING: IMU has NO notify, indicate, or read!", {
          name: BluetoothUtils.name(characteristic.uuid),
          properties: characteristic.properties
        });
      }
    }
  }

  // Start polling a read-only characteristic (used for IMU when notify not available)
  function startPollingCharacteristic(characteristic) {
    const deviceId = getUniqueDeviceId(characteristic.service.device);
    const charKey = `${deviceId}:${characteristic.uuid}`;

    if (pollingIntervals.has(charKey)) {
      logger.log(loggerCtxName, "Polling already active for", charKey);
      return;
    }

    const pollFn = async () => {
      try {
        if (!characteristic.service.device.gatt?.connected) {
          stopPollingCharacteristic(charKey);
          return;
        }

        const valueObj = await characteristic.readValue();
        let decodedValue = BluetoothUtils.decodeValue(characteristic.uuid, valueObj);

        if (decodedValue === null && valueObj.byteLength > 0) {
          decodedValue = valueObj.getInt8(0);
        }

        if (decodedValue !== null) {
          bleValues.setValue(characteristic.uuid, decodedValue);
          const normalizedAttrId = BluetoothUtils.normalizedType(characteristic.uuid);
          const payLoad = {
            payload: decodedValue,
            attribute_id: normalizedAttrId,
            timestamp: Math.round(new Date().getTime()),
          };
          sensorService.sendChannelMessage(deviceId, payLoad);
        }
      } catch (error) {
        logger.log(loggerCtxName, "Poll error for", BluetoothUtils.name(characteristic.uuid), error.message);
        if (error.message?.includes('disconnected') || error.message?.includes('not connected')) {
          stopPollingCharacteristic(charKey);
        }
      }
    };

    const intervalId = setInterval(pollFn, IMU_POLL_INTERVAL_MS);
    pollingIntervals.set(charKey, intervalId);
    logger.log(loggerCtxName, "Started polling", BluetoothUtils.name(characteristic.uuid), "at", IMU_POLL_INTERVAL_MS, "ms");

    pollFn();
  }

  function stopPollingCharacteristic(charKey) {
    const intervalId = pollingIntervals.get(charKey);
    if (intervalId) {
      clearInterval(intervalId);
      pollingIntervals.delete(charKey);
      logger.log(loggerCtxName, "Stopped polling", charKey);
    }
  }

  function stopAllPollingForDevice(deviceId) {
    for (const [key, intervalId] of pollingIntervals.entries()) {
      if (key.startsWith(deviceId + ':')) {
        clearInterval(intervalId);
        pollingIntervals.delete(key);
        logger.log(loggerCtxName, "Stopped polling", key);
      }
    }
  }

  function handleCharacteristicChanged(event) {
    let v = event.target.value;

    let sensorValue = null;
    let debounce = false;

    // Debug logging for IMU characteristics only
    const uuid = event.target.uuid.toLowerCase();
    if (uuid === QUATERNION_UUID || uuid === EULER_UUID || uuid === RAW_MOTION_UUID) {
      logger.log(loggerCtxName, "IMU notification!", BluetoothUtils.name(event.target.uuid), "bytes:", v?.byteLength);
    }

    sensorValue = BluetoothUtils.decodeValue(event.target.uuid, v);

    sensorType = "unknown";

    // Handle special cases
    if (event.target.uuid === "feb7cb83-e359-4b57-abc6-628286b7a79b") {
      // flexsense
      sensorValue = Math.round(v.getFloat32(0, true) * 100) / 100;
      debounce = true;
    }

    if (sensorValue !== null) {

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

    // Stop any polling intervals for this device
    if (deviceId) {
      stopAllPollingForDevice(deviceId);
    }

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

{#if "bluetooth" in navigator}
  {#if compact}
    <button
      on:click={scanDevices}
      class="icon-btn"
      class:active={devices.length > 0}
      title={devices.length > 0 ? `${devices.length} BLE device(s) connected` : "Scan BLE devices"}
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
        <path d="M12.75 2v6.568l3.22-2.79a.75.75 0 01.98 1.136l-4.2 3.636 4.2 3.636a.75.75 0 01-.98 1.136l-3.22-2.79V22a.75.75 0 01-1.28.53l-4.72-4.72a.75.75 0 010-1.06l4-4-4-4a.75.75 0 010-1.06l4.72-4.72a.75.75 0 011.28.53z"/>
      </svg>
      {#if devices.length > 0}
        <span class="badge">{devices.length}</span>
      {/if}
    </button>
  {:else}
    {#if "requestLEScan" in navigator.bluetooth}
      <button on:click={requestLEScan} class="btn btn-blue text-xs">Request LE Scan</button>
    {/if}
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
{/if}

<style>
  .icon-btn {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 0.375rem;
    background: #374151;
    color: #9ca3af;
    border: none;
    cursor: pointer;
    transition: all 0.15s ease;
  }
  .icon-btn:hover {
    background: #4b5563;
    color: #d1d5db;
  }
  .icon-btn.active {
    background: #2563eb;
    color: white;
  }
  .badge {
    position: absolute;
    top: -0.25rem;
    right: -0.25rem;
    min-width: 0.875rem;
    height: 0.875rem;
    padding: 0 0.25rem;
    font-size: 0.5rem;
    font-weight: 600;
    background: #22c55e;
    color: white;
    border-radius: 9999px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
</style>
