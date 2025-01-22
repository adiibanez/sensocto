# stream_ecg.py
import neurokit2 as nk
import numpy as np
import pandas as pd
import asyncio
import logging

from numpy.lib.recfunctions import join_by

from python_phoenix_client import PhoenixChannelClient
import requests
import time
import argparse
import random
import uuid

logging.basicConfig(level=logging.INFO)  # Set Logging Level
save_path = "/home/jovyan"


def generate_heart_rate(duration, sampling_rate, avg_heart_rate=70, variability=3, tidal_amplitude=50):
    """Generates heart rate data with a tidal trend, sinusoidal variation, and random noise."""
    num_samples = int(duration * sampling_rate)
    time_points = np.linspace(0, duration, num_samples)

    # Tidal trend (slow sinusoidal variation)
    tidal_trend = np.sin(2 * np.pi * 0.01 * time_points) * tidal_amplitude

    # Sinusoidal variation
    sinusoid = np.sin(2 * np.pi * 0.1 * time_points) * variability

    # Random noise
    noise = np.random.normal(0, variability / 3, num_samples)

    heart_rate_values = avg_heart_rate + tidal_trend + sinusoid + noise
    heart_rate_values = np.clip(heart_rate_values, 30, 220)  # Clip to a reasonable range
    return heart_rate_values


def generate_sensor_data(duration, sampling_rate, sensor_type, heart_rate=None, respiratory_rate=None, scr_number=None,
                         burst_number=None):
    """Generates synthetic biosignal data based on sensor_type."""
    if sensor_type == "ecg":
        ecg = nk.ecg_simulate(duration=duration, sampling_rate=sampling_rate,
                              heart_rate=heart_rate if heart_rate else 70)
        return pd.DataFrame({"ECG": ecg})
    elif sensor_type == "ppg":
        ppg = nk.ppg_simulate(duration=duration, sampling_rate=sampling_rate,
                              heart_rate=heart_rate if heart_rate else 70)
        return pd.DataFrame({"PPG": ppg})
    elif sensor_type == "rsp":
        rsp = nk.rsp_simulate(duration=duration, sampling_rate=sampling_rate,
                              respiratory_rate=respiratory_rate if respiratory_rate else 15)
        return pd.DataFrame({"RSP": rsp})
    elif sensor_type == "eda":
        eda = nk.eda_simulate(duration=duration, sampling_rate=sampling_rate,
                              scr_number=scr_number if scr_number else 5)
        return pd.DataFrame({"EDA": eda})
    elif sensor_type == "emg":
        emg = nk.emg_simulate(duration=duration, sampling_rate=sampling_rate,
                              burst_number=burst_number if burst_number else 5)
        return pd.DataFrame({"EMG": emg})
    elif sensor_type == "heartrate":
        hr_values = generate_heart_rate(duration, sampling_rate, heart_rate if heart_rate else 70)
        return pd.DataFrame({"HeartRate": hr_values})
    else:
        raise ValueError(f"Unsupported sensor type: {sensor_type}")


def time_delta(samples, delta, noise_range_percentage=1):
    dt_list = [delta] * samples
    noise_number = (delta) / 100 * noise_range_percentage
    noise_range = (-noise_number, noise_number)
    dt_list_noisy = [x + np.random.uniform(*noise_range) for x in dt_list]
    return dt_list, dt_list_noisy


async def stream_sensor_data(client, sensor_id, events):
    for event in events:
        payload = {
            'timestamp': int(time.time() * 1000),
            'payload': event['payload'],
            'uuid': event['sensor_type']
        }
        print(payload)
        try:
            await client.push(f"sensor_data:{sensor_id}", "measurement", payload)
        except Exception as e:
            logging.error(f"Error pushing message: {e}")
            return
        await asyncio.sleep(event['delay'])


def handle_message(topic, event, payload):
    logging.info(f"Received message on topic: {topic}, event: {event}, payload: {payload}")


