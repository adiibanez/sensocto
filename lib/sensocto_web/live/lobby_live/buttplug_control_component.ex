defmodule SensoctoWeb.LobbyLive.ButtplugControlComponent do
  @moduledoc """
  Control panel for buttplug.io devices connected via Intiface Central.

  Provides connection management, device discovery, and actuator controls
  (vibrate/rotate/linear sliders). Communicates with the ButtplugBridge JS hook.
  """
  use Phoenix.Component

  attr :buttplug_status, :string, required: true
  attr :buttplug_devices, :list, required: true
  attr :buttplug_error, :string, default: nil
  attr :bearer_token, :string, default: "missing"

  def buttplug_panel(assigns) do
    ~H"""
    <div
      id="buttplug-bridge"
      phx-hook="ButtplugBridge"
      data-bearer-token={@bearer_token}
      class="p-3 mb-3 bg-gray-800/50 rounded-lg border border-gray-700"
    >
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium text-gray-300">Intiface Devices</span>
          <.status_badge status={@buttplug_status} />
        </div>
        <.connection_controls status={@buttplug_status} />
      </div>

      <.error_banner :if={@buttplug_error} error={@buttplug_error} />

      <.device_list :if={@buttplug_status in ["connected", "scanning"]} devices={@buttplug_devices} />

      <.connect_prompt :if={@buttplug_status == "disconnected"} />
    </div>
    """
  end

  defp status_badge(assigns) do
    {color, label} =
      case assigns.status do
        "connected" -> {"bg-green-500", "Connected"}
        "scanning" -> {"bg-blue-500 animate-pulse", "Scanning"}
        "connecting" -> {"bg-yellow-500 animate-pulse", "Connecting"}
        "error" -> {"bg-red-500", "Error"}
        _ -> {"bg-gray-500", "Disconnected"}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span class="flex items-center gap-1.5">
      <span class={"w-2 h-2 rounded-full #{@color}"}></span>
      <span class="text-xs text-gray-400">{@label}</span>
    </span>
    """
  end

  defp connection_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= if @status in ["connected", "scanning"] do %>
        <button
          :if={@status == "connected"}
          phx-click="buttplug_start_scan"
          class="px-2 py-1 text-xs bg-blue-600 hover:bg-blue-500 text-white rounded transition-colors"
        >
          Scan
        </button>
        <button
          :if={@status == "scanning"}
          phx-click="buttplug_stop_scan"
          class="px-2 py-1 text-xs bg-yellow-600 hover:bg-yellow-500 text-white rounded transition-colors"
        >
          Stop Scan
        </button>
        <button
          phx-click="buttplug_disconnect"
          class="px-2 py-1 text-xs bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
        >
          Disconnect
        </button>
      <% else %>
        <button
          :if={@status not in ["connecting"]}
          phx-click="buttplug_connect"
          class="px-2 py-1 text-xs bg-purple-600 hover:bg-purple-500 text-white rounded transition-colors"
        >
          Connect
        </button>
      <% end %>
    </div>
    """
  end

  defp error_banner(assigns) do
    ~H"""
    <div class="mb-2 p-2 bg-red-900/30 border border-red-700/50 rounded text-xs text-red-300">
      {@error}
      <span :if={String.contains?(@error || "", "WebSocket")} class="block mt-1 text-red-400">
        Make sure
        <a
          href="https://intiface.com/central/"
          target="_blank"
          class="underline hover:text-red-200"
        >
          Intiface Central
        </a>
        is running on your machine.
      </span>
    </div>
    """
  end

  defp connect_prompt(assigns) do
    ~H"""
    <div class="text-center py-4 text-xs text-gray-500">
      <p>Connect to Intiface Central to discover devices.</p>
      <p class="mt-1">
        <a
          href="https://intiface.com/central/"
          target="_blank"
          class="text-purple-400 hover:text-purple-300 underline"
        >
          Download Intiface Central
        </a>
      </p>
    </div>
    """
  end

  defp device_list(assigns) do
    ~H"""
    <div class="space-y-2">
      <div :if={@devices == []} class="text-center py-3 text-xs text-gray-500">
        No devices found. Start scanning to discover nearby devices.
      </div>
      <.device_card :for={device <- @devices} device={device} />
    </div>
    """
  end

  defp device_card(assigns) do
    ~H"""
    <div class="p-2 bg-gray-700/50 rounded border border-gray-600/50">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm text-gray-200">{@device.name}</span>
        <button
          phx-click="buttplug_stop_device"
          phx-value-sensor-id={@device.sensor_id}
          class="px-1.5 py-0.5 text-[10px] bg-red-700 hover:bg-red-600 text-white rounded transition-colors"
          title="Stop all motors"
        >
          Stop
        </button>
      </div>

      <.vibrate_control
        :if={@device.capabilities.vibrate > 0}
        sensor_id={@device.sensor_id}
        motor_count={@device.capabilities.vibrate}
      />
      <.rotate_control
        :if={@device.capabilities.rotate > 0}
        sensor_id={@device.sensor_id}
      />
      <.linear_control
        :if={@device.capabilities.linear > 0}
        sensor_id={@device.sensor_id}
      />
    </div>
    """
  end

  defp vibrate_control(assigns) do
    ~H"""
    <div class="mt-1">
      <label class="text-[10px] text-gray-400 uppercase tracking-wide">Vibrate</label>
      <div class="flex items-center gap-2 mt-0.5">
        <span class="text-[10px] text-gray-500 w-4">0</span>
        <input
          type="range"
          min="0"
          max="100"
          value="0"
          phx-change="buttplug_vibrate"
          phx-value-sensor-id={@sensor_id}
          name="speed"
          class="flex-1 h-1.5 rounded-full appearance-none cursor-pointer"
          style="accent-color: #a855f7; background: #2d2845;"
        />
        <span class="text-[10px] text-gray-500 w-6">100</span>
      </div>
    </div>
    """
  end

  defp rotate_control(assigns) do
    ~H"""
    <div class="mt-1">
      <label class="text-[10px] text-gray-400 uppercase tracking-wide">Rotate</label>
      <div class="flex items-center gap-2 mt-0.5">
        <span class="text-[10px] text-gray-500 w-4">0</span>
        <input
          type="range"
          min="0"
          max="100"
          value="0"
          phx-change="buttplug_rotate"
          phx-value-sensor-id={@sensor_id}
          name="speed"
          class="flex-1 h-1.5 rounded-full appearance-none cursor-pointer"
          style="accent-color: #ec4899; background: #2d2845;"
        />
        <span class="text-[10px] text-gray-500 w-6">100</span>
      </div>
    </div>
    """
  end

  defp linear_control(assigns) do
    ~H"""
    <div class="mt-1">
      <label class="text-[10px] text-gray-400 uppercase tracking-wide">Linear</label>
      <div class="flex items-center gap-2 mt-0.5">
        <span class="text-[10px] text-gray-500 w-4">0</span>
        <input
          type="range"
          min="0"
          max="100"
          value="0"
          phx-change="buttplug_linear"
          phx-value-sensor-id={@sensor_id}
          name="position"
          class="flex-1 h-1.5 rounded-full appearance-none cursor-pointer"
          style="accent-color: #3b82f6; background: #2d2845;"
        />
        <span class="text-[10px] text-gray-500 w-6">100</span>
      </div>
    </div>
    """
  end
end
