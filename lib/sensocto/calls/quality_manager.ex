defmodule Sensocto.Calls.QualityManager do
  @moduledoc """
  Manages adaptive video quality based on participant count,
  network conditions, system load, and attention-based tiers.

  ## Participant-Count Quality Profiles:
  - :high   - 720p @ 30fps, 2.5 Mbps (1-2 participants)
  - :medium - 480p @ 24fps, 1.0 Mbps (3-4 participants)
  - :low    - 360p @ 20fps, 500 Kbps (5-9 participants)
  - :minimal - 240p @ 15fps, 250 Kbps (10-20 participants)

  ## Attention-Based Quality Tiers (for massive scale):
  - :active  - Full video 720p@30fps (~2.5 Mbps) - Currently speaking/presenting
  - :recent  - Reduced video 480p@15fps (~500 Kbps) - Spoke in last 30s
  - :viewer  - Snapshot mode 1-3fps JPEG (~50-100 Kbps) - Watching, not active
  - :idle    - Static avatar + presence (~0) - Tab hidden, AFK

  This enables 100+ participants per room with ~8x bandwidth reduction:
  - Traditional: 20 participants x 2.5 Mbps = 50 Mbps
  - Adaptive (1 speaker, 5 recent, 14 viewers): 2.5 + 2.5 + 1.4 = ~6.4 Mbps
  """

  @type quality :: :high | :medium | :low | :minimal
  @type network_quality :: :excellent | :good | :fair | :poor
  @type attention_tier :: :active | :recent | :viewer | :idle
  @type attention_level :: :high | :medium | :low
  @type media_mode :: :video | :snapshot | :static

  # Participant-count based quality profiles (legacy/fallback)
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

  # Attention-based tier profiles for adaptive quality
  @tier_profiles %{
    active: %{
      mode: :video,
      max_bitrate: 2_500_000,
      max_framerate: 30,
      width: 1280,
      height: 720,
      description: "Active Speaker (720p @ 30fps)",
      priority: 1
    },
    recent: %{
      mode: :video,
      max_bitrate: 500_000,
      max_framerate: 15,
      width: 640,
      height: 480,
      description: "Recently Active (480p @ 15fps)",
      priority: 2
    },
    viewer: %{
      mode: :snapshot,
      interval_ms: 1000,
      width: 320,
      height: 240,
      jpeg_quality: 70,
      description: "Viewer (Snapshot @ 1fps)",
      priority: 3
    },
    idle: %{
      mode: :static,
      show_avatar: true,
      description: "Idle (Static Avatar)",
      priority: 4
    }
  }

  @audio_profile %{
    max_bitrate: 64_000,
    sample_rate: 48_000,
    channels: 1
  }

  # Attention-Based Tier API

  @doc """
  Calculates the appropriate quality tier for a participant.
  """
  @spec calculate_tier(attention_level(), boolean(), boolean()) :: attention_tier()
  def calculate_tier(attention_level, is_speaking, recently_spoke) do
    cond do
      attention_level == :low -> :idle
      is_speaking -> :active
      recently_spoke -> :recent
      true -> :viewer
    end
  end

  @doc """
  Returns the tier profile for a given attention tier.
  """
  @spec get_tier_profile(attention_tier()) :: map()
  def get_tier_profile(tier) when tier in [:active, :recent, :viewer, :idle] do
    Map.get(@tier_profiles, tier)
  end

  @doc """
  Returns video constraints for a given attention tier.
  """
  @spec get_tier_video_constraints(attention_tier()) :: map()
  def get_tier_video_constraints(tier) do
    profile = get_tier_profile(tier)

    case profile.mode do
      :video ->
        %{
          width: %{ideal: profile.width, max: profile.width},
          height: %{ideal: profile.height, max: profile.height},
          frameRate: %{ideal: profile.max_framerate, max: profile.max_framerate}
        }

      :snapshot ->
        %{
          width: %{ideal: profile.width, max: profile.width},
          height: %{ideal: profile.height, max: profile.height},
          frameRate: %{ideal: 1, max: 5}
        }

      :static ->
        %{}
    end
  end

  @doc """
  Returns encoding parameters for a given attention tier.
  """
  @spec get_tier_encoding_parameters(attention_tier()) :: map()
  def get_tier_encoding_parameters(tier) do
    profile = get_tier_profile(tier)

    case profile.mode do
      :video ->
        %{
          maxBitrate: profile.max_bitrate,
          maxFramerate: profile.max_framerate,
          scaleResolutionDownBy: tier_scale_factor(tier)
        }

      _ ->
        %{maxBitrate: 0, maxFramerate: 0, scaleResolutionDownBy: 1.0}
    end
  end

  @doc """
  Returns the media mode for a tier.
  """
  @spec get_tier_mode(attention_tier()) :: media_mode()
  def get_tier_mode(tier), do: get_tier_profile(tier).mode

  @doc """
  Returns the snapshot interval in milliseconds for snapshot-mode tiers.
  """
  @spec get_snapshot_interval(attention_tier()) :: non_neg_integer() | nil
  def get_snapshot_interval(tier) do
    profile = get_tier_profile(tier)
    if profile.mode == :snapshot, do: Map.get(profile, :interval_ms, 1000), else: nil
  end

  @doc """
  Returns all tier profiles.
  """
  @spec all_tier_profiles() :: map()
  def all_tier_profiles, do: @tier_profiles

  @doc """
  Returns the tier description for UI display.
  """
  @spec tier_description(attention_tier()) :: String.t()
  def tier_description(tier), do: get_tier_profile(tier).description

  @doc """
  Calculates estimated bandwidth usage for a given tier distribution.
  """
  @spec estimate_bandwidth(map()) :: non_neg_integer()
  def estimate_bandwidth(tier_counts) do
    Enum.reduce(tier_counts, 0, fn {tier, count}, acc ->
      profile = get_tier_profile(tier)

      tier_bw =
        case profile.mode do
          :video -> profile.max_bitrate
          :snapshot -> 50_000
          :static -> 0
        end

      acc + tier_bw * count
    end)
  end

  @doc """
  Downgrades a tier by one level.
  """
  @spec downgrade_tier(attention_tier()) :: attention_tier()
  def downgrade_tier(:active), do: :recent
  def downgrade_tier(:recent), do: :viewer
  def downgrade_tier(:viewer), do: :idle
  def downgrade_tier(:idle), do: :idle

  @doc """
  Upgrades a tier by one level.
  """
  @spec upgrade_tier(attention_tier()) :: attention_tier()
  def upgrade_tier(:idle), do: :viewer
  def upgrade_tier(:viewer), do: :recent
  def upgrade_tier(:recent), do: :active
  def upgrade_tier(:active), do: :active

  # Participant-Count Quality API (Legacy/Fallback)

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
  Returns the audio profile.
  """
  @spec get_audio_profile() :: map()
  def get_audio_profile, do: @audio_profile

  @doc """
  Returns the suggested quality level for a given participant count.
  """
  @spec suggest_quality_for_participant_count(non_neg_integer()) :: quality()
  def suggest_quality_for_participant_count(count), do: quality_for_participant_count(count)

  @doc """
  Returns all available quality profiles.
  """
  @spec all_profiles() :: map()
  def all_profiles, do: @quality_profiles

  @doc """
  Returns the quality profile description for UI display.
  """
  @spec quality_description(quality()) :: String.t()
  def quality_description(quality), do: get_profile(quality).description

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

  defp tier_scale_factor(:active), do: 1.0
  defp tier_scale_factor(:recent), do: 2.0
  defp tier_scale_factor(:viewer), do: 4.0
  defp tier_scale_factor(:idle), do: 1.0
end