async def send_sensor_data(client, sensor_id, sensor_type, duration, sampling_rate, heart_rate=None,
                           respiratory_rate=None,
                           scr_number=None, burst_number=None):
    """Generates and sends data for a given sensor type."""
    events = []
    # Generate the synthetic data based on sensor_type
    data_df = generate_sensor_data(duration, sampling_rate, sensor_type, heart_rate, respiratory_rate, scr_number,
                                   burst_number)

    if sensor_type == "heartrate":
        hr = data_df["HeartRate"].tolist()
        last_hr = None
        last_send_time = 0  # initialize before the loop
        for i, point in enumerate(hr):
            point = round(point)  # round the data
            if last_hr is None or abs(point - last_hr) > 1:
                current_time = time.time()
                delay = random.uniform(0.9, 2.1)  # slightly randomize the delay
                events.append({'delay': delay, 'payload': point, 'sensor_type': sensor_type})
                last_hr = point
                last_send_time = current_time


    else:
        signal = data_df[data_df.columns[0]].tolist()  # get the signal column as a list
        # calculate the time deltas
        delta = 1000 / sampling_rate  # milliseconds
        dt_list, _ = time_delta(len(signal), delta, noise_range_percentage=1)
        time_deltas = np.array(dt_list)
        for i, point in enumerate(signal):
            events.append({'delay': time_deltas[i] / 1000, 'payload': point, 'sensor_type': sensor_type})

    logging.info(f"Start streaming {sensor_type} data")
    await stream_sensor_data(client, sensor_id, events)

    logging.info("Finished sending data")


async def main():
    parser = argparse.ArgumentParser(description="Stream sensor data to Phoenix.")
    parser.add_argument("sensor_id", type=str, help="Sensor identifier, SimulatorXY")
    parser.add_argument("sensor_type", type=str,
                        help="The sensor type to simulate (ecg, ppg, rsp, eda, emg, heartrate).")
    parser.add_argument("--duration", type=int, default=10, help="Duration of the simulation in seconds.")
    parser.add_argument("--sampling_rate", type=int, default=20, help="Sampling rate of the sensor data.")
    parser.add_argument("--heart_rate", type=int, default=None, help="Heart rate.")
    parser.add_argument("--respiratory_rate", type=int, default=None, help="Respiratory rate.")
    parser.add_argument("--scr_number", type=int, default=None, help="SCR Number for EDA.")
    parser.add_argument("--burst_number", type=int, default=None, help="Burst number for EMG.")
    # parser.add_argument("--socket_url", type=str, default="wss://sensocto.fly.dev/socket/websocket", help="Burst number for EMG.")
    # parser.add_argument("--socket_url", type=str, default="ws://192.168.1.64:4000/socket/websocket", help="Socket target")
    parser.add_argument("--socket_url", type=str, default="ws://localhost:4000/socket/websocket",
                        help="Socket target")

    args = parser.parse_args()

    socket_url = args.socket_url
    sensor_id = args.sensor_id
    sensor_type = args.sensor_type
    duration = args.duration
    sampling_rate = 5# args.sampling_rate
    heart_rate = args.heart_rate
    respiratory_rate = args.respiratory_rate
    scr_number = args.scr_number
    burst_number = args.burst_number

    connector_id = str(uuid.UUID(int=uuid.getnode()))
    connector_name = sensor_id
    sensor_id_string = f"{sensor_id}:{sensor_type}"

    join_params = {
        "connector_id": connector_id,
        "connector_name": connector_name,
        "sensor_name": sensor_id,
        "sensor_id": sensor_id_string,
        "sensor_type": sensor_type,
        "sampling_rate": sampling_rate,
        "batch_size": 1,
        "bearer_token": "fake"
    }

    client = PhoenixChannelClient(socket_url, handle_message)
    logging.info(f"Connecting to: {socket_url}")

    await client.subscribe(f"sensor_data:{sensor_id_string}", join_params)
    await client.connect()

    while True:  # Loop indefinitely
        await send_sensor_data(client, sensor_id_string, sensor_type, duration, sampling_rate, heart_rate,
                               respiratory_rate, scr_number,
                               burst_number)
    # await asyncio.sleep(random.randint(5, 10))  # Pause before the next run, with random pause


if __name__ == "__main__":
    asyncio.run(main())
