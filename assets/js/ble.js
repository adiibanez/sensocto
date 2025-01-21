import socket from "./socket"
//import {RadialGauge, LinearGauge} from "canvas-gauges"

// required due to async functions
// most probably due to webpack == ES2015 / browser == ES6
import "regenerator-runtime";
import {v4 as uuidv4} from 'uuid';

import Cookies from 'js-cookie'

export const setupBleGui = () => {
    const bleGui = document.querySelector('#bleGui');

    if (bleGui) {
        //var cookies = cookie.parse(document.cookie);
        //console.log(cookies);

        let simulatorInterval = null;

        var sensorSimValues = [
            [0.0, 0.0, 0.3, 0.5, 0.7, 10.5, 12.2, 11.3, 10.1, 8.5, 10.5, 10.3, 10.8, 10.9, 10.1, 10.2, 5.3, 0.3, 0.0, 0.0, 0.0, -0.1, -0.3, -0.5, -1, -1, -1.2, -1.3, -0.3, -0.2, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.3, 0.5, 0.7, 10, 25.2, 25.1, 25.5, 25.8, 25.4, 25.2, 25.6, 25.2, 25.2, 10.1, 5.2, 0.3, 0.0, 0.0, 0.0, -0.1, -0.3, -0.5, -1, -1.5, -1.3, -1.2, -0.3, -0.2, 0.0, 0.0, 0.0, 0.0],
        ]

        let simSetIndex = 0;
        let simValueIndex = 0;

        let pressureValuePoller = null;
        let lastMeasurementReportedType = null;

        let lastHeartbeatMeasurement = null;
        let lastHeartbeatTimestamp = null;

        let animationDuration = null;
        let animationTimeout = null;

        // interval in ms
        let imuSimulatorInterval = 30;
        let imuSimulatorTimestamp = null;

        var deviceId = Cookies.get('deviceId');

        var sensors = {};

        console.log('deviceId: ', deviceId);

        if (deviceId == null) {
            deviceId = uuidv4();

            //var expiration = new Date();
            //expiration.setDate(expiration.getDate() + 365 * 10);

            //cookie.serialize('deviceId', deviceId, {expires: expiration});
            //Cookies.set('deviceId', deviceId, { expires: 365 * 10, path: '' })
        }

        document.querySelector('#uuid').textContent = "UUID: " + deviceId;

        // https://hexdocs.pm/phoenix/js/
        let channel = socket.channel("sensor_data:lobby", {
            "auth": "_819_slaMNhshsls99_()",
            "device_id": deviceId,
            "type": "player",
            "device_description": window.navigator.userAgent
        });

        channel.join()
            .receive("ok", resp => {
                console.log("Joined successfully", resp)
            })
            .receive("error", resp => {
                console.log("Unable to join", resp)
            })

        //channel.push('measurement', {'type': 'INHALE', 'value': 1.1, 'timestamp': Math.round((new Date()).getTime() / 1000) });

        var messages = [];
        var msgCount = 10;

        var log = function (msg) {
            console.log(msg);

            messages.push(msg);
            messages = messages.slice(Math.max(0, messages.length - msgCount));
            document.querySelector('#log').textContent = messages.join('\n');
        };

        if (navigator.bluetooth !== undefined) {
            log('Web bluetooth supported');
        } else {
            log('Web bluetooth is not supported, sorry. Use chrome or edge browser. Or WebBLE app on iOs');
        }

        var bluetoothDevicePressure;
        var bluetoothDeviceMovesense;

        var pressureCharacteristic;
        var heartRateCharacteristic;
        var bodyCharacteristic;
        var batteryCharacteristic;
        var flexSenseCharacteristic;

        async function getPressureValue() {
            if (pressureCharacteristic) {
                await pressureCharacteristic.readValue();
            }
        }

        async function onPrepareDeviceClick() {
            if (!bluetoothDevicePressure || !bluetoothDeviceMovesense) {
                await requestDevice();
            }
        }

        async function requestDevice() {
            log('Requesting any Bluetooth Device...');
            var ctx = {};
            navigator.bluetooth.requestDevice({
                // filters: [...] <- Prefer filters to save energy & show relevant devices.
                filters: [{namePrefix: "PressureSensor"}, {namePrefix: 'Movesense'}, {namePrefix: "BlueNRG"}, {namePrefix: "FlexSenseSensor"}, {namePrefix: "vívosmart"}],
                //
                //acceptAllDevices: true,
                optionalServices: [
                    '453b02b0-71a1-11ea-ab12-0800200c9a66', // pressure
                    'heart_rate',
                    'battery_service',
                    '61353090-8231-49cc-b57a-886370740041',
                    'a688bc90-09e2-4643-8e9a-ff3076703bc3', // oximeter
                    '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
                    '897fdb8d-dec3-40bc-98e8-2310a58b0189' // flexsense
                ]
            }).then(device => {
                sensors[device.id] = device;
                device.addEventListener('gattserverdisconnected', onDisconnected);

                log('Connecting to GATT Server...');
                return device.gatt.connect();

            }).then(server => {
                //console.log('server', server);
                return server.getPrimaryServices();
            }).then(services => {
                //log('Getting Characteristics...');
                let queue = Promise.resolve();
                services.forEach(service => {
                    console.log('service', service);

                    queue = queue.then(_ => service.getCharacteristics().then(characteristics => {
                        //log('> Service: ' + service.uuid);
                        characteristics.forEach(characteristic => {
                            if (undefined == characteristic.startNotifications) {
                                log('startNotifications not supported, requires polling fallback');
                            }
                            /*log('>> Characteristic: ' + characteristic.uuid + ' ' +
                                getSupportedProperties(characteristic));
                             */
                            queue.then(_ => handleCharacteristic(characteristic));
                        });
                    }));
                });
                return queue;
            }).catch(error => {
                log('Argh! ' + error);
            });
        }

        function handleCharacteristic(characteristic) {

            switch (characteristic.uuid) {
                case '61d20a90-71a1-11ea-ab12-0800200c9a66':
                    log('> pressure handler registration', characteristic);
                    pressureCharacteristic = characteristic;
                    return characteristic.startNotifications().then(c => {
                        log('> pressure handler notifications started');
                        c.addEventListener('characteristicvaluechanged', handlePressureChanged);
                        sendSensorDiscoveryMessage('pressure', 'NEUTRAL');
                        document.querySelector('#gauge').classList.add('active');
                    }).catch(error => {
                        log('Argh! ' + characteristic.uuid + " error: " + error);
                    });
                    break;
                case 'd0b02e79-854a-4129-9475-7610e938a4dc':
                    log('> body handler registration', characteristic);
                    bodyCharacteristic = characteristic;
                    return characteristic.startNotifications().then(_ => {
                        log('> body handler notifications started');
                        characteristic.addEventListener('characteristicvaluechanged', handleBodyChanged);
                        sendSensorDiscoveryMessage('body');
                        document.querySelector("#oximeter").classList.add('active');
                    }).catch(error => {
                        log('Argh! ' + characteristic.name + " error: " + error);
                    });
                    break;
                case 'feb7cb83-e359-4b57-abc6-628286b7a79b':
                    log('> flexsense handler registration', characteristic);
                    flexSenseCharacteristic = characteristic;
                    return characteristic.startNotifications().then(_ => {
                        log('> flexsense handler notifications started');
                        characteristic.addEventListener('characteristicvaluechanged', handleFlexSenseChanged);
                        sendSensorDiscoveryMessage('flexsense');
                        document.querySelector("#flexsense").classList.add('active');
                    }).catch(error => {
                        log('Argh! ' + characteristic.name + " error: " + error);
                    });
                    break;

                case '00002a37-0000-1000-8000-00805f9b34fb':
                    log('> Movesense heartrate handler registration');
                    heartRateCharacteristic = characteristic;
                    return characteristic.startNotifications().then(c => {
                        log('> Movesense heartrate notifications started');
                        c.addEventListener('characteristicvaluechanged', handleHeartrateChanged);
                        sendSensorDiscoveryMessage('heartrate');
                        document.querySelector('#heart').classList.add('active');
                    }).catch(error => {
                        log('Argh! ' + characteristic.uuid + " error: " + error);
                    });
                    break;
                case '___00002a19-0000-1000-8000-00805f9b34fb':
                    log('> Movesense battery handler registration');
                    batteryCharacteristic = characteristic;
                    return characteristic.startNotifications().then(c => {
                        log('> Movesense battery notifications started');
                        c.addEventListener('characteristicvaluechanged', handleBatteryLevelChanged);
                        //sendSensorDiscoveryMessage('heartrate_battery');
                    }).catch(error => {
                        log('Argh! ' + characteristic.name + " error: " + error);
                    });
                    break;

                default:
                //return characteristic;
                    console.log('unknown characteristic', characteristic);
            }

        }

        function sendSensorDisconnectMessage(type) {
            channel.push('disconnect', {
                'type': type,
                'timestamp': Math.round((new Date()).getTime())
            });
        }

        function sendSensorDiscoveryMessage(type, state = null, value = null) {
            channel.push('discovery', {
                'type': type,
                'state': state,
                'value': value,
                'timestamp': Math.round((new Date()).getTime())
            });
        }

        function getSupportedProperties(characteristic) {
            let supportedProperties = [];
            for (const p in characteristic.properties) {
                if (characteristic.properties[p] === true) {
                    supportedProperties.push(p.toUpperCase());
                }
            }
            return '[' + supportedProperties.join(', ') + ']';
        }

        var pfx = ["webkit", "moz", "MS", "o", ""];

        function PrefixedEvent(element, type, callback, add = true) {
            for (var p = 0; p < pfx.length; p++) {
                if (!pfx[p]) type = type.toLowerCase();
                if (add) {
                    element.addEventListener(pfx[p] + type, callback, false);
                } else {
                    element.removeEventListener(pfx[p] + type, callback);
                }
            }
        }

        function onHeartAnimationEnd(event) {

            var hrClassName = (Math.round((new Date()).getTime()) - lastHeartbeatTimestamp < 3000) ? 'hrpulse' : 'hrvoid';

            //console.log('heartanimation end', animationTimeout, lastHeartbeatTimestamp, );

            document.querySelector('#heart').classList.remove('hrpulse');
            document.querySelector('#heart').classList.remove('hrvoid');

            if (animationDuration != null) {
                animationTimeout = setTimeout(function () {

                    clearTimeout(animationTimeout);

                    //console.log('hrpulse timeout exec', animationDuration);
                    document.querySelector('#heart').classList.add(hrClassName);

                }, animationDuration * 1000);
            }
        }

        function roundFloat(number) {
            return Math.round(number * 100) / 100;
        }

        function handleHeartrateChanged(event) {
            let v = event.target.value;

            if (animationDuration == null) {
                console.log('add initial class');
                document.querySelector('#heart').classList.add('hrpulse');
                PrefixedEvent(document.querySelector('#heart'), "AnimationEnd", onHeartAnimationEnd);
            }

            var heartRate = v.getInt8(1);
            //log('> heartrate ' + v);

            lastHeartbeatMeasurement = heartRate;
            lastHeartbeatTimestamp = Math.round((new Date()).getTime());

            channel.push('measurement', {
                'type': 'heartrate',
                'state': 0,
                'value': v.getInt8(1),
                'timestamp': Math.round((new Date()).getTime())
            });

            // calculate time until next pulse
            animationDuration = roundFloat(Math.max(0, (60 / heartRate) - 0.3));

            document.querySelector('#heartrate').textContent = 'HR: ' + heartRate + 'bpm';

            //console.log('heartrate', v.byteLength, v.getInt8(1), animationDuration);
            //console.log('test', document.querySelector('#animateTransform').getAttribute('dur'));
        }

        function handleBodyChanged(event) {
            let v = event.target.value;
            //let pressureLevel = Math.round(v.getFloat32(0, true) * 100) / 100; //v.getFloat32(0, true);//
            //console.log('body single bytes', v.byteLength, v.getInt8(0), v.getInt8(1), v.getInt8(2), v.getInt8(3));

            var state = v.getInt8(0);
            var heartrate = v.getInt8(1);
            var spo2 = v.getInt8(2);
            var confidence = v.getInt8(3);

            var statusText = '';
            var instructionText = '';

            switch (state) {
                case 0:
                    statusText = 'No object detected';
                    instructionText = 'Place finger on sensor to measure';
                    document.querySelector("#oximeter").classList.remove('ready');
                    break;
                case 1:
                    statusText = 'Object detected';
                case 2:
                    statusText = 'Object other than finger detected';
                    instructionText = 'Collecting data';
                    document.querySelector("#oximeter").classList.remove('ready');
                    break;
                case 3:
                    statusText = 'Finger detected';
                    document.querySelector("#oximeter").classList.add('ready');
            }

            channel.push('measurement', {
                'type': 'body',
                'state': state,
                'value': {state: state, hr: heartrate, spo2: spo2, c: confidence},
                'timestamp': Math.round((new Date()).getTime())
            });
            // v.getInt32(0),

            document.querySelector("#oximeter .status").textContent = statusText;
            document.querySelector("#oximeter .heartrate").textContent = heartrate + 'bpm';
            document.querySelector("#oximeter .spo2").textContent = spo2 + '%';
            document.querySelector("#oximeter .confidence").textContent = confidence + '%';
            document.querySelector("#oximeter .instruction").textContent = instructionText;
        }

        function handlePressureChanged(event) {
            let v = event.target.value;
            let pressureLevel = Math.round(v.getFloat32(0, true) * 100) / 100; //v.getFloat32(0, true);//
            //console.log('test single bytes', v.getInt8(0), v.getInt8(1), v.getInt8(2), v.getInt8(3));
            //log('> pressure ' + pressureLevel);

            processPressureUpdate(pressureLevel);
        }

        function handleFlexSenseChanged(event) {
            let v = event.target.value;
            let flexSenseLevel = Math.round(v.getFloat32(0, true) * 100) / 100; //v.getFloat32(0, true);//
            //console.log('test single bytes', v.getInt8(0), v.getInt8(1), v.getInt8(2), v.getInt8(3));
            //log('> flex ' + flexSenseLevel);
            document.querySelector("#flexsense").innerHTML = flexSenseLevel + '%';

            channel.push('measurement', {
                'type': 'flexsense',
                'state': 0,
                'value': flexSenseLevel,
                'timestamp': Math.round((new Date()).getTime())
            });
        }

        function processPressureUpdate(pressureLevel, threshHold = 0.1) {
            updateSvgGaugeValue(pressureLevel);

            var measurementType = 'NEUTRAL';

            if (pressureLevel >= threshHold) {
                measurementType = 'EXHALE';
            }

            if (pressureLevel <= -threshHold) {
                measurementType = 'INHALE';
            }

            // push anything breathing or first neutral measurement
            if (measurementType != 'NEUTRAL' || lastMeasurementReportedType != 'NEUTRAL') {
                channel.push('measurement', {
                    'type': 'pressure',
                    'state': measurementType,
                    'value': pressureLevel,
                    'timestamp': Math.round((new Date()).getTime())
                });
                lastMeasurementReportedType = measurementType;
            }
        }

        function handleBatteryLevelChanged(event) {
            let v = event.target.value;
            console.log('battery level', v.byteLength, v.getInt8(0));
            document.querySelector("#heartrate_battery").textContent = 'Bat:' + v.getInt8(0) + '%';
        }

        function updateSvgGaugeValue(value) {
            var matrix = getSvgGaugeTransform(value);
            document.querySelector('#pressure').textContent = 'mbar: ' + value;
            document.getElementById("gauge_needle").setAttribute("transform", matrix);
        }

        function getSvgGaugeTransform(pressure) {

            var x = 115.92;
            var y = 115.65;

            var maxAngle = 298;

            var angle = 1 / 50 * pressure * maxAngle;
            var realAngle = angle;

            //console.log('realAngle', realAngle, 'angle', angle, 'pressure', pressure);

            var ca = Math.cos(realAngle * Math.PI / 180);
            var sa = Math.sin(realAngle * Math.PI / 180);

            var matrix = "matrix( " + ca + "," + sa + "," + -sa + "," + ca + ", " +
                (-ca * x + sa * y + x) + "," + (-sa * x - ca * y + y) + " )";

            //console.log("matrix", matrix);

            return matrix;
        }

        function handleImuPressureSimulator(event) {
            if (document.querySelector("#imu").checked) {
                if (window.DeviceMotionEvent) {
                    log('> pressure simulator notifications started');
                    sendSensorDiscoveryMessage('pressure', 'NEUTRAL');

                    //window.addEventListener("devicemotion", handleMotion, false);
                    window.addEventListener("deviceorientation", handleOrientation, false);
                    document.querySelector('#gauge').classList.add('active');
                } else {
                    log('> IMU not supported. can\'t start simulator');
                }
            } else {
                log('> pressure simulator notifications stopped');
                document.querySelector('#gauge').classList.remove('active');
            }
        }

        function handleMotion(event) {
            if (!document.querySelector('#imu').checked) return;
            console.log('Accelorometer: '
                + event.accelerationIncludingGravity.x + ', '
                + event.accelerationIncludingGravity.y + ', '
                + event.accelerationIncludingGravity.z
            );
        }

        function convertRange(value, r1, r2) {
            return (value - r1[0]) * (r2[1] - r2[0]) / (r1[1] - r1[0]) + r2[0];
        }

        function handleOrientation(event) {
            if (!document.querySelector('#imu').checked) return;

            if ((new Date()).getTime() - imuSimulatorTimestamp > imuSimulatorInterval) {
                console.log('Orientation alpha, beta, gamma: '
                    + event.alpha + ', '
                    + event.beta + ', '
                    + event.gamma);
                if(Math.abs(event.beta) > 1) {
                    var pressureLevel = 0;
                    if(event.beta > 0) {
                        pressureLevel = Math.min(50, event.beta);
                    } else {
                        pressureLevel = Math.max(-10, event.beta);
                    }

                    processPressureUpdate(roundFloat(pressureLevel));
                } else {
                    processPressureUpdate(0);
                }

                document.querySelector('#imu_state').textContent = roundFloat(event.beta);
            }
        }

        async function onDisconnected(event) {

            var device = event.target;

            console.log('> Bluetooth Device disconnected ' + device.name);
            console.log('disconnect device', device.name);

            if (device.name.startsWith('PressureSensor')) {

                sendSensorDisconnectMessage('pressure');
                sendSensorDisconnectMessage('body');

                document.querySelector('#gauge').classList.remove('active');
                document.querySelector("#oximeter").classList.remove('active');
                document.querySelector("#oximeter").classList.remove('ready');
                document.querySelector('#pressure').textContent = '';

                document.querySelector("#oximeter .status").textContent = '';
                document.querySelector("#oximeter .instruction").textContent = '';

            } else if (device.name.startsWith('Movesense')) {
                sendSensorDisconnectMessage('heartrate');

                document.querySelector('#heart').classList.remove('active');
                document.querySelector('#heartrate').textContent = '';

                clearTimeout(animationTimeout);
                animationTimeout = null;
                document.querySelector('#heart').classList.remove('hrpulse');
            } else if (device.name.startsWith('FlexSenseSensor')) {
                sendSensorDisconnectMessage('flexsense');
                document.querySelector('#flexsense').classList.remove('active');
                document.querySelector('#flexsense').innerHTML = '';
            }
        }

        async function onUnload() {

            if (pressureCharacteristic) {
                pressureCharacteristic.stopNotifications();
            }

            if (heartRateCharacteristic) {
                heartRateCharacteristic.stopNotifications();
            }

            if (bodyCharacteristic) {
                bodyCharacteristic.stopNotifications();
            }

            if (flexSenseCharacteristic) {
                flexSenseCharacteristic.stopNotifications();
            }
        }

        document.querySelector('body').addEventListener('unload', onUnload);
        document.querySelector('#prepareDevice').addEventListener('click', onPrepareDeviceClick);
        document.querySelector('#imu').addEventListener('change', handleImuPressureSimulator);
    }
}