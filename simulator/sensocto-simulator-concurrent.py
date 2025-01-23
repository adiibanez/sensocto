# concurrent_runner.py
import asyncio
import logging
import subprocess
import shlex
import argparse
import re

logging.basicConfig(level=logging.INFO)


async def run_command(command):
    """Runs a shell command asynchronously."""
    logging.info(f"Running command: {command}")
    process = await asyncio.create_subprocess_shell(
        command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    if stdout:
        logging.info(f"Command output:\n{stdout.decode()}")
    if stderr:
        logging.error(f"Command error output:\n{stderr.decode()}")
    if process.returncode != 0:
        logging.error(f"Command failed with exit code: {process.returncode}")
    else:
        logging.info(f"Command completed successfully: {command}")


async def main():
    parser = argparse.ArgumentParser(
        description="Run multiple Python scripts concurrently based on a configuration file.")
    parser.add_argument("--config_file", type=str, default="sensocto-simulator.txt", help="Path to the configuration file.")
    parser.add_argument("--mode", type=str, default="phoenix",
                        help="Simulator mode")
    args = parser.parse_args()
    config_file = args.config_file

    commands = []
    socket_url = None

    try:
        with open(config_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue  # Skip empty lines and comments

                if line.startswith("--socket_url"):
                    parts = line.split(" ", 1)
                    if len(parts) == 2:
                        socket_url = parts[1].strip()
                        logging.info(f"Setting socket url to {socket_url}")
                    continue  # skip this line

                commands.append(line)
    except FileNotFoundError:
        logging.error(f"Error: Configuration file not found at {config_file}")
        return

    tasks = []

    for command in commands:
        if socket_url:
            if "--socket_url" not in command:  # dont append if there is already a socket url
                command += f' --socket_url {socket_url}'  # add it if it's missing

        tasks.append(run_command(command))

    await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())