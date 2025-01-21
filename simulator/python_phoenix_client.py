import asyncio
import json
import time
import logging
import random
import websockets  # Correct library name

logging.basicConfig(level=logging.INFO)

class PhoenixChannelClient:
    def __init__(self, socket_url, on_message_callback):
        self.socket_url = socket_url
        self.on_message_callback = on_message_callback
        self.channels = {}
        self.ws = None
        self.lock = asyncio.Lock()
        self.connected = False
        self.receiving_task = None  # Task for receiving messages

    async def connect(self):
        try:
            self.ws = await websockets.connect(self.socket_url)
            logging.info("WebSocket connection opened")
            self.connected = True
             # Now the channels are already in self.channels
            await self._join_all_channels()
            self.receiving_task = asyncio.create_task(self._receive_messages())

        except websockets.ConnectionClosed as e:
            logging.info(f"WebSocket connection closed: {e}")
            self.connected = False
        except Exception as e:
            logging.error(f"An error occurred: {e}")
            self.connected = False

    async def _join_all_channels(self):
        for topic, params in list(self.channels.items()):
             await self._join_channel(topic, params)

    async def _receive_messages(self):
        try:
            async for message in self.ws:
                try:
                    data = json.loads(message)
                    topic = data.get("topic")
                    event = data.get("event")
                    payload = data.get("payload")
                    if topic and event:
                        self.on_message_callback(topic, event, payload)
                except json.JSONDecodeError as e:
                    logging.error(f"Error decoding JSON: {message}, {e}")
        except Exception as e:
            logging.error(f"Error receiving messages, closing connection: {e}")
            self.connected = False
            await self.close()

    async def _join_channel(self, topic, params):
        try:
            async with self.lock:
                logging.info(f"Joining channel: {topic}")
                payload = {"topic": topic, "event": "phx_join", "payload": params, "ref": str(time.time())}
                await self.ws.send(json.dumps(payload))
        except Exception as e:
            logging.error(f"Error joining channel {topic}: {e}")

    async def subscribe(self, topic, params):
        async with self.lock:
             if topic not in self.channels:
                self.channels[topic] = params


    async def unsubscribe(self, topic):
        async with self.lock:
            if topic in self.channels:
                logging.info(f"Unsubscribing from channel: {topic}")
                del self.channels[topic]
                payload = {"topic": topic, "event": "phx_leave", "payload": {}, "ref": str(time.time())}
                if self.connected:
                  await self.ws.send(json.dumps(payload))


    async def push(self, topic, event, payload):
         async with self.lock:
            #if self.ws and self.connected and self.ws.open:
            if self.ws and self.connected and not self.ws.closed:
                try:
                   logging.info(f"Pushing event: {event} on topic: {topic}, with payload: {payload}")
                   push_payload = {"topic": topic, "event": event, "payload": payload, "ref": str(time.time())}
                   await self.ws.send(json.dumps(push_payload))
                except Exception as e:
                    logging.error(f"Error pushing message {event} on {topic}: {e}")
                    self.connected = False

    async def close(self):
         if self.ws:
           await self.ws.close()
           self.connected = False
           if self.receiving_task:
                self.receiving_task.cancel()


def handle_message(topic, event, payload):
    logging.info(f"Received message on topic: {topic}, event: {event}, payload: {payload}")


async def main():
    socket_url = "ws://localhost:4000/socket/websocket"
    client = PhoenixChannelClient(socket_url, handle_message)

    logging.info(f"Before client init")
   # Subscribe to some channels, this will ensure that the channels exist before the client connects.
    await client.subscribe("sensor_data:sensor_1", {"device_name": "sensor_1"})
    #await client.subscribe("sensor_data:sensor_2", {"device_name": "sensor_2"})
    #await client.subscribe("sensor_data:sensor_3", {"device_name": "sensor_3"})

    await client.connect()
    logging.info(f"After client init")

    '''
    time.sleep(1)  # simulate long running application
    await client.push("sensor_data:sensor_1", "measurement", {"value": 123})
    await client.push("sensor_data:sensor_2", "measurement", {"value": 321})
    await client.push("sensor_data:sensor_3", "measurement", {"value": 456})
    time.sleep(1)  # simulate long running application
    await client.unsubscribe("sensor_data:sensor_2")
    time.sleep(1)  # simulate long running application

    for i in range(100):
      await client.push("sensor_data:sensor_1", "measurement", {"value": random.randint(1, 100)})
      await asyncio.sleep(random.randint(1, 2)/100)
      await client.push("sensor_data:sensor_2", "measurement", {"value": random.randint(1, 100)})
      await asyncio.sleep(random.randint(1, 2)/100)
      await client.push("sensor_data:sensor_3", "measurement", {"value": random.randint(1, 100)})
      await asyncio.sleep(random.randint(1, 2)/100)

    # client.subscribe("sensor_data:sensor_4", {"device_name": "sensor_4"})
    time.sleep(1)  # simulate long running application
    await client.push("sensor_data:sensor_4", "measurement", {"value": 987})
    time.sleep(1)
    '''
    await client.close()


if __name__ == "__main__":
    asyncio.run(main())