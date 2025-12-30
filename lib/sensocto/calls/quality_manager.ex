defmodule Sensocto.Calls.QualityManager do
  @moduledoc """
  Manages adaptive video quality based on participant count,
  network conditions, and system load.

  Quality Profiles:
  - :high   - 720p @ 30fps, 2.5 Mbps (1-2 participants)
  - :medium - 480p @ 24fps, 1.0 Mbps (3-4 participants)
  - :low    - 360p @ 20fps, 500 Kbps (5-9 participants)
  - :minimal - 240p @ 15fps, 250 Kbps (10-20 participants)
  """

  @type quality :: :high | :medium | :low | :minimal
  @type network_quality :: :excellent | :good | :fair | :poor

  @quality_profiles %{
    high: %{
      max_bitrate: 2_500_000,
      max_framerate: 30,
      width: 1280,
      height: 720,
      description: "HD (720p @ 30fps)"
    },
    medium: %{
      max_bitrate: 1_000_000,
      max_framerate: 24,
      width: 640,
      height: 480,
      description: "SD (480p @ 24fps)"
    },
    low: %{
      max_bitrate: 500_000,
      max_framerate: 20,
      width: 640,
      height: 360,
      description: "Low (360p @ 20fps)"
    },
    minimal: %{
      max_bitrate: 250_000,
      max_framerate: 15,
      width: 320,
      height: 240,
      description: "Minimal (240p @ 15fps)"
    }
  }

  @audio_profile %{
    max_bitrate: 64_000,
    sample_rate: 48_000,
    channels: 1
  }

  @doc """
  Calculates the optimal quality level based on participant count and network quality.
  """
  @spec calculate_quality(non_neg_integer(), network_quality()) :: quality()
  def calculate_quality(participant_count, network_quality \\ :good) do
    base_quality = quality_for_participant_count(participant_count)
    adjust_for_network(base_quality, network_quality)
  end

  @doc """
  Returns the quality profile for a given quality level.
  """
  @spec get_profile(quality()) :: map()
  def get_profile(quality) when is_atom(quality) do
    Map.get(@quality_profiles, quality, @quality_profiles.medium)
  end

  @doc """
  Returns video constraints for a given quality level.
  Used for MediaStream.getUserMedia constraints.
  """
  @spec get_video_constraints(quality()) :: map()
  def get_video_constraints(quality) do
    profile = get_profile(quality)

    %{
      width: %{ideal: profile.width, max: profile.width},
      height: %{ideal: profile.height, max: profile.height},
      frameRate: %{ideal: profile.max_framerate, max: profile.max_framerate}
    }
  end

  @doc """
  Returns encoding parameters for WebRTC SDP.
  """
  @spec get_encoding_parameters(quality()) :: map()
  def get_encoding_parameters(quality) do
    profile = get_profile(quality)

    %{
      maxBitrate: profile.max_bitrate,
      maxFramerate: profile.max_framerate,
      scaleResolutionDownBy: scale_factor(quality)
    }
  end

  @doc """
  Returns the audio profile (constant for all quality levels).
  """
  @spec get_audio_profile() :: map()
  def get_audio_profile do
    @audio_profile
  end

  @doc """
  Returns the suggested quality level for a given participant count.
  """
  @spec suggest_quality_for_participant_count(non_neg_integer()) :: quality()
  def suggest_quality_for_participant_count(count) do
    quality_for_participant_count(count)
  end

  @doc """
  Returns all available quality profiles.
  """
  @spec all_profiles() :: map()
  def all_profiles do
    @quality_profiles
  end

  @doc """
  Returns the quality profile description for UI display.
  """
  @spec quality_description(quality()) :: String.t()
  def quality_description(quality) do
    get_profile(quality).description
  end

  @doc """
  Downgrades quality by one level.
  """
  @spec downgrade_quality(quality()) :: quality()
  def downgrade_quality(:high), do: :medium
  def downgrade_quality(:medium), do: :low
  def downgrade_quality(:low), do: :minimal
  def downgrade_quality(:minimal), do: :minimal

  @doc """
  Upgrades quality by one level.
  """
  @spec upgrade_quality(quality()) :: quality()
  def upgrade_quality(:minimal), do: :low
  def upgrade_quality(:low), do: :medium
  def upgrade_quality(:medium), do: :high
  def upgrade_quality(:high), do: :high

  # Private functions

  defp quality_for_participant_count(count) when count <= 2, do: :high
  defp quality_for_participant_count(count) when count <= 4, do: :medium
  defp quality_for_participant_count(count) when count <= 9, do: :low
  defp quality_for_participant_count(_count), do: :minimal

  defp adjust_for_network(quality, :excellent), do: quality
  defp adjust_for_network(quality, :good), do: quality
  defp adjust_for_network(quality, :fair), do: downgrade_quality(quality)
  defp adjust_for_network(quality, :poor), do: downgrade_quality(downgrade_quality(quality))

  defp scale_factor(:high), do: 1.0
  defp scale_factor(:medium), do: 1.5
  defp scale_factor(:low), do: 2.0
  defp scale_factor(:minimal), do: 3.0
end
