defmodule SensoctoWeb.Components.AboutContentComponent do
  @moduledoc """
  Reusable LiveComponent for the About page content.
  Used in both AboutLive and CustomSignInLive to avoid duplication.
  """
  use SensoctoWeb, :live_component

  # Use cases organized by viewing lens
  @use_cases_by_lens %{
    technical: [
      {"stream", "cyan", "Movesense ECG and IMU data at 100Hz"},
      {"connect", "teal", "Nordic Thingy:52 via Web Bluetooth"},
      {"visualize", "blue", "GPS tracks from walking, cycling, or drones"},
      {"analyze", "emerald", "underwater hydrophone feeds with spectrograms"},
      {"process", "purple", "YOLOfish-style inference on live video"},
      {"capture", "amber", "9-axis IMU quaternions for motion analysis"},
      {"sync", "cyan", "distributed datasets via P2P CRDT networks"},
      {"export", "teal", "time-series data in scientific formats"},
      {"trigger", "violet", "actuators from sensor threshold rules"},
      {"monitor", "blue", "temperature, humidity, pressure, air quality"},
      {"stream", "pink", "ROV video feeds with real-time annotations"},
      {"integrate", "emerald", "Buttplug.io for haptic device control"},
      {"track", "cyan", "HRV and recovery metrics from medical wearables"},
      {"collect", "teal", "field research data stored locally on mobile"}
    ],
    empathy: [
      {"feel", "pink", "someone's nervousness before they speak"},
      {"sense", "rose", "a partner's desire without words"},
      {"know", "purple", "a friend is struggling before they ask"},
      {"share", "cyan", "your calm with an anxious loved one"},
      {"sync", "teal", "your breathing with a meditation circle"},
      {"notice", "amber", "your child's nightmare from another room"},
      {"witness", "green", "trust forming in a therapy session"},
      {"experience", "violet", "collective flow in a jam session"},
      {"feel", "blue", "the ocean's rhythm through a hydrophone"},
      {"sense", "pink", "when your partner needs to be held"},
      {"know", "emerald", "when words aren't needed anymore"},
      {"share", "cyan", "presence across distance and time"},
      {"feel", "rose", "your body's wisdom guiding decisions"},
      {"experience", "purple", "synchronized pleasure in real-time"}
    ],
    fun: [
      {"play", "yellow", "sensor-driven party games with friends"},
      {"pilot", "orange", "drones while sharing your excitement"},
      {"roll", "amber", "smart dice that glow with your heartbeat"},
      {"dance", "pink", "with haptic feedback synced to the beat"},
      {"explore", "cyan", "underwater worlds through ROV adventures"},
      {"create", "violet", "music from your collective heartbeats"},
      {"solve", "teal", "escape rooms with physiological puzzles"},
      {"jam", "rose", "together as instruments respond to your mood"},
      {"chill", "blue", "in calm-off sessions seeing who relaxes first"},
      {"breathe", "emerald", "together and watch your sync grow"},
      {"unlock", "purple", "new experiences by reaching flow states"},
      {"stream", "cyan", "your gameplay with live biometrics overlay"},
      {"vibe", "pink", "together at silent discos with shared pulse"},
      {"laugh", "yellow", "as haptic devices tickle synchronized giggles"}
    ],
    impact: [
      {"restore", "emerald", "coral reef ecosystems with AI monitoring"},
      {"enable", "violet", "independence for wheelchair users"},
      {"protect", "cyan", "marine biodiversity through acoustic detection"},
      {"support", "green", "mental health with trusted peer networks"},
      {"improve", "blue", "cystic fibrosis outcomes through gamification"},
      {"empower", "teal", "non-verbal communication via physiology"},
      {"prevent", "amber", "crises with early warning biometrics"},
      {"democratize", "purple", "research with P2P data collection"},
      {"assist", "pink", "caregivers with real-time patient monitoring"},
      {"accelerate", "cyan", "trauma healing with biofeedback"},
      {"detect", "emerald", "wandering risk via wearable location tracking"},
      {"transform", "violet", "physiotherapy into engaging games"},
      {"connect", "blue", "isolated individuals to support networks"},
      {"verify", "teal", "consent through embodied signals"}
    ],
    research: [
      {"quantify", "blue", "group synchronization in meditation studies"},
      {"measure", "cyan", "HRV responses to therapeutic interventions"},
      {"track", "teal", "marine migration patterns via bioacoustics"},
      {"analyze", "emerald", "coral health metrics across reef systems"},
      {"correlate", "purple", "physiological data with mood reports"},
      {"validate", "amber", "freediving training protocols with ECG"},
      {"study", "violet", "co-regulation dynamics in therapy dyads"},
      {"document", "pink", "species diversity with automated detection"},
      {"compare", "cyan", "recovery patterns across athlete cohorts"},
      {"observe", "teal", "circadian rhythm impacts on chronic conditions"},
      {"map", "blue", "stress patterns in distributed populations"},
      {"assess", "emerald", "intervention effectiveness with biometrics"},
      {"explore", "purple", "massive datasets like wildflow.org corals"},
      {"prototype", "amber", "assistive interfaces with sensor feedback"}
    ]
  }

  @lens_info [
    {:empathy,
     %{
       name: "Empathy",
       icon: "hero-heart",
       color: "pink",
       description: "Feelings, relationships, presence",
       featured: true
     }},
    {:fun,
     %{
       name: "Fun",
       icon: "hero-puzzle-piece",
       color: "yellow",
       description: "Games, play, entertainment",
       featured: false
     }},
    {:technical,
     %{
       name: "Technical",
       icon: "hero-cpu-chip",
       color: "cyan",
       description: "Sensors, protocols, data flows",
       featured: false
     }},
    {:impact,
     %{
       name: "Impact",
       icon: "hero-globe-alt",
       color: "emerald",
       description: "Social good, accessibility, outcomes",
       featured: false
     }},
    {:research,
     %{
       name: "Research",
       icon: "hero-beaker",
       color: "purple",
       description: "Science, analysis, discovery",
       featured: false
     }}
  ]

  @research_papers [
    %{
      title: "Interpersonal Autonomic Physiology: A Systematic Review of the Literature",
      authors: "Palumbo et al.",
      year: 2017,
      journal: "Personality and Social Psychology Review",
      doi: "10.1177/1088868316628405",
      category: :synchronization,
      description:
        "Systematic review defining interpersonal autonomic physiology and how physiological synchronization emerges during social interactions."
    },
    %{
      title: "State of the Art of Interpersonal Physiology in Psychotherapy: A Systematic Review",
      authors: "Kleinbub, R.",
      year: 2017,
      journal: "Frontiers in Psychology",
      doi: "10.3389/fpsyg.2017.02053",
      category: :therapy,
      description:
        "Reviews evidence for physiological synchrony between therapists and clients as a marker of therapeutic alliance."
    },
    %{
      title: "Social Ties and Mental Health",
      authors: "Kawachi & Berkman",
      year: 2001,
      journal: "Journal of Urban Health",
      doi: "10.1093/jurban/78.3.458",
      category: :care_networks,
      description:
        "Foundational work on how social networks influence mental health outcomes and crisis prevention."
    },
    %{
      title:
        "Partner Influence and In-Phase Versus Anti-Phase Physiological Linkage in Romantic Couples",
      authors: "Reed et al.",
      year: 2013,
      journal: "International Journal of Psychophysiology",
      doi: "10.1016/j.ijpsycho.2012.08.009",
      category: :synchronization,
      description:
        "Examines how partners' physiological systems co-regulate during emotional conversations and health discussions."
    },
    %{
      title:
        "Identifying Objective Physiological Markers Using Wearable Sensors and Mobile Phones",
      authors: "Sano et al.",
      year: 2018,
      journal: "Journal of Medical Internet Research",
      doi: "10.2196/jmir.9410",
      category: :wearables,
      description:
        "Uses wearable biosensors and machine learning to classify stress and mental health status in real-time."
    },
    %{
      title: "Biofeedback in the Treatment of Anxiety and PTSD",
      authors: "Tan et al.",
      year: 2011,
      journal: "Applied Psychophysiology and Biofeedback",
      doi: "10.1007/s10484-010-9141-x",
      category: :therapy,
      description:
        "Evidence for HRV biofeedback as an effective intervention for anxiety and trauma recovery."
    },
    %{
      title: "Peer Support in Mental Health: A Systematic Review",
      authors: "Repper & Carter",
      year: 2011,
      journal: "Journal of Mental Health",
      doi: "10.3109/09638237.2011.583947",
      category: :care_networks,
      description:
        "Systematic review of peer support effectiveness in mental health care and community interventions."
    },
    %{
      title: "Collective Effervescence and Synchrony in Ritual",
      authors: "Páez et al.",
      year: 2015,
      journal: "Frontiers in Psychology",
      doi: "10.3389/fpsyg.2015.01963",
      category: :synchronization,
      description:
        "Studies how group rituals produce physiological and emotional synchronization among participants."
    },
    %{
      title: "Autonomic Nervous System Dynamics for Mood Detection",
      authors: "Valenza et al.",
      year: 2014,
      journal: "IEEE Transactions on Affective Computing",
      doi: "10.1109/TAFFC.2014.2332167",
      category: :wearables,
      description:
        "Methods for detecting emotional states through autonomic nervous system monitoring via wearables."
    },
    %{
      title: "Technology-Mediated Compassion in Healthcare",
      authors: "Chen & Schultz",
      year: 2016,
      journal: "JMIR Mental Health",
      doi: "10.2196/mental.5316",
      category: :care_networks,
      description:
        "Explores how technology can enhance compassionate care in mental health treatment settings."
    }
  ]

  @paper_categories %{
    synchronization: %{
      name: "HRV Synchronization",
      color: "cyan",
      icon: "hero-arrows-right-left"
    },
    therapy: %{name: "Therapy & Healing", color: "green", icon: "hero-heart"},
    care_networks: %{name: "Care Networks", color: "purple", icon: "hero-users"},
    wearables: %{
      name: "Wearables & Monitoring",
      color: "blue",
      icon: "hero-device-phone-mobile"
    }
  }

  @research_summaries %{
    spark: """
    Human connection has a measurable heartbeat. When two people truly connect—in therapy, in love, in crisis support—their autonomic nervous systems begin to synchronize. Heart rate variability aligns. Breathing patterns match. This isn't metaphor; it's physiology.

    The research behind Sensocto spans four domains: interpersonal synchronization studies showing how bodies co-regulate during meaningful interactions; therapy research demonstrating that physiological attunement predicts therapeutic outcomes; care network studies proving that social ties directly impact mental health; and wearable technology research enabling real-time monitoring of these vital signs.

    What emerges is a scientific foundation for what humans have always intuited: presence is physical. Connection is measurable. And technology can amplify empathy rather than replace it. Sensocto builds on this research to create a platform where you don't just see someone's status update—you feel their actual state.
    """,
    story: """
    The science of human connection has revealed something profound: our bodies are constantly communicating beneath conscious awareness. When we sit with someone we trust, our heart rate variability begins to synchronize. When a therapist truly attunes to a client, their autonomic nervous systems enter a coordinated dance. This interpersonal physiology—documented across hundreds of peer-reviewed studies—forms the scientific foundation for everything Sensocto does.

    Palumbo and colleagues' systematic review of interpersonal autonomic physiology established that physiological synchronization reliably emerges during social interactions. This isn't random noise or coincidence. When humans engage meaningfully, their bodies begin to mirror each other. Reed's research on romantic couples showed this co-regulation extends to health discussions and emotional conversations—partners literally influence each other's nervous systems. Páez's work on collective rituals demonstrated that group synchronization produces the experience of "collective effervescence"—that feeling of being part of something larger than yourself.

    In therapeutic contexts, this synchronization becomes even more significant. Kleinbub's systematic review found that physiological attunement between therapist and client serves as a marker of therapeutic alliance—the single strongest predictor of positive outcomes in psychotherapy. Tan's research showed that HRV biofeedback can effectively treat anxiety and PTSD by helping individuals regulate their own nervous systems. The body remembers what the mind suppresses, and healing often happens through somatic pathways.

    The care network research adds another dimension. Kawachi and Berkman's foundational work demonstrated that social ties directly influence mental health outcomes. People embedded in supportive networks experience better outcomes across nearly every health measure. Repper and Carter's systematic review of peer support showed that mutual aid and lived experience create therapeutic value that professional intervention alone cannot replicate. Chen and Schultz explored how technology can enhance rather than diminish compassionate care.

    Finally, the wearable technology research makes all of this actionable. Sano's work showed that stress and mental health states can be classified in real-time using wearable biosensors. Valenza's research on autonomic nervous system dynamics demonstrated that emotional states can be detected through continuous monitoring. The hardware exists. The science is validated. What's been missing is a platform built on human values rather than attention extraction.

    Sensocto synthesizes these research streams into a coherent vision: a platform where presence is physiological, where support is proactive rather than reactive, where intimacy transcends distance, and where technology serves connection rather than performance. We're not building another social network. We're building the infrastructure for genuine human attunement.
    """,
    deep: """
    The research foundation for Sensocto represents a convergence of four scientific domains that together reveal an extraordinary opportunity: to use technology not as a replacement for human connection, but as an amplifier of our innate capacity for empathy and co-regulation. This body of research challenges fundamental assumptions about what technology can do for human relationships.

    INTERPERSONAL AUTONOMIC PHYSIOLOGY: THE SCIENCE OF SYNCHRONIZATION

    Palumbo and colleagues' 2017 systematic review in Personality and Social Psychology Review established interpersonal autonomic physiology as a rigorous field of study. Their comprehensive analysis of the literature defined the phenomenon: when humans engage in meaningful social interactions, their autonomic nervous systems—the unconscious regulatory systems controlling heart rate, breathing, and arousal—begin to synchronize. This synchronization isn't metaphorical. It's measurable in heart rate variability patterns, skin conductance responses, and respiratory rhythms.

    What makes this research particularly significant is its demonstration that synchronization varies with relationship quality. Strangers show minimal synchronization. Couples, therapists and clients, parents and children—these dyads show pronounced coupling that increases with trust and emotional connection. Reed and colleagues' 2013 research in the International Journal of Psychophysiology examined romantic partners specifically, finding that physiological linkage during emotional conversations reflects and reinforces the quality of the relationship. Partners don't just influence each other's moods; they literally shape each other's nervous system regulation.

    The group dimension adds further richness. Páez and colleagues' 2015 study of collective rituals in Frontiers in Psychology demonstrated that synchronized activities produce the experience Durkheim called "collective effervescence"—the profound sense of belonging and transcendence that occurs when groups move, breathe, or experience together. This research explains why meditation circles, dance parties, and protest marches feel so different from solitary activities. Our bodies are designed for collective experience, and synchronization is the physiological substrate.

    THERAPEUTIC APPLICATIONS: WHEN ATTUNEMENT HEALS

    The therapy research stream provides perhaps the most compelling case for Sensocto's approach. Kleinbub's 2017 systematic review in Frontiers in Psychology synthesized evidence on interpersonal physiology in psychotherapy, finding that therapist-client physiological synchrony serves as a reliable marker of therapeutic alliance. This matters enormously because therapeutic alliance—the quality of the working relationship between therapist and client—is the single strongest predictor of positive outcomes across all forms of psychotherapy, accounting for more variance than specific techniques or theoretical orientations.

    What this means practically is that effective therapy involves bodies, not just minds. When a therapist attunes to a client's nervous system state, co-regulation becomes possible. The therapist's calm can literally help regulate a dysregulated client. This somatic dimension of healing is often invisible in traditional therapy, but physiological monitoring makes it tangible and teachable.

    Tan and colleagues' 2011 research on biofeedback for anxiety and PTSD in Applied Psychophysiology and Biofeedback extended this insight to self-regulation. Their evidence showed that HRV biofeedback—learning to consciously influence heart rate variability—produces significant improvements in anxiety symptoms and trauma recovery. The body isn't just a site of symptoms; it's an active participant in healing. Teaching individuals to recognize and regulate their physiological states creates lasting change that top-down cognitive approaches often cannot achieve alone.

    CARE NETWORKS: SOCIAL TIES AS HEALTH INFRASTRUCTURE

    The care network research establishes the epidemiological significance of human connection. Kawachi and Berkman's 2001 paper in the Journal of Urban Health documented what subsequent research has repeatedly confirmed: social ties directly influence mental health outcomes. People with strong social networks experience lower rates of depression, better recovery from illness, reduced mortality risk, and improved quality of life across virtually every measure. Isolation is not just uncomfortable; it's a significant health risk factor comparable to smoking.

    Repper and Carter's 2011 systematic review of peer support in the Journal of Mental Health demonstrated that mutual aid creates therapeutic value that professional intervention alone cannot replicate. Peer supporters—individuals with lived experience of mental health challenges—provide a form of understanding and validation that differs qualitatively from professional care. This isn't about replacing clinicians; it's about recognizing that healing happens in community, not just in clinical settings.

    The challenge that current technology fails to address is the reactive nature of support. By the time someone posts about a crisis, the crisis is often well advanced. By the time friends notice withdrawal, isolation has already taken hold. What the research suggests is needed is proactive support—the ability to notice someone struggling before they can articulate it, to reach out before being asked.

    Chen and Schultz's 2016 research in JMIR Mental Health explored how technology might enhance rather than diminish compassionate care. Their work suggests that technology-mediated support can extend the reach of care networks without replacing their human core. The key is designing technology that facilitates genuine connection rather than substituting for it.

    WEARABLE TECHNOLOGY: FROM RESEARCH TO PRACTICE

    The final research stream makes the vision actionable. Sano and colleagues' 2018 paper in the Journal of Medical Internet Research demonstrated that wearable biosensors combined with machine learning can classify stress levels and mental health states with clinically useful accuracy. The data that matters—heart rate, HRV, skin conductance, sleep patterns, activity levels—can now be captured continuously in daily life, not just in laboratory settings.

    Valenza and colleagues' 2014 research in IEEE Transactions on Affective Computing developed methods for detecting emotional states through autonomic nervous system monitoring. Their work established that the information content in physiological signals is sufficient to distinguish between emotional states with meaningful reliability. Combined with advances in wearable hardware—medical-grade sensors now available in consumer devices—this research establishes that continuous physiological monitoring is technically feasible.

    WHY THIS MATTERS FOR SENSOCTO

    The synthesis of these four research streams points to a specific opportunity that current technology entirely misses. Social media platforms harvest attention for advertising revenue, creating incentive structures that favor outrage over calm, performance over authenticity, isolation disguised as connection. Healthcare systems remain reactive, responding to crises rather than preventing them. Therapy often treats the mind as separate from the body. Support networks rely on explicit communication that stigma and shame often prevent.

    Sensocto proposes something different: a platform where connection is physiological, not performative. Where a trusted friend can sense you're struggling before you post about it. Where a therapist can see nervous system dysregulation in real-time during sessions. Where romantic partners separated by distance can feel each other's presence through their actual heartbeats. Where groups can verify their synchronization in meditation, dance, or collective action.

    This isn't technological utopianism. The research is clear about what's possible and what's not. Physiological synchronization is real but doesn't replace verbal communication. Biofeedback is effective but requires practice and intention. Care networks matter but don't substitute for professional treatment when needed. What the research supports is a both/and approach: technology that enhances human capacity for connection rather than replacing it, that makes visible what was previously invisible, that creates the conditions for empathy without attempting to automate it.

    The scientific foundation is solid. The hardware exists. The research is validated. What's been missing is a platform designed from the ground up to serve human flourishing rather than extract human attention. That's what Sensocto aims to build—and why understanding this research matters for everyone who uses it.
    """
  }

  @impl true
  def mount(socket) do
    current_lens = :empathy
    shuffled = Enum.shuffle(@use_cases_by_lens[current_lens])

    socket =
      socket
      |> assign(:detail_level, :spark)
      |> assign(:current_lens, current_lens)
      |> assign(:lens_info, @lens_info)
      |> assign(:use_cases, shuffled)
      |> assign(:visible_count, 3)
      |> assign(:current_offset, 0)
      |> assign(:research_papers, @research_papers)
      |> assign(:paper_categories, @paper_categories)
      |> assign(:research_summaries, @research_summaries)
      |> assign(:research_summary_level, :spark)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Handle initial_detail_level on first mount
    socket =
      if assigns[:initial_detail_level] && !socket.assigns[:initialized] do
        socket
        |> assign(:detail_level, assigns.initial_detail_level)
        |> assign(:initialized, true)
      else
        socket
      end

    {:ok, assign(socket, Map.drop(assigns, [:initial_detail_level]))}
  end

  @impl true
  def handle_event("set_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, detail_level: String.to_existing_atom(level))}
  end

  @impl true
  def handle_event("set_lens", %{"lens" => lens}, socket) do
    lens = String.to_existing_atom(lens)
    shuffled = Enum.shuffle(@use_cases_by_lens[lens])

    socket =
      socket
      |> assign(:current_lens, lens)
      |> assign(:use_cases, shuffled)
      |> assign(:current_offset, 0)

    {:noreply, socket}
  end

  @impl true
  def handle_event("shuffle_use_cases", _params, socket) do
    use_cases = socket.assigns.use_cases
    visible_count = socket.assigns.visible_count
    current_offset = socket.assigns.current_offset
    total = length(use_cases)

    new_offset = current_offset + visible_count

    {new_cases, new_offset} =
      if new_offset >= total do
        {Enum.shuffle(use_cases), 0}
      else
        {use_cases, new_offset}
      end

    {:noreply, assign(socket, use_cases: new_cases, current_offset: new_offset)}
  end

  @impl true
  def handle_event("set_visible_count", %{"count" => count}, socket) do
    count = String.to_integer(count)
    {:noreply, assign(socket, visible_count: count, current_offset: 0)}
  end

  @impl true
  def handle_event("set_summary_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, research_summary_level: String.to_existing_atom(level))}
  end

  defp visible_use_cases(use_cases, offset, count) do
    use_cases
    |> Enum.drop(offset)
    |> Enum.take(count)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="about-content">
      <%!-- Hero Section --%>
      <div class="relative overflow-hidden">
        <div
          class="absolute inset-0 bg-gradient-to-r from-blue-900/20 via-cyan-900/10 to-purple-900/20 animate-pulse"
          style="animation-duration: 4s;"
        >
        </div>

        <div class="relative max-w-4xl mx-auto px-4 py-12 sm:py-16 text-center">
          <h1 class="text-4xl sm:text-5xl font-bold bg-gradient-to-r from-cyan-400 via-blue-400 to-purple-400 bg-clip-text text-transparent mb-4">
            SensOcto
          </h1>
          <p class="text-xl text-gray-400 mb-8">
            Feel someone's presence. Not their performance.
          </p>

          <%!-- Detail Level Switcher --%>
          <div class="flex flex-wrap justify-center gap-2 mb-12">
            <button
              phx-click="set_level"
              phx-value-level="spark"
              phx-target={@myself}
              class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                if @detail_level == :spark do
                  "bg-cyan-500 text-white shadow-lg shadow-cyan-500/30"
                else
                  "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                end}
            >
              The Spark
            </button>
            <button
              phx-click="set_level"
              phx-value-level="story"
              phx-target={@myself}
              class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                if @detail_level == :story do
                  "bg-blue-500 text-white shadow-lg shadow-blue-500/30"
                else
                  "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                end}
            >
              The Story
            </button>
            <button
              phx-click="set_level"
              phx-value-level="deep"
              phx-target={@myself}
              class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                if @detail_level == :deep do
                  "bg-purple-500 text-white shadow-lg shadow-purple-500/30"
                else
                  "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                end}
            >
              The Deep Dive
            </button>
            <button
              phx-click="set_level"
              phx-value-level="research"
              phx-target={@myself}
              class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                if @detail_level == :research do
                  "bg-amber-500 text-white shadow-lg shadow-amber-500/30"
                else
                  "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                end}
            >
              Research
            </button>
          </div>
        </div>
      </div>

      <%!-- Content Sections --%>
      <div class="max-w-4xl mx-auto px-4 pb-24 flex flex-col">
        <%!-- THE SPARK section (order changes based on detail level, hidden on research) --%>
        <div
          :if={@detail_level != :research}
          class={
            case @detail_level do
              :spark -> "order-1 mb-12 text-center"
              :story -> "order-2 mb-12 text-center border-t border-gray-800 pt-8 mt-8"
              :deep -> "order-3 mb-12 text-center border-t border-gray-800 pt-8 mt-8"
              _ -> "hidden"
            end
          }
        >
          <div class="inline-block px-3 py-1 bg-cyan-500/20 text-cyan-400 rounded-full text-xs font-medium mb-6">
            THE SPARK
          </div>

          <p class="text-2xl sm:text-3xl text-white leading-relaxed max-w-3xl mx-auto mb-8">
            Technology promised connection and delivered <span class="text-gray-500">performance</span>.
            We scroll, we perform, we feel more alone.
          </p>
          <%!-- Lens Switcher --%>
          <div class="flex justify-center items-center gap-2 mb-6 flex-wrap">
            <%= for {lens_key, info} <- @lens_info do %>
              <button
                phx-click="set_lens"
                phx-value-lens={lens_key}
                phx-target={@myself}
                class={"flex items-center transition-all duration-300 rounded-full font-medium " <>
                  if info.featured do
                    "gap-2 px-4 py-2 text-sm "
                  else
                    "gap-1.5 px-3 py-1.5 text-xs "
                  end <>
                  if @current_lens == lens_key do
                    "bg-#{info.color}-500/20 text-#{info.color}-400 ring-1 ring-#{info.color}-500/50"
                  else
                    "bg-gray-800/50 text-gray-500 hover:text-gray-300 hover:bg-gray-700/50"
                  end}
                title={info.description}
              >
                <.icon name={info.icon} class={if info.featured, do: "h-4 w-4", else: "h-3.5 w-3.5"} />
                <span>{info.name}</span>
              </button>
            <% end %>
          </div>

          <%!-- Clickable Use Cases Carousel --%>
          <div
            class="text-xl text-gray-400 max-w-2xl mx-auto mb-6 cursor-pointer hover:text-gray-300 transition-colors group"
            phx-click="shuffle_use_cases"
            phx-target={@myself}
            title="Click for more examples"
          >
            <p class="leading-relaxed">
              What if you could
              <%= for {{verb, color, rest}, index} <- Enum.with_index(visible_use_cases(@use_cases, @current_offset, @visible_count)) do %>
                <span class={"text-#{color}-400 font-medium"}>{verb}</span>
                {rest}{if index < @visible_count - 1, do: "? ", else: "?"}
              <% end %>
            </p>
            <div class="flex items-center justify-center gap-2 mt-3 text-sm text-gray-500 group-hover:text-gray-400 transition-colors">
              <.icon name="hero-arrow-path" class="h-4 w-4" />
              <span>Click for more examples</span>
            </div>
          </div>

          <%!-- Slider for visible count --%>
          <form
            phx-change="set_visible_count"
            phx-target={@myself}
            class="flex items-center justify-center gap-4 mb-8"
          >
            <label class="text-sm text-gray-500">Show</label>
            <input
              type="range"
              min="1"
              max="6"
              value={@visible_count}
              name="count"
              class="w-32 h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-cyan-500"
            />
            <span class="text-sm text-cyan-400 w-6 text-center">{@visible_count}</span>
          </form>

          <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 max-w-2xl mx-auto">
            <p class="text-lg text-gray-300 italic">
              "Connection becomes tangible when you can feel someone's presence—their heartbeat, their calm, their stress—in real-time."
            </p>
          </div>
        </div>

        <%!-- The Story: Human Use Cases (hidden on research tab) --%>
        <div class={
          "transition-all duration-500 overflow-hidden " <>
            (if @detail_level in [:story, :deep], do: "opacity-100 max-h-[4000px]", else: "opacity-0 max-h-0 pointer-events-none") <>
            " " <>
            (case @detail_level do
              :story -> "order-1"
              :deep -> "order-2"
              _ -> ""
            end)
        }>
          <div class="border-t border-gray-800 pt-12 mb-12">
            <div class="inline-block px-3 py-1 bg-blue-500/20 text-blue-400 rounded-full text-xs font-medium mb-6">
              THE STORY
            </div>

            <h2 class="text-2xl font-semibold text-white mb-8 text-center">
              Built for humans who want to <span class="text-blue-400">truly</span> connect
            </h2>

            <div class="grid gap-6 mb-10">
              <%!-- Therapy & Healing --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-green-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-green-500/20 rounded-lg shrink-0">
                    <.icon name="hero-heart" class="h-6 w-6 text-green-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">Therapy & Healing</h3>
                    <p class="text-gray-400 mb-3">
                      Therapists see nervous system dysregulation in real-time. HRV, breathing patterns, heart rate—visible during sessions. Trust forms faster when bodies sync. Healing accelerates with biofeedback.
                    </p>
                    <p class="text-green-400 text-sm">
                      "See the nervous system respond before words form."
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Disability & Care --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-blue-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-blue-500/20 rounded-lg shrink-0">
                    <.icon name="hero-hand-raised" class="h-6 w-6 text-blue-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">
                      Disability Care & Non-Verbal Communication
                    </h3>
                    <p class="text-gray-400 mb-3">
                      For those who cannot speak their needs—non-verbal individuals, wheelchair users, those with chronic conditions—physiological signals become their voice. Caregivers sense when someone needs help before they ask.
                    </p>
                    <p class="text-blue-400 text-sm">
                      "Dignity and agency restored through embodied communication."
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Mental Health Networks --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-purple-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-purple-500/20 rounded-lg shrink-0">
                    <.icon name="hero-users" class="h-6 w-6 text-purple-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">
                      Mental Health & Trusted Networks
                    </h3>
                    <p class="text-gray-400 mb-3">
                      Peer support networks are reactive—friends don't know someone's in crisis until it's too late. With shared physiology, trusted contacts see rising stress patterns and can reach out proactively.
                    </p>
                    <p class="text-purple-400 text-sm">
                      "Prevention over crisis. Community as safety net."
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Intimacy & Connection --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-pink-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-pink-500/20 rounded-lg shrink-0">
                    <.icon name="hero-sparkles" class="h-6 w-6 text-pink-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">Intimacy & Real Connection</h3>
                    <p class="text-gray-400 mb-3">
                      Real arousal, real connection. Digital lovers, musicians and audiences, actors and viewers, interviewers and guests, sensual caregivers—anyone sharing intimate moments across distance can finally feel each other's presence.
                    </p>
                    <p class="text-pink-400 text-sm">
                      "Presence you can feel, not just see."
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Groups & Collective Presence --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-cyan-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-cyan-500/20 rounded-lg shrink-0">
                    <.icon name="hero-user-group" class="h-6 w-6 text-cyan-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">
                      Groups & Collective Presence
                    </h3>
                    <p class="text-gray-400 mb-3">
                      Teams feel collective calm or tension. Meditation groups verify synchronization. Performers read live audience engagement. Rituals become measurable. Groups self-regulate as organisms.
                    </p>
                    <p class="text-cyan-400 text-sm">
                      "Emergent collective intelligence through shared physiology."
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Environmental Monitoring --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-emerald-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-emerald-500/20 rounded-lg shrink-0">
                    <.icon name="hero-globe-alt" class="h-6 w-6 text-emerald-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">
                      Environmental Monitoring
                    </h3>
                    <p class="text-gray-400 mb-3">
                      Coral reef restoration with edge AI cameras detecting fish species and health metrics. Environmental sensors tracking water quality, temperature, and ecosystem vitals. Real-time telemetry from remote locations.
                    </p>
                    <p class="text-emerald-400 text-sm">
                      "From coral reefs to urban gardens—sensing what matters."
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <%!-- The Promise --%>
            <div class="bg-gradient-to-r from-cyan-900/20 via-blue-900/20 to-purple-900/20 rounded-xl p-8 border border-gray-700/50 text-center">
              <h3 class="text-xl font-semibold text-white mb-4">The Promise</h3>
              <p class="text-lg text-gray-300 max-w-2xl mx-auto">
                Connection measured in <span class="text-red-400">heartbeats</span>, not dopamine hits.
                Technology that <span class="text-cyan-400">amplifies empathy</span>
                instead of exploiting attention.
                No harvesting. No surveillance. No algorithms deciding who sees what.
              </p>
            </div>
          </div>
        </div>

        <%!-- The Deep Dive: Architecture as Values --%>
        <div class={
          "transition-all duration-500 overflow-hidden " <>
            (if @detail_level == :deep, do: "opacity-100 max-h-[3000px] order-1", else: "opacity-0 max-h-0 pointer-events-none")
        }>
          <div class="border-t border-gray-800 pt-12">
            <div class="inline-block px-3 py-1 bg-purple-500/20 text-purple-400 rounded-full text-xs font-medium mb-6">
              THE DEEP DIVE
            </div>

            <h2 class="text-2xl font-semibold text-white mb-4 text-center">
              Every technical decision is a <span class="text-purple-400">moral statement</span>
            </h2>

            <p class="text-gray-400 text-center mb-8 max-w-2xl mx-auto">
              Architecture shapes incentives. We built Sensocto so that privacy and human dignity are structural guarantees, not policy promises.
            </p>

            <%!-- P2P as Foundation --%>
            <div class="mb-8">
              <h3 class="text-xl font-semibold text-white mb-4">Why Peer-to-Peer?</h3>
              <div class="grid sm:grid-cols-2 gap-4">
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                  <div class="text-gray-400 text-sm">Server costs create monetization pressure</div>
                  <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                  <div class="text-gray-300 text-sm">
                    Near-zero marginal cost. No need to harvest data.
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                  <div class="text-gray-400 text-sm">Data harvesting for ad targeting</div>
                  <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                  <div class="text-gray-300 text-sm">
                    Data stays on your devices. Privacy by structure.
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                  <div class="text-gray-400 text-sm">Deplatforming and censorship risk</div>
                  <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                  <div class="text-gray-300 text-sm">
                    No central authority. Communities cannot be silenced.
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                  <div class="text-gray-400 text-sm">Surveillance by design</div>
                  <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                  <div class="text-gray-300 text-sm">
                    End-to-end encryption native. Intimate data protected.
                  </div>
                </div>
              </div>
            </div>

            <%!-- Biomimetic Intelligence --%>
            <div class="mb-8">
              <h3 class="text-xl font-semibold text-white mb-4">Biomimetic Intelligence</h3>
              <p class="text-gray-400 mb-4">
                Beneath the surface, Sensocto operates like a living organism—adapting, learning, self-regulating.
              </p>
              <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3 text-sm">
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-yellow-400 font-medium">Novelty Detection</div>
                  <div class="text-gray-500">Alertness to anomalous data</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-blue-400 font-medium">Predictive Load Balancing</div>
                  <div class="text-gray-500">Anticipates demand spikes</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-green-400 font-medium">Homeostatic Tuning</div>
                  <div class="text-gray-500">Self-adapting thresholds</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-purple-400 font-medium">Attention-Aware Batching</div>
                  <div class="text-gray-500">Respects user focus</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-cyan-400 font-medium">Circadian Scheduling</div>
                  <div class="text-gray-500">Daily pattern learning</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-pink-400 font-medium">Resource Arbitration</div>
                  <div class="text-gray-500">Competitive allocation</div>
                </div>
              </div>
            </div>

            <%!-- Open Source Note --%>
            <div class="text-center text-gray-500 text-sm">
              <p>
                Built with <span class="text-red-400">♥</span>
                for humans who believe technology should serve connection, not extraction.
              </p>
            </div>
          </div>
        </div>

        <%!-- Research Tab Section --%>
        <div :if={@detail_level == :research} class="order-1">
          <div class="inline-block px-3 py-1 bg-amber-500/20 text-amber-400 rounded-full text-xs font-medium mb-6">
            RESEARCH
          </div>

          <h2 class="text-2xl font-semibold text-white mb-4 text-center">
            Scientific <span class="text-amber-400">foundations</span> for human connection
          </h2>

          <p class="text-gray-400 text-center mb-8 max-w-2xl mx-auto">
            Our approach is grounded in peer-reviewed research on physiological synchronization, care networks, and wearable technology for mental health.
          </p>

          <%!-- Research Summary with depth levels --%>
          <div class="mb-8 bg-gradient-to-br from-amber-900/20 via-gray-800/50 to-purple-900/20 rounded-xl p-6 border border-amber-500/20">
            <div class="flex flex-wrap items-center justify-between gap-4 mb-4">
              <h4 class="text-lg font-medium text-white">
                <.icon name="hero-document-text" class="h-5 w-5 inline-block mr-2 text-amber-400" />
                Research Synthesis
              </h4>
              <div class="flex gap-2">
                <button
                  phx-click="set_summary_level"
                  phx-value-level="spark"
                  phx-target={@myself}
                  class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all " <>
                    if @research_summary_level == :spark do
                      "bg-amber-500 text-white"
                    else
                      "bg-gray-700 text-gray-400 hover:text-white hover:bg-gray-600"
                    end}
                >
                  Brief (~300 words)
                </button>
                <button
                  phx-click="set_summary_level"
                  phx-value-level="story"
                  phx-target={@myself}
                  class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all " <>
                    if @research_summary_level == :story do
                      "bg-amber-500 text-white"
                    else
                      "bg-gray-700 text-gray-400 hover:text-white hover:bg-gray-600"
                    end}
                >
                  Standard (~900 words)
                </button>
                <button
                  phx-click="set_summary_level"
                  phx-value-level="deep"
                  phx-target={@myself}
                  class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all " <>
                    if @research_summary_level == :deep do
                      "bg-amber-500 text-white"
                    else
                      "bg-gray-700 text-gray-400 hover:text-white hover:bg-gray-600"
                    end}
                >
                  Deep Dive (~1800 words)
                </button>
              </div>
            </div>
            <div class={"prose prose-invert prose-sm max-w-none " <>
              if @research_summary_level == :deep do
                "max-h-[600px] overflow-y-auto pr-2"
              else
                ""
              end}>
              <div class="text-gray-300 leading-relaxed whitespace-pre-line">
                {@research_summaries[@research_summary_level]}
              </div>
            </div>
          </div>

          <%!-- Category filters --%>
          <div class="flex flex-wrap gap-2 mb-6">
            <%= for {_key, cat} <- @paper_categories do %>
              <span class={"inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-#{cat.color}-500/20 text-#{cat.color}-400"}>
                <.icon name={cat.icon} class="h-3.5 w-3.5" />
                {cat.name}
              </span>
            <% end %>
          </div>

          <%!-- Papers list --%>
          <div class="space-y-4">
            <%= for paper <- @research_papers do %>
              <% cat = @paper_categories[paper.category] %>
              <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50 hover:border-amber-500/30 transition-colors">
                <div class="flex items-start gap-3">
                  <div class={"p-2 rounded-lg shrink-0 bg-#{cat.color}-500/20"}>
                    <.icon name={cat.icon} class={"h-4 w-4 text-#{cat.color}-400"} />
                  </div>
                  <div class="flex-1 min-w-0">
                    <h4 class="text-white font-medium text-sm leading-tight mb-1">
                      {paper.title}
                    </h4>
                    <p class="text-gray-500 text-xs mb-2">
                      {paper.authors} ({paper.year}) ·
                      <span class="text-gray-600">{paper.journal}</span>
                    </p>
                    <p class="text-gray-400 text-sm">
                      {paper.description}
                    </p>
                    <a
                      href={"https://doi.org/#{paper.doi}"}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center gap-1 mt-2 text-xs text-amber-400 hover:text-amber-300 transition-colors"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> DOI: {paper.doi}
                    </a>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Footer CTA (optional, controlled by show_cta prop) --%>
        <div :if={Map.get(assigns, :show_cta, true)} class="mt-12 text-center order-last">
          <.link
            navigate={~p"/sign-in"}
            class="inline-flex items-center gap-2 px-6 py-3 bg-cyan-600 hover:bg-cyan-500 text-white font-medium rounded-lg transition-colors"
          >
            <.icon name="hero-play" class="h-5 w-5" /> Get Started
          </.link>
        </div>
      </div>

      <style>
        @keyframes float {
          0%, 100% { transform: translateY(0px); }
          50% { transform: translateY(-10px); }
        }
        .animate-float {
          animation: float 3s ease-in-out infinite;
        }
      </style>
    </div>
    """
  end
end
