<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    import {logger} from "./logger.js";

    let sensorService = getContext("sensorService");
    let loggerCtxName = 'BluetoothClient';

    export let devices = [];
    export let deviceCharacteristics = {};
    export let characteristicValues = {};

    const dispatch = createEventDispatcher();

    async function scanDevices() {
        const newDevice = await navigator.bluetooth
            .requestDevice({
                // filters: [...] <- Prefer filters to save energy & show relevant devices.
                filters: [
                    {
                        namePrefix: "PressureSensor",
                    },
                    { namePrefix: "Movesense" },
                    { namePrefix: "BlueNRG" },
                    { namePrefix: "FlexSenseSensor" },
                    { namePrefix: "vívosmart" },
                ],
                //
                //acceptAllDevices: true,
                optionalServices: [
                    "453b02b0-71a1-11ea-ab12-0800200c9a66", // pressure
                    "heart_rate",
                    "battery_service",
                    "61353090-8231-49cc-b57a-886370740041",
                    "a688bc90-09e2-4643-8e9a-ff3076703bc3", // oximeter
                    "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
                    "897fdb8d-dec3-40bc-98e8-2310a58b0189", // flexsense
                ],
            })
            .then((device) => {
                devices = [...devices, device];
                device.addEventListener(
                    "gattserverdisconnected",
                    onDisconnected,
                );

                const sensorIdentifier = getUniqueDeviceId(device);
                const sensorType = getDeviceSensorType(device);
                const sensorSamplingRate = getDeviceSamplingRate(device);

                const metadata = {
                    sensor_name: getUniqueDeviceId(device),
                    sensor_id: device.id,
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
                            characteristics.forEach((characteristic) => {
                                if (
                                    undefined ==
                                    characteristic.startNotifications
                                ) {
                                    logger.log(loggerCtxName, 
                                        "startNotifications not supported, requires polling fallback",
                                    );
                                }

                                /*log('>> Characteristic: ' + characteristic.uuid + ' ' +
                            getSupportedProperties(characteristic));
                          */
                                queue.then((_) =>
                                    handleCharacteristic(characteristic),
                                );
                            });
                        }),
                    );
                });
                return queue;
            })
            .catch((error) => {
                logger.log(loggerCtxName, "Argh! " + error);
            });
    }

    function handleCharacteristic(characteristic) {
        logger.log(loggerCtxName, "> Service UUID:", characteristic.service.uuid);
        logger.log(loggerCtxName, "> Characteristic UUID:  " + characteristic.uuid);
        logger.log(loggerCtxName, 
            "> Broadcast:            " + characteristic.properties.broadcast,
        );
        logger.log(loggerCtxName, 
            "> Read:                 " + characteristic.properties.read,
        );
        logger.log(loggerCtxName, 
            "> Write w/o response:   " +
                characteristic.properties.writeWithoutResponse,
        );
        logger.log(loggerCtxName, 
            "> Write:                " + characteristic.properties.write,
        );
        logger.log(loggerCtxName, 
            "> Notify:               " + characteristic.properties.notify,
        );
        logger.log(loggerCtxName, 
            "> Indicate:             " + characteristic.properties.indicate,
        );
        logger.log(loggerCtxName, 
            "> Signed Write:         " +
                characteristic.properties.authenticatedSignedWrites,
        );
        logger.log(loggerCtxName, 
            "> Queued Write:         " +
                characteristic.properties.reliableWrite,
        );
        logger.log(loggerCtxName, 
            "> Writable Auxiliaries: " +
                characteristic.properties.writableAuxiliaries,
        );

        if (characteristic.properties.notify == true) {
            return characteristic
                .startNotifications()
                .then((_) => {
                    characteristic.addEventListener(
                        "characteristicvaluechanged",
                        handleCharacteristicChanged,
                    );

                    if (
                        deviceCharacteristics[
                            characteristic.service.device.id
                        ] == undefined
                    ) {
                        deviceCharacteristics[
                            characteristic.service.device.id
                        ] = [];
                    }
                    deviceCharacteristics[
                        characteristic.service.device.id
                    ].push(characteristic);

                    logger.log(loggerCtxName, 
                        "deviceCharacteristics",
                        deviceCharacteristics[characteristic.service.device.id],
                    );
                    logger.log(loggerCtxName, 
                        "Subscribed to" + characteristic.uuid,
                        characteristic,
                    );

                    return characteristic;
                })
                .then((characteristic) => {
                    if (characteristic.properties.read == true) {
                        logger.log(loggerCtxName, "Reading" + characteristic.uuid + "...");
                        return characteristic
                            .readValue()
                            .then((valueObj) => {
                                logger.log(loggerCtxName, 
                                    "Characteristic value:",
                                    characteristic.uuid,
                                    valueObj,
                                    valueObj.getInt8(0),
                                );
                                characteristicValues[characteristic.uuid] =
                                    valueObj.getInt8(0);
                            })
                            .catch((error) => {
                                console.error(
                                    "Error reading characteristic:",
                                    error,
                                );
                            });
                    }
                })
                .catch((error) => {
                    logger.log(loggerCtxName, 
                        "Argh! " + characteristic.name + " error: " + error,
                    );
                });
        }
    }

    function handleCharacteristicChanged(event) {
        let v = event.target.value;

        let sensorValue = null;
        let debounce = false;

        switch (event.target.uuid) {
            case "61d20a90-71a1-11ea-ab12-0800200c9a66":
                // pressure sensor
                sensorValue = Math.round(v.getFloat32(0, true) * 100) / 100;
                if (Math.abs(sensorValue) < 0.5) sensorValue = 0;
                debounce = true;
                break;
            case "00002a37-0000-1000-8000-00805f9b34fb":
                // Movesense heartrate
                sensorValue = v.getInt8(1);
                break;
            case "00002a38-0000-1000-8000-00805f9b34fb":
                // Movesense body sensor location
                sensorValue = v.getInt8(1);
                break;
            case "00002a19-0000-1000-8000-00805f9b34fb":
                // Movesense battery
                sensorValue = v.getInt8(0);
                break;
            case "feb7cb83-e359-4b57-abc6-628286b7a79b":
                // flexsense
                sensorValue = Math.round(v.getFloat32(0, true) * 100) / 100; //v.getFloat32(0, true);//
                debounce = true;
                break;
            default:
                logger.log(loggerCtxName, "unknown characteristic", event.target.uuid, v);
        }

        if (sensorValue !== null) {
            logger.log(loggerCtxName, "sensorValue", event.target.uuid, sensorValue);

            var payLoad = {
                payload: sensorValue,
                uuid: event.target.uuid,
                timestamp: Math.round(new Date().getTime()),
            };
            /*live.pushEvent("ingest", );*/
            if (
                debounce == false ||
                sensorValue != characteristicValues[event.target.uuid]
            ) {
                sensorService.sendChannelMessage(
                    getUniqueDeviceId(event.target.service.device),
                    payLoad,
                );
            } else {
                //logger.log(loggerCtxName, "no change", event.target.uuid, sensorValue);
            }

            characteristicValues[event.target.uuid] = sensorValue;
        }
    }

    async function onDisconnected(event) {
        var device = event.target;
        logger.log(loggerCtxName, 
            "> Bluetooth Device disconnected " + device.name,
            device.id,
        );
        // TODO adjust to send arbitrary message types sensorService.sendChannelMessage(getUniqueDeviceId(event.target.service.device.id)).push("disconnect", {"deviceid": device.id});
        ensureDeviceCleanup(device);
    }

    function ensureDeviceCleanup(device) {

        logger.log(loggerCtxName, "Device disconnected", device?.id, device);
        return;

        try {
            if (device?.id && deviceCharacteristics?.length && Array.isArray(deviceCharacteristics[device.id])) {
                deviceCharacteristics[device.id].forEach(
                    function (characteristic) {
                        if (characteristic) {
                            characteristic.removeEventListener(
                                "characteristicvaluechanged",
                                handleCharacteristicChanged,
                            );
                            //await characteristic.stopNotifications();
                            logger.log(loggerCtxName, 
                                "Notifications stopped and listener removed.",
                            );
                        }
                    },
                );
                delete deviceCharacteristics[device.id];
            }

            var channelName = getUniqueDeviceId(device);
            logger.log(loggerCtxName, "Leaving channel", channelName);
            sensorService.leaveChannel(channelName);

            devices = devices.filter((d) => d.id !== device.id);
            logger.log(loggerCtxName, 
                "Devices after cleanup: ",
                devices,
                deviceCharacteristics,
            );
        } catch (e) {
            logger.log(loggerCtxName, "ensureDeviceCleanup error: ", e);
        }
    }

    async function disconnectBLEDevice(device) {
        if (device.gatt.connected) {
            logger.log(loggerCtxName, "Device still connected", device);
            device.gatt.disconnect();
        } else {
            logger.log(loggerCtxName, "Device is already disconnected.");
        }
    }

    function getUniqueDeviceId(device) {
        if (device.name.startsWith("Movesense")) {
            return device.name;
        }
        return sensorService.getDeviceId() + ":" + device.name;
    }

    function getDeviceSamplingRate(device) {
        if (device.name.startsWith("Movesense")) {
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
        ensureDeviceCleanup();
    });
</script>

{#if "bluetooth" in navigator}
    <button on:click={scanDevices} class="btn btn-blue text-xs">Scan BLE</button
    >
    <ul class="py-3">
        {#each devices as device}
            <li>
                <strong alt="ID: {device.id}">{device.name}</strong>
                <ul>
                    {#if deviceCharacteristics[device.id]}
                        {#each deviceCharacteristics[device.id] as characteristic}
                            <li class="text-xs">
                                <p data-tooltip={characteristic.uuid}>
                                    {characteristicValues[characteristic.uuid]}
                                </p>
                                <p></p>
                            </li>
                        {/each}
                    {:else}
                        <li>No attributes</li>
                    {/if}
                </ul>
                <button
                    class="btn btn-blue text-xs"
                    on:click={() => disconnectBLEDevice(device)}>Bye</button
                >
            </li>
        {/each}
    </ul>
{/if}
