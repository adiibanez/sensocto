defmodule SensoctoWeb.LobbyLive.LensComponents do
  @moduledoc """
  Function components for lobby lens views.
  Extracted from lobby_live.html.heex for diff isolation:
  LiveView skips diffing subtrees whose assigns haven't changed.
  """
  use Phoenix.Component
  use SensoctoWeb, :verified_routes
  import LiveSvelte

  # ---------------------------------------------------------------------------
  # composite_lens/1 — generic wrapper for all single-Svelte composite views
  # (heartrate, imu, location, ecg, battery, skeleton, respiration, hrv, gaze)
  # ---------------------------------------------------------------------------

  attr :svelte_name, :string, required: true
  attr :container_id, :string, required: true
  # sensors list used only for the empty-state guard
  attr :sensors, :list, required: true
  attr :props, :map, required: true
  attr :socket, :any, required: true
  attr :container_class, :string, default: ""
  attr :svelte_class, :string, default: "w-full"
  attr :empty_icon, :string, required: true
  attr :empty_message, :string, required: true
  attr :empty_hint, :string, required: true

  def composite_lens(assigns) do
    ~H"""
    <div id={@container_id} phx-hook="CompositeMeasurementHandler" class={@container_class}>
      <.svelte name={@svelte_name} props={@props} socket={@socket} class={@svelte_class} />
      <div :if={@sensors == []} class="text-center py-12 text-gray-300">
        <Heroicons.icon name={@empty_icon} type="outline" class="h-12 w-12 mx-auto mb-4" />
        <p class="text-lg">{@empty_message}</p>
        <p class="text-sm mt-2">{@empty_hint}</p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # midi_panel/1 — MIDI / GrooveEngine panel shown on graph and graph3d views.
  # All content is phx-update="ignore" (managed entirely by MidiOutputHook JS).
  # No assigns required — purely static HTML.
  # ---------------------------------------------------------------------------

  def midi_panel(assigns) do
    ~H"""
    <div id="midi-output-wrapper" class="px-4">
      <div
        id="midi-output-panel"
        phx-hook="MidiOutputHook"
        phx-update="ignore"
        class="mt-3 px-3 py-2 bg-gray-800/40 rounded-lg border border-gray-700/50 flex items-center justify-center gap-3 flex-wrap text-xs"
      >
        <span id="midi-status-dot" class="w-2 h-2 rounded-full bg-gray-500 flex-shrink-0"></span>
        <button
          id="midi-toggle-btn"
          class="px-2 py-1 rounded text-xs font-medium bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
        >
          Audio Off
        </button>
        <select
          id="midi-backend-select"
          class="rounded px-2 py-1 text-xs focus:outline-none"
          style="background: #374151; border: 1px solid #4b5563; color: #d1d5db;"
        >
          <option value="midi">MIDI</option>
          <option value="tone">Synth</option>
          <option value="both">Both</option>
        </select>
        <select
          id="midi-device-select"
          class="bg-gray-700 border border-gray-600 rounded px-2 py-1 text-xs text-gray-300 focus:outline-none focus:border-purple-500 min-w-[140px]"
        >
          <option value="">-- Select MIDI output --</option>
        </select>
        <span style="position:relative;display:inline-block;" id="midi-mode-wrap">
          <button
            id="midi-mode-btn"
            class="px-2 py-1 rounded text-xs font-medium bg-gray-600 text-gray-400 hover:bg-gray-500 transition-colors"
          >
            🌊 Abstract
          </button>
          <span
            id="midi-mode-tooltip"
            style="display:none;position:absolute;bottom:calc(100% + 8px);left:50%;transform:translateX(-50%);width:280px;padding:10px 12px;background:rgba(17,12,34,0.96);border:1px solid rgba(139,92,246,0.35);border-radius:8px;color:#d1d5db;font-size:11px;line-height:1.5;text-align:left;white-space:normal;z-index:50;pointer-events:none;box-shadow:0 4px 20px rgba(0,0,0,0.5);"
          >
            <span id="midi-mode-tooltip-content">
              Click to cycle modes: Abstract → Groovy genres → Local AI.<br />
              <b style="color:#c4b5fd;">Abstract</b>
              — raw sensor data as MIDI CCs &amp; note triggers.<br />
              <b style="color:#c4b5fd;">Groovy</b>
              — musical engine with chords, bass, drums &amp; arps driven by biometrics. 4 genre styles.<br />
              <b style="color:#c4b5fd;">Local AI</b>
              — on-device neural net (Magenta) generates melodies from sensor input. Use ⚙ to set key, chords &amp; creativity.
            </span>
          </span>
          <style>
            #midi-mode-wrap:hover #midi-mode-tooltip { display: block !important; }
          </style>
        </span>
        <button
          id="midi-ai-settings-btn"
          class="hidden px-2.5 py-1.5 rounded text-base hover:bg-gray-600 transition-colors"
          style="color: #c4b5fd;"
          title="AI Settings"
        >
          ⚙
        </button>
        <span
          id="midi-chord-display"
          class="text-pink-400 font-mono text-[10px]"
          style="display:none"
        >
        </span>

        <div
          id="tone-instruments"
          class="hidden w-full flex items-center gap-2 flex-wrap text-[10px]"
        >
          <span style="color: #9ca3af;">Voices:</span>
          <label class="flex items-center gap-1 cursor-pointer" style="color: #d1d5db;">
            <input
              type="checkbox"
              id="tone-mute-bass"
              checked
              class="w-3 h-3 accent-red-400 cursor-pointer"
            />
            <span style="color: #f87171;">Bass</span>
            <select
              id="tone-inst-bass"
              class="rounded px-1 py-0.5 text-[10px]"
              style="background: #1f2937; border: 1px solid #4b5563; color: #d1d5db;"
            >
              <option value="default">Genre</option>
            </select>
          </label>
          <label class="flex items-center gap-1 cursor-pointer" style="color: #d1d5db;">
            <input
              type="checkbox"
              id="tone-mute-pad"
              checked
              class="w-3 h-3 accent-violet-400 cursor-pointer"
            />
            <span style="color: #a78bfa;">Pad</span>
            <select
              id="tone-inst-pad"
              class="rounded px-1 py-0.5 text-[10px]"
              style="background: #1f2937; border: 1px solid #4b5563; color: #d1d5db;"
            >
              <option value="default">Genre</option>
            </select>
          </label>
          <label class="flex items-center gap-1 cursor-pointer" style="color: #d1d5db;">
            <input
              type="checkbox"
              id="tone-mute-lead"
              checked
              class="w-3 h-3 accent-emerald-400 cursor-pointer"
            />
            <span style="color: #34d399;">Lead</span>
            <select
              id="tone-inst-lead"
              class="rounded px-1 py-0.5 text-[10px]"
              style="background: #1f2937; border: 1px solid #4b5563; color: #d1d5db;"
            >
              <option value="default">Genre</option>
            </select>
          </label>
          <label class="flex items-center gap-1 cursor-pointer" style="color: #d1d5db;">
            <input
              type="checkbox"
              id="tone-mute-arp"
              checked
              class="w-3 h-3 accent-sky-400 cursor-pointer"
            />
            <span style="color: #38bdf8;">Arp</span>
            <select
              id="tone-inst-arp"
              class="rounded px-1 py-0.5 text-[10px]"
              style="background: #1f2937; border: 1px solid #4b5563; color: #d1d5db;"
            >
              <option value="default">Genre</option>
            </select>
          </label>
        </div>
        <div id="midi-meters" class="hidden ml-auto flex items-center gap-2.5 flex-wrap">
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="tempo"
            title="Click to toggle — MIDI Clock / Group mean heart rate"
          >
            <span class="text-[10px]" style="color: #f87171;">BPM</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-tempo"
                class="h-full rounded-full transition-all duration-150"
                style="width: 0%; background: #ef4444;"
              >
              </div>
            </div>
            <span id="midi-val-tempo" class="w-6 tabular-nums" style="color: #d1d5db;">-</span>
          </div>
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="arousal"
            title="Click to toggle — CC7 Volume / Collective arousal"
          >
            <span class="text-[10px]" style="color: #fbbf24;">ARO</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-arousal"
                class="h-full rounded-full transition-all duration-150"
                style="width: 0%; background: #f59e0b;"
              >
              </div>
            </div>
            <span id="midi-val-arousal" class="w-6 tabular-nums" style="color: #d1d5db;">
              0
            </span>
          </div>
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="hrv"
            title="Click to toggle — CC1 Mod Wheel / Group HRV RMSSD"
          >
            <span class="text-[10px]" style="color: #c084fc;">HRV</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-hrv"
                class="h-full rounded-full transition-all duration-75"
                style="width: 0%; background: #a855f7;"
              >
              </div>
            </div>
            <span id="midi-val-hrv" class="w-6 tabular-nums" style="color: #d1d5db;">0</span>
          </div>
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="breath"
            title="Click to toggle — CC2 Breath / Group breath phase LFO"
          >
            <span class="text-[10px]" style="color: #22d3ee;">BRE</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-breath"
                class="h-full rounded-full transition-all duration-75"
                style="width: 0%; background: #06b6d4;"
              >
              </div>
            </div>
            <span id="midi-val-breath" class="w-6 tabular-nums" style="color: #d1d5db;">0</span>
          </div>
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="bsync"
            title="Click to toggle — CC16 / Breathing sync (Kuramoto R)"
          >
            <span class="text-[10px]" style="color: #2dd4bf;">BSy</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-bsync"
                class="h-full rounded-full transition-all duration-75"
                style="width: 0%; background: #14b8a6;"
              >
              </div>
            </div>
            <span id="midi-val-bsync" class="w-6 tabular-nums" style="color: #d1d5db;">0</span>
          </div>
          <div
            class="midi-meter flex items-center gap-1 cursor-pointer select-none rounded px-1 hover:bg-gray-700/50 transition-colors"
            data-midi-attr="hsync"
            title="Click to toggle — CC17 / HRV sync (Kuramoto R)"
          >
            <span class="text-[10px]" style="color: #818cf8;">HSy</span>
            <div class="w-16 h-3 rounded-full overflow-hidden" style="background: #374151;">
              <div
                id="midi-bar-hsync"
                class="h-full rounded-full transition-all duration-75"
                style="width: 0%; background: #6366f1;"
              >
              </div>
            </div>
            <span id="midi-val-hsync" class="w-6 tabular-nums" style="color: #d1d5db;">0</span>
          </div>
          <span
            id="midi-sync-trigger"
            class="text-yellow-400 font-bold opacity-0 transition-opacity duration-500 min-w-[70px]"
          >
          </span>
        </div>
        <button
          id="groove-help-btn"
          onclick="document.getElementById('groove-help-modal').classList.remove('hidden')"
          class="flex-shrink-0 w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold transition-colors"
          style="background: rgba(139,92,246,0.18); border: 1px solid rgba(139,92,246,0.35); color: #a78bfa;"
          title="What is GrooveEngine?"
        >
          ?
        </button>

        <%!-- AI Settings Modal (inside phx-update="ignore" zone) --%>
        <div
          id="ai-settings-modal"
          class="hidden fixed inset-0 z-50 flex items-center justify-center"
          style="background: rgba(0,0,0,0.6); backdrop-filter: blur(4px);"
        >
          <div
            class="rounded-xl p-5 w-full max-w-md mx-4 shadow-2xl"
            style="background: #1e1b2e; border: 1px solid #3b3556;"
          >
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-sm font-semibold" style="color: #c4b5fd;">AI Music Settings</h3>
              <button
                id="ai-settings-close"
                class="text-lg leading-none px-2 py-1 rounded hover:bg-gray-700 transition-colors"
                style="color: #9ca3af;"
              >
                &times;
              </button>
            </div>
            <%!-- Chord Progression --%>
            <div class="mb-4">
              <label class="block text-[11px] mb-1.5 font-medium" style="color: #a78bfa;">
                Chord Progression
              </label>
              <input
                id="ai-chords-input"
                type="text"
                placeholder="e.g. Am7 Dm7 G7 Cmaj7"
                class="w-full rounded-lg px-3 py-2 text-xs focus:outline-none"
                style="background: #0f0d1a; border: 1px solid #3b3556; color: #e2e0f0;"
              />
              <div id="ai-chord-presets" class="flex flex-wrap gap-1.5 mt-2">
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Dm7 G7 Cmaj7 Am7"
                >
                  Jazz ii-V-I
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Fmaj7 Em7 Dm7 Cmaj7"
                >
                  Neo Soul
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Am Fmaj7 C G"
                >
                  Lo-fi Chill
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Cm Fm Abmaj7 G7"
                >
                  Dark Cinema
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="C7 F7 C7 G7"
                >
                  Blues
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Dm7 G7 Cmaj7 A7"
                >
                  Bossa Nova
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Cmaj7 Am7 Fmaj7 G"
                >
                  Dreamy Pop
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Em Bm C D"
                >
                  Indie Rock
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Bbmaj7 Cm7 Fm7 Gm7"
                >
                  Reggae
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="C F G F"
                >
                  Ska
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="E A B A"
                >
                  Punk
                </button>
                <button
                  class="ai-preset-btn px-2 py-1 rounded text-[10px] transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-chords="Em G D C"
                >
                  Grunge
                </button>
              </div>
            </div>
            <%!-- Key Selector --%>
            <div class="mb-4">
              <label class="block text-[11px] mb-1.5 font-medium" style="color: #a78bfa;">
                Key
              </label>
              <div class="flex gap-2">
                <select
                  id="ai-key-root"
                  class="rounded-lg px-3 py-1.5 text-xs flex-1 focus:outline-none"
                  style="background: #0f0d1a; border: 1px solid #3b3556; color: #e2e0f0;"
                >
                  <option value="0">C</option>
                  <option value="1">C# / Db</option>
                  <option value="2">D</option>
                  <option value="3">Eb</option>
                  <option value="4">E</option>
                  <option value="5">F</option>
                  <option value="6">F# / Gb</option>
                  <option value="7">G</option>
                  <option value="8">Ab</option>
                  <option value="9">A</option>
                  <option value="10">Bb</option>
                  <option value="11">B</option>
                </select>
                <select
                  id="ai-key-quality"
                  class="rounded-lg px-3 py-1.5 text-xs flex-1 focus:outline-none"
                  style="background: #0f0d1a; border: 1px solid #3b3556; color: #e2e0f0;"
                >
                  <option value="major">Major</option>
                  <option value="minor" selected>Minor</option>
                </select>
              </div>
            </div>
            <%!-- Creativity Slider --%>
            <div class="mb-4">
              <label class="block text-[11px] mb-1.5 font-medium" style="color: #a78bfa;">
                Creativity
                <span id="ai-creativity-label" class="font-normal" style="color: #9ca3af;">
                  — Auto (from breathing)
                </span>
              </label>
              <div class="flex items-center gap-3">
                <span class="text-[10px]" style="color: #6b7280;">Tight</span>
                <input
                  id="ai-creativity-slider"
                  type="range"
                  min="0"
                  max="100"
                  value="50"
                  class="flex-1 h-1.5 rounded-full appearance-none cursor-pointer"
                  style="accent-color: #a78bfa; background: #2d2845;"
                />
                <span class="text-[10px]" style="color: #6b7280;">Wild</span>
              </div>
              <div class="flex items-center gap-2 mt-1.5">
                <label
                  class="flex items-center gap-1 text-[10px] cursor-pointer"
                  style="color: #9ca3af;"
                >
                  <input
                    id="ai-creativity-auto"
                    type="checkbox"
                    checked
                    class="rounded"
                    style="accent-color: #a78bfa;"
                  /> Auto (breathing controls creativity)
                </label>
              </div>
            </div>
            <%!-- Mood Override --%>
            <div class="mb-5">
              <label class="block text-[11px] mb-1.5 font-medium" style="color: #a78bfa;">
                Mood
              </label>
              <div class="flex gap-1.5" id="ai-mood-buttons">
                <button
                  class="ai-mood-btn flex-1 px-2 py-1.5 rounded-lg text-[10px] font-medium transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-mood="auto"
                >
                  Auto
                </button>
                <button
                  class="ai-mood-btn flex-1 px-2 py-1.5 rounded-lg text-[10px] font-medium transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-mood="calm"
                >
                  Calm
                </button>
                <button
                  class="ai-mood-btn flex-1 px-2 py-1.5 rounded-lg text-[10px] font-medium transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-mood="warm"
                >
                  Warm
                </button>
                <button
                  class="ai-mood-btn flex-1 px-2 py-1.5 rounded-lg text-[10px] font-medium transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-mood="tense"
                >
                  Tense
                </button>
                <button
                  class="ai-mood-btn flex-1 px-2 py-1.5 rounded-lg text-[10px] font-medium transition-colors"
                  style="background: #2d2845; color: #c4b5fd; border: 1px solid #3b3556;"
                  data-mood="intense"
                >
                  Intense
                </button>
              </div>
            </div>
            <%!-- Apply --%>
            <button
              id="ai-settings-apply"
              class="w-full py-2 rounded-lg text-xs font-semibold transition-colors"
              style="background: #7c3aed; color: white;"
            >
              Apply &amp; Generate
            </button>
          </div>
        </div>
      </div>

      <%!-- GrooveEngine Explanation Modal --%>
      <div
        id="groove-help-modal"
        class="hidden fixed inset-0 z-50 flex items-start justify-center"
        style="background: rgba(0,0,0,0.78); padding-top: 5vh;"
        onclick="if(event.target===this)this.classList.add('hidden')"
      >
        <div
          class="rounded-xl shadow-2xl w-full mx-4 flex flex-col"
          style="background: #12101f; border: 1px solid rgba(139,92,246,0.35); max-width: 680px; max-height: 88vh;"
        >
          <%!-- Header --%>
          <div
            class="flex items-center justify-between px-5 pt-4 pb-3 flex-shrink-0"
            style="border-bottom: 1px solid rgba(139,92,246,0.18);"
          >
            <div class="flex items-center gap-3">
              <span style="font-size:1.15rem;">🎛️</span>
              <h3 class="text-sm font-semibold tracking-wide" style="color: #c4b5fd;">
                GrooveEngine
              </h3>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full"
                style="background: rgba(139,92,246,0.15); color: #a78bfa; border: 1px solid rgba(139,92,246,0.25);"
              >
                Biometric → Music
              </span>
            </div>
            <div class="flex items-center gap-2">
              <%!-- Depth tabs --%>
              <div
                class="flex rounded-lg overflow-hidden text-[10px]"
                style="border: 1px solid rgba(139,92,246,0.3);"
              >
                <button
                  id="groove-depth-brief"
                  onclick="['brief','standard','full'].forEach(function(d){var c=document.getElementById('groove-content-'+d);var b=document.getElementById('groove-depth-'+d);if(c)c.style.display=d==='brief'?'':'none';if(b){b.style.background=d==='brief'?'rgba(139,92,246,0.35)':'transparent';b.style.color=d==='brief'?'#e9d5ff':'#7c6a9e'}})"
                  class="px-2.5 py-1 transition-colors"
                  style="background: rgba(139,92,246,0.35); color: #e9d5ff;"
                >
                  Brief
                </button>
                <button
                  id="groove-depth-standard"
                  onclick="['brief','standard','full'].forEach(function(d){var c=document.getElementById('groove-content-'+d);var b=document.getElementById('groove-depth-'+d);if(c)c.style.display=d==='standard'?'':'none';if(b){b.style.background=d==='standard'?'rgba(139,92,246,0.35)':'transparent';b.style.color=d==='standard'?'#e9d5ff':'#7c6a9e'}})"
                  class="px-2.5 py-1 transition-colors"
                  style="background: transparent; color: #7c6a9e; border-left: 1px solid rgba(139,92,246,0.3);"
                >
                  Standard
                </button>
                <button
                  id="groove-depth-full"
                  onclick="['brief','standard','full'].forEach(function(d){var c=document.getElementById('groove-content-'+d);var b=document.getElementById('groove-depth-'+d);if(c)c.style.display=d==='full'?'':'none';if(b){b.style.background=d==='full'?'rgba(139,92,246,0.35)':'transparent';b.style.color=d==='full'?'#e9d5ff':'#7c6a9e'}})"
                  class="px-2.5 py-1 transition-colors"
                  style="background: transparent; color: #7c6a9e; border-left: 1px solid rgba(139,92,246,0.3);"
                >
                  Full
                </button>
              </div>
              <button
                onclick="document.getElementById('groove-help-modal').classList.add('hidden')"
                class="text-lg leading-none w-7 h-7 flex items-center justify-center rounded hover:bg-gray-700 transition-colors"
                style="color: #9ca3af;"
              >
                &times;
              </button>
            </div>
          </div>

          <%!-- Scrollable body --%>
          <div
            class="overflow-y-auto px-5 py-4 text-[12px] leading-relaxed flex-1"
            style="color: #c9c4d8;"
          >
            <%!-- BRIEF (≈300 words) --%>
            <div id="groove-content-brief">
              <p class="mb-3">
                <strong style="color:#e9d5ff;">GrooveEngine</strong>
                is Sensocto's real-time biometric-to-music system. It reads live sensor data — heart rate, motion, breathing, gaze, skin conductance — from connected wearables and translates them continuously into musical output: notes, chords, rhythms, and dynamics.
              </p>
              <p class="mb-3">Three modes govern how sensor data becomes sound:</p>
              <p class="mb-2">
                <strong style="color:#c4b5fd;">Abstract</strong>
                sends raw sensor values directly as MIDI control changes and note triggers. Heart rate maps to tempo, motion to velocity, gaze to filter cutoff. Every sensor fluctuation is immediately audible without musical interpretation — useful for data sonification research or experimental performance.
              </p>
              <p class="mb-2">
                <strong style="color:#c4b5fd;">Groovy</strong>
                engages the full musical engine. It maintains a key and chord progression while different biometric streams simultaneously drive different musical layers: heart rate sets BPM, heart rate variability shapes chord tension (stress = dissonance), breathing modulates dynamics and filter, and wrist motion drives the arpeggiator. Four genre presets — House, Jazz, Ambient, Drum &amp; Bass — provide distinct harmonic vocabularies and rhythmic templates.
              </p>
              <p class="mb-2">
                <strong style="color:#c4b5fd;">Local AI</strong>
                replaces the rule-based generator with an on-device Magenta neural network (runs in the browser, no cloud). It generates melodic sequences from compressed biometric feature vectors. You control the key, base chord, and a creativity slider.
              </p>
              <p class="mb-3">
                In group sessions GrooveEngine creates an emergent collective soundtrack: a stressed participant shifts the chords darker, a calm one anchors the rhythm, and the group's mean heart rate drives the tempo — everyone exercising together causes a dramatic synchronized acceleration.
              </p>
              <p>
                Output routes via Web MIDI API to hardware synths and DAWs, Tone.js for in-browser synthesis, or both simultaneously. No external server is required.
              </p>
            </div>

            <%!-- STANDARD (≈900 words) --%>
            <div id="groove-content-standard" style="display:none;">
              <p class="mb-3">
                <strong style="color:#e9d5ff;">GrooveEngine</strong>
                is Sensocto's real-time biometric sonification engine — a musical translation layer that continuously reads physiological and motion data from connected sensors and converts it into meaningful sound. The goal is not to generate arbitrary noise from sensor readings, but to maintain musical structure while letting the body be the composer.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">How it works</p>
              <p class="mb-3">
                The engine lives entirely in the browser, receiving sensor measurements through Sensocto's PriorityLens data pipeline via the MidiOutputHook. Measurements arrive in real-time batches every 32–128ms and are processed in a loop that computes musical parameters. Output routes to two channels:
                <strong style="color:#d1d5db;">Web MIDI API</strong>
                for hardware synthesizers, external instruments, and MIDI-compatible software (DAWs, VCV Rack, Ableton); and
                <strong style="color:#d1d5db;">Tone.js</strong>
                for zero-latency in-browser polyphonic synthesis. Both can run simultaneously.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Abstract Mode</p>
              <p class="mb-3">
                Abstract is the direct data path. Each attribute maps to a MIDI control channel: heart rate → CC1 (modulation), breathing → CC2, skin conductance → CC7 (volume), gaze horizontal → CC10 (pan), gaze vertical → CC11 (expression), IMU acceleration → note velocity. When combined sensor values cross thresholds, note-on events fire on specific channels. The result is a maximal, unfiltered representation of the data — ideal for sonification research, live generative performance, or calibrating what your sensors are actually measuring.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Groovy Mode</p>
              <p class="mb-2">
                Groovy layers multiple biometric dimensions onto different musical parameters simultaneously:
              </p>
              <ul class="mb-3 space-y-1.5 pl-4" style="list-style: none;">
                <li>
                  <span style="color:#f9a8d4;">❤ Heart rate → BPM</span>
                  — The tempo tracks the mean HR across all connected participants. Resting (60 BPM) → slow groove. Exertion (120+ BPM) → double pace. Tempo changes are smoothed over 4 beats.
                </li>
                <li>
                  <span style="color:#c4b5fd;">⚡ HRV → Chord tension</span>
                  — High HRV (calm, recovered) maps to stable major/minor triads. Low HRV (stress) introduces suspended 4ths, diminished 7ths, and cluster voicings. The harmony becomes measurably darker when participants are under pressure.
                </li>
                <li>
                  <span style="color:#7dd3fc;">🌬 Breathing → Dynamics</span>
                  — Slow deep breaths open the low-pass filter, increase reverb, and stretch the amplitude envelope. Fast shallow breathing tightens the envelope, raises the high-pass cutoff, creating a more urgent, compressed sound.
                </li>
                <li>
                  <span style="color:#86efac;">🤙 IMU motion → Arpeggiator</span>
                  — Wrist acceleration drives the arpeggiator rate. Still sensors produce held chord pads; active motion produces rapid melodic runs across chord tones.
                </li>
                <li>
                  <span style="color:#fcd34d;">👁 Gaze → Spatial placement</span>
                  — Where eye-tracking is present, gaze direction controls stereo pan and reverb send. Your visual attention literally places sounds in the acoustic space.
                </li>
                <li>
                  <span style="color:#f87171;">⚡ Collective arousal → Density</span>
                  — Mean skin conductance across participants scales the number of simultaneous voices: low arousal → sparse texture; high arousal → full ensemble.
                </li>
              </ul>
              <p class="mb-3">
                Four genre presets configure the underlying harmonic vocabulary, bass pattern, drum kit, and timbres:
                <strong style="color:#d1d5db;">House</strong>
                (four-on-the-floor kick, synth bass, piano pad),
                <strong style="color:#d1d5db;">Jazz</strong>
                (walking bass, extended 9th/13th chords, brush snare),
                <strong style="color:#d1d5db;">Ambient</strong>
                (slow pad swells, no percussion, heavy reverb tails),
                <strong style="color:#d1d5db;">Drum &amp; Bass</strong>
                (tempo at 2× HR, Reese bass, jungle breaks).
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Local AI Mode</p>
              <p class="mb-3">
                Local AI replaces the rule-based note generator with a Magenta MusicRNN running on-device via TensorFlow.js — no data leaves the browser. The model receives a compressed biometric feature vector (last 8 seconds of normalized sensor readings) and generates a melodic continuation. Musical context (key, chord, scale) is maintained by the same harmonic system as Groovy mode. The ⚙ settings panel exposes key signature, base chord, and a creativity temperature slider: low values → conservative stepwise melodies; high values → adventurous leaps. Recommended range: 0.6–0.8.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Group dynamics</p>
              <p>
                In multi-participant sessions, GrooveEngine creates an emergent collective soundtrack. No single person controls the music — the group state produces it. When participants synchronize breathing (group meditation, yoga), the dynamics layer locks into alignment and the texture becomes calm and unified. When heart rates diverge (some exercising, some resting), harmonic layers pull against each other, creating productive tension. When collective arousal rises, all voices enter at once, producing a crescendo that mirrors group engagement. This makes GrooveEngine useful for biofeedback training, group workshops, live performance, installation art, and research on inter-subject physiological synchrony.
              </p>
            </div>

            <%!-- FULL (≈1800 words) --%>
            <div id="groove-content-full" style="display:none;">
              <p class="mb-3">
                <strong style="color:#e9d5ff;">GrooveEngine</strong>
                is Sensocto's real-time biometric sonification system — a musical translation layer that reads live physiological and motion data from connected wearable sensors and converts it continuously into structured sound: notes, chords, rhythms, and spatial dynamics. Unlike simple data-to-pitch mappings, GrooveEngine maintains musical coherence across multiple simultaneous biometric dimensions, treating the collective body as both composer and performer.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Signal Path</p>
              <p class="mb-3">
                The engine runs entirely in the browser as a JavaScript module attached to the graph views via MidiOutputHook. It subscribes to Sensocto's PriorityLens pipeline — the same attention-weighted, batched measurement stream that drives the visual sensor graph — delivering measurements from all connected participants at 32–128ms intervals depending on PriorityLens quality level. Raw measurements undergo feature extraction: current value, 4-second rolling average, rate of change (derivative), and a normalized 0–1 score relative to the plausible biological range for that attribute type. These normalized scores drive all three engine modes. Output routes to:
                <strong style="color:#d1d5db;">Web MIDI API</strong>
                for any connected hardware synthesizer, instrument, or MIDI-compatible software (Ableton, VCV Rack, Logic, SuperCollider); and
                <strong style="color:#d1d5db;">Tone.js</strong>
                for in-browser polyphonic synthesis. Both channels can run simultaneously with independent volume controls.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Abstract Mode</p>
              <p class="mb-2">
                Abstract mode is the most direct representation of sensor data as sound. Each monitored attribute maps to a specific MIDI control channel:
              </p>
              <div
                class="mb-3 rounded-lg overflow-hidden text-[11px]"
                style="border: 1px solid rgba(139,92,246,0.2);"
              >
                <table class="w-full">
                  <thead>
                    <tr style="background: rgba(139,92,246,0.15); color: #c4b5fd;">
                      <th class="px-3 py-1.5 text-left font-medium">Attribute</th>
                      <th class="px-3 py-1.5 text-left font-medium">MIDI CC</th>
                      <th class="px-3 py-1.5 text-left font-medium">Musical parameter</th>
                    </tr>
                  </thead>
                  <tbody style="color: #c9c4d8;">
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">Heart rate</td>
                      <td class="px-3 py-1">CC1</td>
                      <td class="px-3 py-1">Modulation wheel depth</td>
                    </tr>
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">Breathing rate</td>
                      <td class="px-3 py-1">CC2</td>
                      <td class="px-3 py-1">Breath controller</td>
                    </tr>
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">Skin conductance</td>
                      <td class="px-3 py-1">CC7</td>
                      <td class="px-3 py-1">Volume</td>
                    </tr>
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">Gaze X</td>
                      <td class="px-3 py-1">CC10</td>
                      <td class="px-3 py-1">Pan position</td>
                    </tr>
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">Gaze Y</td>
                      <td class="px-3 py-1">CC11</td>
                      <td class="px-3 py-1">Expression</td>
                    </tr>
                    <tr style="border-top: 1px solid rgba(139,92,246,0.12);">
                      <td class="px-3 py-1">IMU acceleration</td>
                      <td class="px-3 py-1">Velocity</td>
                      <td class="px-3 py-1">Note velocity</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p class="mb-3">
                When the weighted score of active sensors crosses a configurable threshold, note-on events fire on the corresponding MIDI channel. Pitch maps to a pentatonic scale in the current key signature, preventing dissonant semitone clashes while preserving continuous data character. Abstract mode is most useful for: data sonification research; experimental live performance where raw fidelity is desired; initial calibration to understand what sensors are actually measuring; and building custom MIDI mappings in external software.
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Groovy Mode</p>
              <p class="mb-2">
                Groovy mode synthesizes all available biometric streams into a coherent musical performance with a maintained key, chord progression, and rhythmic structure:
              </p>
              <p class="mb-2">
                <strong style="color:#f9a8d4;">Heart rate → BPM.</strong>
                The tempo tracks the rolling mean HR across all connected participants, mapped from 40–180 BPM (biological) to 60–180 BPM (musical). At resting HR the groove is slow and spacious; physical exertion doubles the pace. Tempo changes are smoothed over 4 beats to avoid jarring accelerations.
              </p>
              <p class="mb-2">
                <strong style="color:#c4b5fd;">HRV → Chord tension.</strong>
                Heart rate variability (RMSSD) controls harmonic color — this is physiologically significant: high HRV indicates parasympathetic activation and calm; low HRV indicates sympathetic dominance, stress, or fatigue. High HRV → stable major/minor triads and open intervals. Decreasing HRV → adds suspended 4ths and major 7ths (slightly unresolved). Very low HRV → diminished 7ths, augmented chords, dense cluster voicings. The harmony becomes measurably more tense when participants are under stress, creating an acoustic mirror of the group's autonomic state.
              </p>
              <p class="mb-2">
                <strong style="color:#7dd3fc;">Breathing → Dynamics.</strong>
                Respiratory rate and depth modulate the filter and dynamics of the entire mix. Slow deep breathing opens the low-pass filter, increases reverb depth, and stretches amplitude envelopes — the sound becomes airy and resonant. Fast shallow breathing tightens the envelope, raises the high-pass cutoff, increases compression, and reduces reverb return — the sound becomes tighter, more urgent. In sessions where breathing is specifically tracked, participants can hear their own respiratory pattern in the quality of the sound, creating an implicit biofeedback loop.
              </p>
              <p class="mb-2">
                <strong style="color:#86efac;">IMU motion → Arpeggiator.</strong>
                Wrist acceleration maps to arpeggiator rate: at rest, the arpeggiator is slow or off, and chord voicings are held as sustained pads. During active movement, the arpeggiator accelerates and weights note selection toward higher register chord tones, producing rapid melodic runs. Gyroscope rotation controls arpeggiator direction: forward rotation sweeps up through the chord; backward sweeps down.
              </p>
              <p class="mb-2">
                <strong style="color:#fcd34d;">Gaze → Spatial placement.</strong>
                Where eye-tracking is present, gaze direction controls stereo pan and reverb send. Looking left pans the voice left; looking up increases reverb return, creating a more distant sensation. In multichannel installations this extends to full 3D spatial audio.
              </p>
              <p class="mb-3">
                <strong style="color:#f87171;">Collective arousal → Ensemble density.</strong>
                Mean skin conductance across all participants scales the number of simultaneously active voices: low collective arousal produces sparse, minimal textures; rising arousal adds voices layer by layer until maximum arousal activates the full ensemble.
              </p>
              <p class="mb-2">The four genre presets define the musical identity:</p>
              <ul
                class="mb-3 space-y-1.5 pl-3 text-[11px]"
                style="color: #c9c4d8; list-style: none;"
              >
                <li>
                  <strong style="color:#d1d5db;">House</strong>
                  — Four-on-the-floor kick, Chicago-style synth bass, electric piano pad, open hi-hats. Chord vocabulary: major 7ths and minor 7ths with modal interchange. BPM range 110–130.
                </li>
                <li>
                  <strong style="color:#d1d5db;">Jazz</strong>
                  — Walking bass with voice-leading, extended 9th/11th/13th chords, brush snare on beats 2 &amp; 4, vibraphone or Rhodes comping. Tritone substitutions applied. Swing feel at all tempos.
                </li>
                <li>
                  <strong style="color:#d1d5db;">Ambient</strong>
                  — No percussion. Long chord swells (4–8s attack), bass drones held for the full chord, heavy convolution reverb with 8–12s tails. Melodic movement extremely slow, often staying on single tones for multiple bars.
                </li>
                <li>
                  <strong style="color:#d1d5db;">Drum &amp; Bass</strong>
                  — BPM at 2× mapped HR (160–180 BPM range). Reese bass (detuned sawtooth, heavy low-pass). Jungle break pattern with syncopated hi-hat rolls. Dark minor scales and chromatic bass movement.
                </li>
              </ul>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">Local AI Mode</p>
              <p class="mb-3">
                Local AI replaces the rule-based note generator with a Magenta MusicRNN running entirely in the browser via TensorFlow.js — no biometric data leaves the device, no server required. The model receives two inputs: a compressed biometric feature vector encoding the last 8 seconds of normalized sensor readings (heart rate, HRV, motion magnitude, skin conductance, breathing rate, and gaze stability), and a musical context vector encoding the current key, chord root, scale mode, and the last 4 generated notes. From these it generates a probability distribution over the next note, from which a note is sampled. The ⚙ settings panel exposes:
                <strong style="color:#d1d5db;">Key signature</strong>
                (tonal center and scale mode: major, natural minor, dorian, mixolydian, chromatic);
                <strong style="color:#d1d5db;">Base chord</strong>
                (root and quality); <strong style="color:#d1d5db;">Creativity</strong>
                (sampling temperature — 0.0 = always picks most likely prediction, very predictable; 1.0 = samples full distribution, adventurous; 0.6–0.8 recommended for most sessions).
              </p>

              <p class="mb-1 font-semibold" style="color: #a78bfa;">
                Group Dynamics &amp; Emergent Behavior
              </p>
              <p class="mb-3">
                GrooveEngine's most distinctive quality emerges in multi-participant sessions. With 10, 50, or 100 people each wearing sensors, each person's physiology contributes to different musical layers independently. No single participant controls the music — the collective state produces it emergently.
              </p>
              <p class="mb-3">
                Interesting phenomena arise: when a group synchronizes breathing (group meditation, yoga), the dynamics layer locks into a shared pattern and the texture becomes suddenly calm and unified. When heart rates diverge (some participants exercising, some resting), the rhythmic and harmonic layers pull against each other, creating productive tension. When everyone's arousal rises together (excitement, physical effort), all voices enter at once producing a crescendo that reflects collective engagement.
              </p>
              <p>
                This makes GrooveEngine applicable across:
                <strong style="color:#d1d5db;">biofeedback training</strong>
                (participants learn to recognize their physiological state by ear);
                <strong style="color:#d1d5db;">group workshops</strong>
                exploring collective regulation;
                <strong style="color:#d1d5db;">live performance</strong>
                where physiology is the score; <strong style="color:#d1d5db;">interactive installation art</strong>; and <strong style="color:#d1d5db;">physiological synchrony research</strong>. The music becomes a shared language for bodily states that are otherwise invisible.
              </p>
            </div>
          </div>

          <%!-- Footer --%>
          <div
            class="px-5 py-3 flex-shrink-0 flex items-center justify-between text-[10px]"
            style="border-top: 1px solid rgba(139,92,246,0.18); color: #6b5e8a;"
          >
            <span>Runs entirely in-browser · Web MIDI API + Tone.js · No external server</span>
            <button
              onclick="document.getElementById('groove-help-modal').classList.add('hidden')"
              class="px-3 py-1 rounded text-[11px] transition-colors"
              style="background: rgba(139,92,246,0.2); color: #c4b5fd; border: 1px solid rgba(139,92,246,0.3);"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
