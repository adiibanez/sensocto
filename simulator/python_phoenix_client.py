import asyncio
import json
import time
import logging
import random
import websockets  # Correct library name

logging.basicConfig(level=logging.INFO)

class PhoenixChannelClient:
    def __init__(self, socket_url, on_message_callback, on_connect_callback=None, on_disconnect_callback=None):
        self.socket_url = socket_url
        self.on_message_callback = on_message_callback
        self.on_connect_callback = on_connect_callback
        self.on_disconnect_callback = on_disconnect_callback
        self.channels = {}
        self.ws = None
        self.lock = asyncio.Lock()
        self.connected = False
        self.receiving_task = None  # Task for receiving messages
        self.reconnect_delay = 2 # Default reconnect delay

    async def connect(self):
        while True:
            try:
                self.ws = await websockets.connect(self.socket_url)
                logging.info("WebSocket connection opened")
                self.connected = True
                if self.on_connect_callback:
                    await self.on_connect_callback()

                await self._join_all_channels()
                self.receiving_task = asyncio.create_task(self._receive_messages())
                break  # Connection successful, exit loop
            except websockets.ConnectionClosed as e:
                logging.info(f"WebSocket connection closed: {e}")
                self.connected = False
                if self.on_disconnect_callback:
                    await self.on_disconnect_callback()
                await asyncio.sleep(self.reconnect_delay)  # Wait before retrying
                logging.info(f"Attempting to reconnect in {self.reconnect_delay} seconds...")


            except Exception as e:
                #logging.error(f"An error occurred: {e}")
                logging.error(e, exc_info=True)
                self.connected = False
                if self.on_disconnect_callback:
                    await self.on_disconnect_callback()
                await asyncio.sleep(self.reconnect_delay)  # Wait before retrying
                logging.info(f"Attempting to reconnect in {self.reconnect_delay} seconds...")

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
            if self.on_disconnect_callback:
                await self.on_disconnect_callback()
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

async def on_connect():
    logging.info("Client connected to websocket.")


async def on_disconnect():
    logging.info("Client disconnected from websocket.")


async def main():
    socket_url = "ws://localhost:4000/socket/websocket"
    client = PhoenixChannelClient(socket_url, handle_message, on_connect, on_disconnect)

    logging.info(f"Before client init")
   # Subscribe to some channels, this will ensure that the channels exist before the client connects.
    await client.subscribe("sensor_data:sensor_1", {"device_name": "sensor_1"})
    #await client.subscribe("sensor_data:sensor_2", {"device_name": "sensor_2"})
    #await client.subscribe("sensor_data:sensor_3", {"device_name": "sensor_3"})

    await client.connect()
    logging.info(f"After client init")

    await client.close()


if __name__ == "__main__":
    asyncio.run(main())