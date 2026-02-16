defmodule SensoctoWeb.Components.AboutContentComponent do
  @moduledoc """
  Reusable LiveComponent for the About page content.
  Used in both AboutLive and CustomSignInLive to avoid duplication.
  """
  use SensoctoWeb, :live_component

  # Use cases organized by viewing lens - converted to function for gettext support
  defp use_cases_by_lens do
    %{
      technical: [
        {gettext("stream"), "cyan", gettext("Movesense ECG and IMU data at 100Hz")},
        {gettext("connect"), "teal", gettext("Nordic Thingy:52 via Web Bluetooth")},
        {gettext("visualize"), "blue", gettext("GPS tracks from walking, cycling, or drones")},
        {gettext("analyze"), "emerald", gettext("underwater hydrophone feeds with spectrograms")},
        {gettext("process"), "purple", gettext("YOLOfish-style inference on live video")},
        {gettext("capture"), "amber", gettext("9-axis IMU quaternions for motion analysis")},
        {gettext("sync"), "cyan", gettext("distributed datasets via P2P CRDT networks")},
        {gettext("export"), "teal", gettext("time-series data in scientific formats")},
        {gettext("trigger"), "violet", gettext("actuators from sensor threshold rules")},
        {gettext("monitor"), "blue", gettext("temperature, humidity, pressure, air quality")},
        {gettext("stream"), "pink", gettext("ROV video feeds with real-time annotations")},
        {gettext("integrate"), "emerald", gettext("Buttplug.io for haptic device control")},
        {gettext("track"), "cyan", gettext("HRV and recovery metrics from medical wearables")},
        {gettext("collect"), "teal", gettext("field research data stored locally on mobile")}
      ],
      empathy: [
        {gettext("feel"), "pink", gettext("someone's nervousness before they speak")},
        {gettext("sense"), "rose", gettext("a partner's desire without words")},
        {gettext("know"), "purple", gettext("a friend is struggling before they ask")},
        {gettext("share"), "cyan", gettext("your calm with an anxious loved one")},
        {gettext("sync"), "teal", gettext("your breathing with a meditation circle")},
        {gettext("notice"), "amber", gettext("your child's nightmare from another room")},
        {gettext("witness"), "green", gettext("trust forming in a therapy session")},
        {gettext("experience"), "violet", gettext("collective flow in a jam session")},
        {gettext("feel"), "blue", gettext("the ocean's rhythm through a hydrophone")},
        {gettext("sense"), "pink", gettext("when your partner needs to be held")},
        {gettext("know"), "emerald", gettext("when words aren't needed anymore")},
        {gettext("share"), "cyan", gettext("presence across distance and time")},
        {gettext("feel"), "rose", gettext("your body's wisdom guiding decisions")},
        {gettext("experience"), "purple", gettext("synchronized pleasure in real-time")}
      ],
      fun: [
        {gettext("play"), "yellow", gettext("sensor-driven party games with friends")},
        {gettext("pilot"), "orange", gettext("drones while sharing your excitement")},
        {gettext("roll"), "amber", gettext("smart dice that glow with your heartbeat")},
        {gettext("dance"), "pink", gettext("with haptic feedback synced to the beat")},
        {gettext("explore"), "cyan", gettext("underwater worlds through ROV adventures")},
        {gettext("create"), "violet", gettext("music from your collective heartbeats")},
        {gettext("solve"), "teal", gettext("escape rooms with physiological puzzles")},
        {gettext("jam"), "rose", gettext("together as instruments respond to your mood")},
        {gettext("chill"), "blue", gettext("in calm-off sessions seeing who relaxes first")},
        {gettext("breathe"), "emerald", gettext("together and watch your sync grow")},
        {gettext("unlock"), "purple", gettext("new experiences by reaching flow states")},
        {gettext("stream"), "cyan", gettext("your gameplay with live biometrics overlay")},
        {gettext("vibe"), "pink", gettext("together at silent discos with shared pulse")},
        {gettext("laugh"), "yellow", gettext("as haptic devices tickle synchronized giggles")}
      ],
      impact: [
        {gettext("restore"), "emerald", gettext("coral reef ecosystems with AI monitoring")},
        {gettext("enable"), "violet", gettext("independence for wheelchair users")},
        {gettext("protect"), "cyan", gettext("marine biodiversity through acoustic detection")},
        {gettext("support"), "green", gettext("mental health with trusted peer networks")},
        {gettext("improve"), "blue", gettext("cystic fibrosis outcomes through gamification")},
        {gettext("empower"), "teal", gettext("non-verbal communication via physiology")},
        {gettext("prevent"), "amber", gettext("crises with early warning biometrics")},
        {gettext("democratize"), "purple", gettext("research with P2P data collection")},
        {gettext("assist"), "pink", gettext("caregivers with real-time patient monitoring")},
        {gettext("accelerate"), "cyan", gettext("trauma healing with biofeedback")},
        {gettext("detect"), "emerald", gettext("wandering risk via wearable location tracking")},
        {gettext("transform"), "violet", gettext("physiotherapy into engaging games")},
        {gettext("connect"), "blue", gettext("isolated individuals to support networks")},
        {gettext("verify"), "teal", gettext("consent through embodied signals")}
      ],
      research: [
        {gettext("quantify"), "blue", gettext("group synchronization in meditation studies")},
        {gettext("measure"), "cyan", gettext("HRV responses to therapeutic interventions")},
        {gettext("track"), "teal", gettext("marine migration patterns via bioacoustics")},
        {gettext("analyze"), "emerald", gettext("coral health metrics across reef systems")},
        {gettext("correlate"), "purple", gettext("physiological data with mood reports")},
        {gettext("validate"), "amber", gettext("freediving training protocols with ECG")},
        {gettext("study"), "violet", gettext("co-regulation dynamics in therapy dyads")},
        {gettext("document"), "pink", gettext("species diversity with automated detection")},
        {gettext("compare"), "cyan", gettext("recovery patterns across athlete cohorts")},
        {gettext("observe"), "teal", gettext("circadian rhythm impacts on chronic conditions")},
        {gettext("map"), "blue", gettext("stress patterns in distributed populations")},
        {gettext("assess"), "emerald", gettext("intervention effectiveness with biometrics")},
        {gettext("explore"), "purple", gettext("massive datasets like wildflow.org corals")},
        {gettext("prototype"), "amber", gettext("assistive interfaces with sensor feedback")}
      ]
    }
  end

  defp lens_info do
    [
      {:empathy,
       %{
         name: gettext("Empathy"),
         icon: "hero-heart",
         color: "pink",
         description: gettext("Feelings, relationships, presence"),
         featured: true
       }},
      {:fun,
       %{
         name: gettext("Fun"),
         icon: "hero-puzzle-piece",
         color: "yellow",
         description: gettext("Games, play, entertainment"),
         featured: false
       }},
      {:technical,
       %{
         name: gettext("Technical"),
         icon: "hero-cpu-chip",
         color: "cyan",
         description: gettext("Sensors, protocols, data flows"),
         featured: false
       }},
      {:impact,
       %{
         name: gettext("Impact"),
         icon: "hero-globe-alt",
         color: "emerald",
         description: gettext("Social good, accessibility, outcomes"),
         featured: false
       }},
      {:research,
       %{
         name: gettext("Research"),
         icon: "hero-beaker",
         color: "purple",
         description: gettext("Science, analysis, discovery"),
         featured: false
       }}
    ]
  end

  defp research_papers do
    [
      # Recent Research (2024-2025)
      %{
        title:
          "Exploring Cardiac Physiological Synchrony and Its Implications for Stress and Anxiety",
        authors: "Escobar et al.",
        year: 2025,
        journal: "Ageing and Neurodegenerative Diseases",
        doi: "10.20517/and.2025.14",
        category: :synchronization,
        description:
          gettext(
            "Comprehensive review of cardiac physiological synchrony (CPS) mechanisms—cognitive, mechanical, and environmental—and their roles in empathy, stress, and anxiety."
          )
      },
      %{
        title:
          "Moral Decision-Making Style, Moral Persuasion, and Interpersonal Neurophysiological Synchronization",
        authors: "Ciminaghi et al.",
        year: 2025,
        journal: "Adaptive Human Behavior and Physiology",
        doi: "10.1007/s40750-025-00266-5",
        category: :synchronization,
        description:
          gettext(
            "EEG-BIO hyperscanning study showing how moral alignment between individuals modulates neural and autonomic (including HRV) synchronization during persuasion."
          )
      },
      %{
        title: "Interpersonal Synchrony Research in Human Groups",
        authors: "Gordon, I.",
        year: 2025,
        journal: "Social and Personality Psychology Compass",
        doi: "10.1111/spc3.70068",
        category: :group_dynamics,
        description:
          gettext(
            "Argues that interpersonal synchrony functions as 'social glue' and presents a theoretical framework for studying group synchrony beyond dyads."
          )
      },
      %{
        title: "How and Why People Synchronize: An Integrated Perspective",
        authors: "daSilva & Wood",
        year: 2025,
        journal: "Personality and Social Psychology Review",
        doi: "10.1177/10888683241252036",
        category: :synchronization,
        description:
          gettext(
            "Major synthesis proposing a unified framework with six dimensions of synchrony form and four core functions: reducing complexity, accomplishing joint tasks, strengthening connection, and influencing partners."
          )
      },
      %{
        title:
          "Interpersonal Physiological Synchrony During Dyadic Joint Action Is Increased by Task Novelty and Reduced by Social Anxiety",
        authors: "Boukarras et al.",
        year: 2025,
        journal: "Psychophysiology",
        doi: "10.1111/psyp.70031",
        category: :synchronization,
        description:
          gettext(
            "Demonstrates that social anxiety reduces physiological synchrony during cooperative tasks, while task novelty increases it—contextual and individual factors shape autonomic alignment."
          )
      },
      %{
        title:
          "Interpersonal Conversations Are Characterized by Increases in Respiratory Sinus Arrhythmia",
        authors: "Stuart et al.",
        year: 2025,
        journal: "Psychophysiology",
        doi: "10.1111/psyp.70043",
        category: :synchronization,
        description:
          gettext(
            "Study of 712 adults showing RSA increases during interpersonal conversations regardless of relationship type, connecting vagally mediated HRV to self-regulatory and interpersonal processes."
          )
      },
      %{
        title:
          "Interpersonal Heart Rate Synchrony Predicts Effective Information Processing in a Naturalistic Group Decision-Making Task",
        authors: "Sharika et al.",
        year: 2024,
        journal: "PNAS",
        doi: "10.1073/pnas.2313801121",
        category: :group_dynamics,
        description:
          gettext(
            "Heart rate synchrony predicted correct group consensus with >70% cross-validation accuracy across 44 groups, providing a biomarker of interpersonal engagement."
          )
      },
      # Foundational Research (2001-2018)
      %{
        title:
          "Identifying Objective Physiological Markers Using Wearable Sensors and Mobile Phones",
        authors: "Sano et al.",
        year: 2018,
        journal: "Journal of Medical Internet Research",
        doi: "10.2196/jmir.9410",
        category: :wearables,
        description:
          gettext(
            "Uses wearable biosensors and machine learning to classify stress and mental health status in real-time."
          )
      },
      %{
        title: "Interpersonal Autonomic Physiology: A Systematic Review of the Literature",
        authors: "Palumbo et al.",
        year: 2017,
        journal: "Personality and Social Psychology Review",
        doi: "10.1177/1088868316628405",
        category: :synchronization,
        description:
          gettext(
            "Systematic review defining interpersonal autonomic physiology and how physiological synchronization emerges during social interactions."
          )
      },
      %{
        title:
          "State of the Art of Interpersonal Physiology in Psychotherapy: A Systematic Review",
        authors: "Kleinbub, R.",
        year: 2017,
        journal: "Frontiers in Psychology",
        doi: "10.3389/fpsyg.2017.02053",
        category: :therapy,
        description:
          gettext(
            "Reviews evidence for physiological synchrony between therapists and clients as a marker of therapeutic alliance."
          )
      },
      %{
        title: "Technology-Mediated Compassion in Healthcare",
        authors: "Chen & Schultz",
        year: 2016,
        journal: "JMIR Mental Health",
        doi: "10.2196/mental.5316",
        category: :care_networks,
        description:
          gettext(
            "Explores how technology can enhance compassionate care in mental health treatment settings."
          )
      },
      %{
        title: "Collective Effervescence and Synchrony in Ritual",
        authors: "Páez et al.",
        year: 2015,
        journal: "Frontiers in Psychology",
        doi: "10.3389/fpsyg.2015.01963",
        category: :group_dynamics,
        description:
          gettext(
            "Studies how group rituals produce physiological and emotional synchronization among participants."
          )
      },
      %{
        title: "Autonomic Nervous System Dynamics for Mood Detection",
        authors: "Valenza et al.",
        year: 2014,
        journal: "IEEE Transactions on Affective Computing",
        doi: "10.1109/TAFFC.2014.2332167",
        category: :wearables,
        description:
          gettext(
            "Methods for detecting emotional states through autonomic nervous system monitoring via wearables."
          )
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
          gettext(
            "Examines how partners' physiological systems co-regulate during emotional conversations and health discussions."
          )
      },
      %{
        title: "Biofeedback in the Treatment of Anxiety and PTSD",
        authors: "Tan et al.",
        year: 2011,
        journal: "Applied Psychophysiology and Biofeedback",
        doi: "10.1007/s10484-010-9141-x",
        category: :therapy,
        description:
          gettext(
            "Evidence for HRV biofeedback as an effective intervention for anxiety and trauma recovery."
          )
      },
      %{
        title: "Peer Support in Mental Health: A Systematic Review",
        authors: "Repper & Carter",
        year: 2011,
        journal: "Journal of Mental Health",
        doi: "10.3109/09638237.2011.583947",
        category: :care_networks,
        description:
          gettext(
            "Systematic review of peer support effectiveness in mental health care and community interventions."
          )
      },
      %{
        title: "Social Ties and Mental Health",
        authors: "Kawachi & Berkman",
        year: 2001,
        journal: "Journal of Urban Health",
        doi: "10.1093/jurban/78.3.458",
        category: :care_networks,
        description:
          gettext(
            "Foundational work on how social networks influence mental health outcomes and crisis prevention."
          )
      }
    ]
  end

  defp paper_categories do
    %{
      synchronization: %{
        name: gettext("HRV Synchronization"),
        color: "cyan",
        icon: "hero-arrows-right-left"
      },
      group_dynamics: %{
        name: gettext("Group Dynamics"),
        color: "orange",
        icon: "hero-user-group"
      },
      therapy: %{name: gettext("Therapy & Healing"), color: "green", icon: "hero-heart"},
      care_networks: %{name: gettext("Care Networks"), color: "purple", icon: "hero-users"},
      wearables: %{
        name: gettext("Wearables & Monitoring"),
        color: "blue",
        icon: "hero-device-phone-mobile"
      }
    }
  end

  defp research_summaries do
    %{
      spark:
        gettext(
          "Human connection has a measurable heartbeat. When two people truly connect—in therapy, in love, in crisis support—their autonomic nervous systems begin to synchronize. Heart rate variability aligns. Breathing patterns match. This isn't metaphor; it's physiology.\n\nThe research behind Sensocto spans five domains: interpersonal synchronization studies showing how bodies co-regulate during meaningful interactions; group dynamics research revealing synchrony as \"social glue\" that predicts collective outcomes; therapy research demonstrating that physiological attunement predicts therapeutic outcomes; care network studies proving that social ties directly impact mental health; and wearable technology research enabling real-time monitoring of these vital signs.\n\nA wave of 2024-2025 research has strengthened this foundation dramatically. Heart rate synchrony now predicts group consensus with over 70%% accuracy (PNAS 2024). Respiratory sinus arrhythmia increases during conversations regardless of relationship type. A unified framework identifies six dimensions of synchrony and four core functions. Social anxiety reduces physiological alignment, while shared novelty amplifies it. What emerges is a scientific foundation for what humans have always intuited: presence is physical, connection is measurable, and technology can amplify empathy rather than replace it."
        ),
      story:
        gettext(
          "The science of human connection has revealed something profound: our bodies are constantly communicating beneath conscious awareness. When we sit with someone we trust, our heart rate variability begins to synchronize. When a therapist truly attunes to a client, their autonomic nervous systems enter a coordinated dance. This interpersonal physiology—documented across hundreds of peer-reviewed studies—forms the scientific foundation for everything Sensocto does.\n\nPalumbo and colleagues' systematic review of interpersonal autonomic physiology established that physiological synchronization reliably emerges during social interactions. This isn't random noise or coincidence. When humans engage meaningfully, their bodies begin to mirror each other. Reed's research on romantic couples showed this co-regulation extends to health discussions and emotional conversations—partners literally influence each other's nervous systems. Páez's work on collective rituals demonstrated that group synchronization produces the experience of \"collective effervescence\"—that feeling of being part of something larger than yourself.\n\nIn therapeutic contexts, this synchronization becomes even more significant. Kleinbub's systematic review found that physiological attunement between therapist and client serves as a marker of therapeutic alliance—the single strongest predictor of positive outcomes in psychotherapy. Tan's research showed that HRV biofeedback can effectively treat anxiety and PTSD by helping individuals regulate their own nervous systems. The body remembers what the mind suppresses, and healing often happens through somatic pathways.\n\nThe care network research adds another dimension. Kawachi and Berkman's foundational work demonstrated that social ties directly influence mental health outcomes. People embedded in supportive networks experience better outcomes across nearly every health measure. Repper and Carter's systematic review of peer support showed that mutual aid and lived experience create therapeutic value that professional intervention alone cannot replicate. Chen and Schultz explored how technology can enhance rather than diminish compassionate care.\n\nThe wearable technology research makes all of this actionable. Sano's work showed that stress and mental health states can be classified in real-time using wearable biosensors. Valenza's research on autonomic nervous system dynamics demonstrated that emotional states can be detected through continuous monitoring. The hardware exists. The science is validated.\n\nRecent advances (2024-2025) have transformed the field from foundational observation to predictive science. Sharika and colleagues demonstrated in PNAS that heart rate synchrony predicts correct group consensus with over 70%% accuracy—establishing physiological alignment as a genuine biomarker of collective intelligence. daSilva and Wood's major synthesis in Personality and Social Psychology Review proposed a unified framework classifying synchrony along six dimensions with four core functions: reducing complexity, accomplishing joint tasks, strengthening social bonds, and influencing partners. Stuart's study of 712 adults showed that respiratory sinus arrhythmia increases during face-to-face conversations regardless of relationship type—our bodies prepare for connection before we consciously engage. Boukarras found that social anxiety reduces physiological synchrony while task novelty increases it, and Escobar's review mapped the mechanisms of cardiac synchrony to empathy, stress, and anxiety pathways. Gordon's framework positions synchrony as \"social glue\" operating at the group level, while Ciminaghi's hyperscanning study revealed that even moral alignment modulates neural and autonomic coupling.\n\nSensocto synthesizes these research streams into a coherent vision: a platform where presence is physiological, where support is proactive rather than reactive, where intimacy transcends distance, and where technology serves connection rather than performance. We're not building another social network. We're building the infrastructure for genuine human attunement."
        ),
      deep:
        Enum.join(
          [
            gettext(
              "The research foundation for Sensocto represents a convergence of four scientific domains that together reveal an extraordinary opportunity: to use technology not as a replacement for human connection, but as an amplifier of our innate capacity for empathy and co-regulation. This body of research challenges fundamental assumptions about what technology can do for human relationships."
            ),
            gettext(
              "INTERPERSONAL AUTONOMIC PHYSIOLOGY: THE SCIENCE OF SYNCHRONIZATION\n\nPalumbo and colleagues' 2017 systematic review in Personality and Social Psychology Review established interpersonal autonomic physiology as a rigorous field of study. Their comprehensive analysis of the literature defined the phenomenon: when humans engage in meaningful social interactions, their autonomic nervous systems—the unconscious regulatory systems controlling heart rate, breathing, and arousal—begin to synchronize. This synchronization isn't metaphorical. It's measurable in heart rate variability patterns, skin conductance responses, and respiratory rhythms.\n\nWhat makes this research particularly significant is its demonstration that synchronization varies with relationship quality. Strangers show minimal synchronization. Couples, therapists and clients, parents and children—these dyads show pronounced coupling that increases with trust and emotional connection. Reed and colleagues' 2013 research in the International Journal of Psychophysiology examined romantic partners specifically, finding that physiological linkage during emotional conversations reflects and reinforces the quality of the relationship. Partners don't just influence each other's moods; they literally shape each other's nervous system regulation.\n\nThe group dimension adds further richness. Páez and colleagues' 2015 study of collective rituals in Frontiers in Psychology demonstrated that synchronized activities produce the experience Durkheim called \"collective effervescence\"—the profound sense of belonging and transcendence that occurs when groups move, breathe, or experience together. This research explains why meditation circles, dance parties, and protest marches feel so different from solitary activities. Our bodies are designed for collective experience, and synchronization is the physiological substrate."
            ),
            gettext(
              "THERAPEUTIC APPLICATIONS: WHEN ATTUNEMENT HEALS\n\nThe therapy research stream provides perhaps the most compelling case for Sensocto's approach. Kleinbub's 2017 systematic review in Frontiers in Psychology synthesized evidence on interpersonal physiology in psychotherapy, finding that therapist-client physiological synchrony serves as a reliable marker of therapeutic alliance. This matters enormously because therapeutic alliance—the quality of the working relationship between therapist and client—is the single strongest predictor of positive outcomes across all forms of psychotherapy, accounting for more variance than specific techniques or theoretical orientations.\n\nWhat this means practically is that effective therapy involves bodies, not just minds. When a therapist attunes to a client's nervous system state, co-regulation becomes possible. The therapist's calm can literally help regulate a dysregulated client. This somatic dimension of healing is often invisible in traditional therapy, but physiological monitoring makes it tangible and teachable.\n\nTan and colleagues' 2011 research on biofeedback for anxiety and PTSD in Applied Psychophysiology and Biofeedback extended this insight to self-regulation. Their evidence showed that HRV biofeedback—learning to consciously influence heart rate variability—produces significant improvements in anxiety symptoms and trauma recovery. The body isn't just a site of symptoms; it's an active participant in healing. Teaching individuals to recognize and regulate their physiological states creates lasting change that top-down cognitive approaches often cannot achieve alone."
            ),
            gettext(
              "CARE NETWORKS: SOCIAL TIES AS HEALTH INFRASTRUCTURE\n\nThe care network research establishes the epidemiological significance of human connection. Kawachi and Berkman's 2001 paper in the Journal of Urban Health documented what subsequent research has repeatedly confirmed: social ties directly influence mental health outcomes. People with strong social networks experience lower rates of depression, better recovery from illness, reduced mortality risk, and improved quality of life across virtually every measure. Isolation is not just uncomfortable; it's a significant health risk factor comparable to smoking.\n\nRepper and Carter's 2011 systematic review of peer support in the Journal of Mental Health demonstrated that mutual aid creates therapeutic value that professional intervention alone cannot replicate. Peer supporters—individuals with lived experience of mental health challenges—provide a form of understanding and validation that differs qualitatively from professional care. This isn't about replacing clinicians; it's about recognizing that healing happens in community, not just in clinical settings.\n\nThe challenge that current technology fails to address is the reactive nature of support. By the time someone posts about a crisis, the crisis is often well advanced. By the time friends notice withdrawal, isolation has already taken hold. What the research suggests is needed is proactive support—the ability to notice someone struggling before they can articulate it, to reach out before being asked.\n\nChen and Schultz's 2016 research in JMIR Mental Health explored how technology might enhance rather than diminish compassionate care. Their work suggests that technology-mediated support can extend the reach of care networks without replacing their human core. The key is designing technology that facilitates genuine connection rather than substituting for it."
            ),
            gettext(
              "WEARABLE TECHNOLOGY: FROM RESEARCH TO PRACTICE\n\nThe final research stream makes the vision actionable. Sano and colleagues' 2018 paper in the Journal of Medical Internet Research demonstrated that wearable biosensors combined with machine learning can classify stress levels and mental health states with clinically useful accuracy. The data that matters—heart rate, HRV, skin conductance, sleep patterns, activity levels—can now be captured continuously in daily life, not just in laboratory settings.\n\nValenza and colleagues' 2014 research in IEEE Transactions on Affective Computing developed methods for detecting emotional states through autonomic nervous system monitoring. Their work established that the information content in physiological signals is sufficient to distinguish between emotional states with meaningful reliability. Combined with advances in wearable hardware—medical-grade sensors now available in consumer devices—this research establishes that continuous physiological monitoring is technically feasible."
            ),
            gettext(
              "RECENT ADVANCES: GROUP DYNAMICS AND UNIFIED FRAMEWORKS (2024-2025)\n\nThe most recent wave of research has elevated synchrony science from observation to prediction, and from dyads to groups. Sharika and colleagues' 2024 study in PNAS represents a watershed moment: using multidimensional recurrence quantification analysis and machine learning on 44 groups (204 participants), they demonstrated that interpersonal heart rate synchrony predicted correct group consensus with over 70%% cross-validation accuracy—significantly higher than discussion duration, subjective assessments, or baseline heart rates. This establishes physiological synchronization not merely as a correlate of connection but as a predictive biomarker of collective intelligence.\n\ndaSilva and Wood's 2025 synthesis in Personality and Social Psychology Review provided the field's first unified framework, classifying synchrony along six dimensions—periodicity, discreteness, spatial similarity, directionality, leader-follower dynamics, and observability—and distilling four core functions: reducing complexity and improving understanding, accomplishing joint tasks, strengthening social connection, and influencing partners' behavior. This framework resolves longstanding fragmentation across disciplines studying the same phenomenon under different names.\n\nGordon's 2025 review in Social and Personality Psychology Compass extended the theoretical lens beyond dyads, arguing that interpersonal synchrony functions as \"social glue\" at the group level and proposing a neuroscience-informed framework for understanding why some groups succeed while others fail. This group-level perspective is critical for applications like meditation circles, team coordination, and collective rituals.\n\nAt the physiological mechanism level, Stuart and colleagues' 2025 study of 712 adults in Psychophysiology revealed that respiratory sinus arrhythmia—a marker of vagal regulation—increases during face-to-face conversations regardless of relationship type or topic. This finding suggests that our autonomic nervous systems actively prepare for social engagement, a process independent of conscious intention. Boukarras and colleagues found that social anxiety dampens this natural synchronization during cooperative tasks, while task novelty amplifies it—pointing toward specific intervention targets for social anxiety treatment. Escobar's comprehensive review mapped three mechanisms of cardiac physiological synchrony—cognitive, mechanical, and environmental—to empathy expression and anxiety manifestation. Ciminaghi's EEG-BIO hyperscanning study added a striking finding: even moral alignment between individuals modulates both neural and autonomic coupling during persuasion tasks, suggesting that shared values create deeper physiological resonance."
            ),
            gettext(
              "WHY THIS MATTERS FOR SENSOCTO\n\nThe synthesis of these five research streams points to a specific opportunity that current technology entirely misses. Social media platforms harvest attention for advertising revenue, creating incentive structures that favor outrage over calm, performance over authenticity, isolation disguised as connection. Healthcare systems remain reactive, responding to crises rather than preventing them. Therapy often treats the mind as separate from the body. Support networks rely on explicit communication that stigma and shame often prevent.\n\nSensocto proposes something different: a platform where connection is physiological, not performative. Where a trusted friend can sense you're struggling before you post about it. Where a therapist can see nervous system dysregulation in real-time during sessions. Where romantic partners separated by distance can feel each other's presence through their actual heartbeats. Where groups can verify their synchronization in meditation, dance, or collective action.\n\nThis isn't technological utopianism. The research is clear about what's possible and what's not. Physiological synchronization is real but doesn't replace verbal communication. Biofeedback is effective but requires practice and intention. Care networks matter but don't substitute for professional treatment when needed. What the research supports is a both/and approach: technology that enhances human capacity for connection rather than replacing it, that makes visible what was previously invisible, that creates the conditions for empathy without attempting to automate it.\n\nThe scientific foundation is solid. The hardware exists. The research is validated. What's been missing is a platform designed from the ground up to serve human flourishing rather than extract human attention. That's what Sensocto aims to build—and why understanding this research matters for everyone who uses it."
            )
          ],
          "\n\n"
        )
    }
  end

  @impl true
  def mount(socket) do
    current_lens = :empathy
    shuffled = Enum.shuffle(use_cases_by_lens()[current_lens])

    socket =
      socket
      |> assign(:detail_level, :spark)
      |> assign(:patch_base, nil)
      |> assign(:current_lens, current_lens)
      |> assign(:lens_info, lens_info())
      |> assign(:use_cases, shuffled)
      |> assign(:visible_count, 3)
      |> assign(:current_offset, 0)
      |> assign(:research_papers, research_papers())
      |> assign(:paper_categories, paper_categories())
      |> assign(:research_summaries, research_summaries())
      |> assign(:research_summary_level, :spark)
      |> assign(:carousel_index, 0)
      |> assign(:show_full_video, false)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      if Map.has_key?(assigns, :detail_level) do
        assign(socket, :detail_level, assigns.detail_level)
      else
        socket
      end

    {:ok, assign(socket, Map.drop(assigns, [:detail_level]))}
  end

  @impl true
  def handle_event("set_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, detail_level: String.to_existing_atom(level))}
  end

  @impl true
  def handle_event("set_lens", %{"lens" => lens}, socket) do
    lens = String.to_existing_atom(lens)
    shuffled = Enum.shuffle(use_cases_by_lens()[lens])

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

  @impl true
  def handle_event("carousel_prev", _params, socket) do
    index = rem(socket.assigns.carousel_index - 1 + 5, 5)
    {:noreply, assign(socket, carousel_index: index)}
  end

  @impl true
  def handle_event("carousel_next", _params, socket) do
    index = rem(socket.assigns.carousel_index + 1, 5)
    {:noreply, assign(socket, carousel_index: index)}
  end

  @impl true
  def handle_event("carousel_goto", %{"index" => index}, socket) do
    {:noreply, assign(socket, carousel_index: String.to_integer(index))}
  end

  @impl true
  def handle_event("carousel_keydown", %{"key" => "ArrowRight"}, socket) do
    index = rem(socket.assigns.carousel_index + 1, 5)
    {:noreply, assign(socket, carousel_index: index)}
  end

  def handle_event("carousel_keydown", %{"key" => "ArrowLeft"}, socket) do
    index = rem(socket.assigns.carousel_index - 1 + 5, 5)
    {:noreply, assign(socket, carousel_index: index)}
  end

  def handle_event("carousel_keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_full_video", _params, socket) do
    {:noreply, assign(socket, show_full_video: !socket.assigns.show_full_video)}
  end

  # Renders a translated string with **highlighted** word in a colored span.
  # Translators can place the **word** anywhere in the sentence for natural grammar.
  attr :text, :string, required: true
  attr :color, :string, required: true

  defp hl(assigns) do
    case String.split(assigns.text, "**", parts: 3) do
      [before, word, rest] ->
        assigns = assign(assigns, before: before, word: word, rest: rest)

        ~H"""
        {@before}<span class={"text-#{@color}-400"}>{@word}</span>{@rest}
        """

      _ ->
        ~H"{@text}"
    end
  end

  attr :level, :atom, required: true
  attr :current, :atom, required: true
  attr :patch_base, :string, default: nil
  attr :target, :any, default: nil
  slot :inner_block, required: true

  defp level_button(assigns) do
    assigns = assign(assigns, :class, level_button_class(assigns.level, assigns.current))

    ~H"""
    <%= if @patch_base do %>
      <.link
        patch={if @level == :spark, do: @patch_base, else: "#{@patch_base}?tab=#{@level}"}
        class={@class}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button phx-click="set_level" phx-value-level={@level} phx-target={@target} class={@class}>
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp level_button_class(level, current) do
    base = "px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 "

    if level == current do
      base <>
        case level do
          :spark -> "bg-cyan-600 text-white shadow-lg shadow-cyan-600/40"
          :story -> "bg-blue-600 text-white shadow-lg shadow-blue-600/40"
          :deep -> "bg-purple-600 text-white shadow-lg shadow-purple-600/40"
          :research -> "bg-[#6b8e23] text-white shadow-lg shadow-[#6b8e23]/40"
          :videos -> "bg-rose-600 text-white shadow-lg shadow-rose-600/40"
        end
    else
      base <>
        "bg-gray-600 text-gray-100 hover:text-white hover:bg-gray-500 ring-1 ring-gray-500"
    end
  end

  defp visible_use_cases(use_cases, offset, count) do
    use_cases
    |> Enum.drop(offset)
    |> Enum.take(count)
  end

  defp research_paper_card(assigns) do
    assigns = assign(assigns, :cat, assigns.paper_categories[assigns.paper.category])

    ~H"""
    <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50 hover:border-amber-500/30 transition-colors">
      <div class="flex items-start gap-3">
        <div class={"p-2 rounded-lg shrink-0 bg-#{@cat.color}-500/20"}>
          <.icon name={@cat.icon} class={"h-4 w-4 text-#{@cat.color}-400"} />
        </div>
        <div class="flex-1 min-w-0">
          <h4 class="text-white font-medium text-sm leading-tight mb-1">
            {@paper.title}
          </h4>
          <p class="text-gray-500 text-xs mb-2">
            {@paper.authors} ({@paper.year}) · <span class="text-gray-600">{@paper.journal}</span>
          </p>
          <p class="text-gray-400 text-sm">
            {@paper.description}
          </p>
          <a
            href={"https://doi.org/#{@paper.doi}"}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 mt-2 text-xs text-amber-400 hover:text-amber-300 transition-colors"
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> DOI: {@paper.doi}
          </a>
        </div>
      </div>
    </div>
    """
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
            {gettext("Feel someone's presence. Not their performance.")}
          </p>

          <%!-- Detail Level Switcher --%>
          <div class="flex flex-wrap justify-center gap-2 mb-12">
            <.level_button
              level={:spark}
              current={@detail_level}
              patch_base={@patch_base}
              target={@myself}
            >
              {gettext("The Spark")}
            </.level_button>
            <.level_button
              level={:story}
              current={@detail_level}
              patch_base={@patch_base}
              target={@myself}
            >
              {gettext("The Story")}
            </.level_button>
            <.level_button
              level={:deep}
              current={@detail_level}
              patch_base={@patch_base}
              target={@myself}
            >
              {gettext("The Deep Dive")}
            </.level_button>
            <.level_button
              level={:research}
              current={@detail_level}
              patch_base={@patch_base}
              target={@myself}
            >
              {gettext("Research")}
            </.level_button>
            <.level_button
              level={:videos}
              current={@detail_level}
              patch_base={@patch_base}
              target={@myself}
            >
              {gettext("Videos")}
            </.level_button>
          </div>
        </div>
      </div>

      <%!-- Content Sections --%>
      <div class="max-w-4xl mx-auto px-4 pb-24 flex flex-col">
        <%!-- THE SPARK section (order changes based on detail level, hidden on research) --%>
        <div
          :if={@detail_level not in [:research, :videos]}
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
            {gettext("THE SPARK")}
          </div>

          <p class="text-2xl sm:text-3xl text-white leading-relaxed max-w-3xl mx-auto mb-8">
            <.hl
              text={gettext("Technology promised connection and delivered **performance**.")}
              color="gray"
            />
            {gettext("We scroll, we perform, we feel more alone.")}
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
            title={gettext("Click for more examples")}
          >
            <p class="leading-relaxed">
              {gettext("What if you could")}
              <%= for {{verb, color, rest}, index} <- Enum.with_index(visible_use_cases(@use_cases, @current_offset, @visible_count)) do %>
                <span class={"text-#{color}-400 font-medium"}>{verb}</span>
                {rest}{if index < @visible_count - 1, do: "? ", else: "?"}
              <% end %>
            </p>
            <div class="flex items-center justify-center gap-2 mt-3 text-sm text-gray-500 group-hover:text-gray-400 transition-colors">
              <.icon name="hero-arrow-path" class="h-4 w-4" />
              <span>{gettext("Click for more examples")}</span>
            </div>
          </div>

          <%!-- Slider for visible count --%>
          <form
            phx-change="set_visible_count"
            phx-target={@myself}
            class="flex items-center justify-center gap-4 mb-8"
          >
            <label class="text-sm text-gray-500">{gettext("Show")}</label>
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

          <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 max-w-2xl mx-auto mb-8">
            <p class="text-lg text-gray-300 italic">
              {gettext(
                "\"Connection becomes tangible when you can feel someone's presence—their heartbeat, their calm, their stress—in real-time.\""
              )}
            </p>
          </div>

          <%!-- Teaser slice carousel --%>
          <div
            class="relative overflow-hidden rounded-lg border border-gray-700/30 group cursor-pointer"
            phx-click="carousel_next"
            phx-target={@myself}
          >
            <%= for i <- 0..4 do %>
              <div class={[
                "w-full transition-all duration-700 ease-in-out",
                if(i == @carousel_index, do: "block", else: "hidden")
              ]}>
                <picture>
                  <source srcset={"/images/slice_#{i}.webp"} type="image/webp" />
                  <img
                    src={"/images/slice_#{i}.jpg"}
                    alt={"Sensor network detail #{i + 1}"}
                    class="w-full"
                    loading={if i == 0, do: "eager", else: "lazy"}
                    width="2400"
                    height="400"
                  />
                </picture>
              </div>
            <% end %>
            <div class="absolute inset-0 bg-gradient-to-r from-gray-900/40 via-transparent to-gray-900/40 pointer-events-none" />
            <div class="absolute bottom-2 right-3 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <%= for i <- 0..4 do %>
                <div class={[
                  "w-1.5 h-1.5 rounded-full transition-all duration-300",
                  if(i == @carousel_index, do: "bg-cyan-400 w-3", else: "bg-gray-400/50")
                ]} />
              <% end %>
            </div>
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
              {gettext("THE STORY")}
            </div>

            <h2 class="text-2xl font-semibold text-white mb-8 text-center">
              <.hl
                text={gettext("Built for humans who want to **truly** connect")}
                color="blue"
              />
            </h2>

            <div class="grid gap-6 mb-10">
              <%!-- Therapy & Healing --%>
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-green-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-green-500/20 rounded-lg shrink-0">
                    <.icon name="hero-heart" class="h-6 w-6 text-green-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">
                      {gettext("Therapy & Healing")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "Therapists see nervous system dysregulation in real-time. HRV, breathing patterns, heart rate—visible during sessions. Trust forms faster when bodies sync. Healing accelerates with biofeedback."
                      )}
                    </p>
                    <p class="text-green-400 text-sm">
                      {gettext("\"See the nervous system respond before words form.\"")}
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
                      {gettext("Disability Care & Non-Verbal Communication")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "For those who cannot speak their needs—non-verbal individuals, wheelchair users, those with chronic conditions—physiological signals become their voice. Caregivers sense when someone needs help before they ask."
                      )}
                    </p>
                    <p class="text-blue-400 text-sm">
                      {gettext("\"Dignity and agency restored through embodied communication.\"")}
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
                      {gettext("Mental Health & Trusted Networks")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "Peer support networks are reactive—friends don't know someone's in crisis until it's too late. With shared physiology, trusted contacts see rising stress patterns and can reach out proactively."
                      )}
                    </p>
                    <p class="text-purple-400 text-sm">
                      {gettext("\"Prevention over crisis. Community as safety net.\"")}
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
                    <h3 class="text-lg font-semibold text-white mb-2">
                      {gettext("Intimacy & Real Connection")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "Real arousal, real connection. Digital lovers, musicians and audiences, actors and viewers, interviewers and guests, sensual caregivers—anyone sharing intimate moments across distance can finally feel each other's presence."
                      )}
                    </p>
                    <p class="text-pink-400 text-sm">
                      {gettext("\"Presence you can feel, not just see.\"")}
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
                      {gettext("Groups & Collective Presence")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "Teams feel collective calm or tension. Meditation groups verify synchronization. Performers read live audience engagement. Rituals become measurable. Groups self-regulate as organisms."
                      )}
                    </p>
                    <p class="text-cyan-400 text-sm">
                      {gettext("\"Emergent collective intelligence through shared physiology.\"")}
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
                      {gettext("Environmental Monitoring")}
                    </h3>
                    <p class="text-gray-400 mb-3">
                      {gettext(
                        "Coral reef restoration with edge AI cameras detecting fish species and health metrics. Environmental sensors tracking water quality, temperature, and ecosystem vitals. Real-time telemetry from remote locations."
                      )}
                    </p>
                    <p class="text-emerald-400 text-sm">
                      {gettext("\"From coral reefs to urban gardens—sensing what matters.\"")}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Sensor Network Carousel --%>
            <div
              class="mb-10 rounded-xl overflow-hidden border border-gray-700/50 relative group"
              phx-window-keydown="carousel_keydown"
              phx-target={@myself}
            >
              <div class="relative overflow-hidden">
                <%= for i <- 0..4 do %>
                  <div class={[
                    "w-full transition-all duration-500 ease-in-out",
                    if(i == @carousel_index, do: "block", else: "hidden")
                  ]}>
                    <picture>
                      <source srcset={"/images/graph_#{i}.webp"} type="image/webp" />
                      <img
                        src={"/images/graph_#{i}.jpg"}
                        alt={"Sensocto sensor network visualization #{i + 1}"}
                        class="w-full"
                        loading={if i == 0, do: "eager", else: "lazy"}
                        width="2400"
                        height="1862"
                      />
                    </picture>
                  </div>
                <% end %>
              </div>
              <%!-- Navigation arrows --%>
              <button
                phx-click="carousel_prev"
                phx-target={@myself}
                class="absolute left-3 top-1/2 -translate-y-1/2 bg-black/50 hover:bg-black/70 text-white rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <.icon name="hero-chevron-left" class="h-5 w-5" />
              </button>
              <button
                phx-click="carousel_next"
                phx-target={@myself}
                class="absolute right-3 top-1/2 -translate-y-1/2 bg-black/50 hover:bg-black/70 text-white rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <.icon name="hero-chevron-right" class="h-5 w-5" />
              </button>
              <%!-- Dot indicators + caption --%>
              <div class="bg-gray-800/80 px-4 py-3 flex items-center justify-between">
                <p class="text-sm text-gray-400">
                  {gettext(
                    "A live sensor network — each node is a person, each connection a shared signal."
                  )}
                </p>
                <div class="flex gap-1.5">
                  <%= for i <- 0..4 do %>
                    <button
                      phx-click="carousel_goto"
                      phx-value-index={i}
                      phx-target={@myself}
                      class={[
                        "w-2 h-2 rounded-full transition-all duration-300",
                        if(i == @carousel_index,
                          do: "bg-cyan-400 w-4",
                          else: "bg-gray-500 hover:bg-gray-400"
                        )
                      ]}
                    />
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- The Promise --%>
            <div class="bg-gradient-to-r from-cyan-900/20 via-blue-900/20 to-purple-900/20 rounded-xl p-8 border border-gray-700/50 text-center">
              <h3 class="text-xl font-semibold text-white mb-4">{gettext("The Promise")}</h3>
              <p class="text-lg text-gray-300 max-w-2xl mx-auto">
                <.hl
                  text={gettext("Connection measured in **heartbeats**, not dopamine hits.")}
                  color="red"
                />{" "}
                <.hl
                  text={
                    gettext("Technology that **amplifies empathy** instead of exploiting attention.")
                  }
                  color="cyan"
                />{" "}
                {gettext("No harvesting. No surveillance. No algorithms deciding who sees what.")}
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
              {gettext("THE DEEP DIVE")}
            </div>

            <h2 class="text-2xl font-semibold text-white mb-4 text-center">
              <.hl
                text={gettext("Every technical decision is a **moral statement**")}
                color="purple"
              />
            </h2>

            <p class="text-gray-400 text-center mb-8 max-w-2xl mx-auto">
              {gettext(
                "Architecture shapes incentives. We built Sensocto so that privacy and human dignity are structural guarantees, not policy promises."
              )}
            </p>

            <%!-- P2P as Foundation --%>
            <div class="mb-8">
              <h3 class="text-xl font-semibold text-white mb-4">{gettext("Why Peer-to-Peer?")}</h3>
              <div class="grid sm:grid-cols-2 gap-4">
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">
                    {gettext("Centralized Problem")}
                  </div>
                  <div class="text-gray-400 text-sm">
                    {gettext("Server costs create monetization pressure")}
                  </div>
                  <div class="mt-2 text-green-400 text-sm font-medium">{gettext("P2P Solution")}</div>
                  <div class="text-gray-300 text-sm">
                    {gettext("Near-zero marginal cost. No need to harvest data.")}
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">
                    {gettext("Centralized Problem")}
                  </div>
                  <div class="text-gray-400 text-sm">
                    {gettext("Data harvesting for ad targeting")}
                  </div>
                  <div class="mt-2 text-green-400 text-sm font-medium">{gettext("P2P Solution")}</div>
                  <div class="text-gray-300 text-sm">
                    {gettext("Data stays on your devices. Privacy by structure.")}
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">
                    {gettext("Centralized Problem")}
                  </div>
                  <div class="text-gray-400 text-sm">
                    {gettext("Deplatforming and censorship risk")}
                  </div>
                  <div class="mt-2 text-green-400 text-sm font-medium">{gettext("P2P Solution")}</div>
                  <div class="text-gray-300 text-sm">
                    {gettext("No central authority. Communities cannot be silenced.")}
                  </div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                  <div class="text-red-400 text-sm font-medium mb-2">
                    {gettext("Centralized Problem")}
                  </div>
                  <div class="text-gray-400 text-sm">{gettext("Surveillance by design")}</div>
                  <div class="mt-2 text-green-400 text-sm font-medium">{gettext("P2P Solution")}</div>
                  <div class="text-gray-300 text-sm">
                    {gettext("End-to-end encryption native. Intimate data protected.")}
                  </div>
                </div>
              </div>
            </div>

            <%!-- Biomimetic Intelligence --%>
            <div class="mb-8">
              <h3 class="text-xl font-semibold text-white mb-4">
                {gettext("Biomimetic Intelligence")}
              </h3>
              <p class="text-gray-400 mb-4">
                {gettext(
                  "Beneath the surface, Sensocto operates like a living organism—adapting, learning, self-regulating."
                )}
              </p>
              <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3 text-sm">
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-yellow-400 font-medium">{gettext("Novelty Detection")}</div>
                  <div class="text-gray-500">{gettext("Alertness to anomalous data")}</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-blue-400 font-medium">{gettext("Predictive Load Balancing")}</div>
                  <div class="text-gray-500">{gettext("Anticipates demand spikes")}</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-green-400 font-medium">{gettext("Homeostatic Tuning")}</div>
                  <div class="text-gray-500">{gettext("Self-adapting thresholds")}</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-purple-400 font-medium">{gettext("Attention-Aware Batching")}</div>
                  <div class="text-gray-500">{gettext("Respects user focus")}</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-cyan-400 font-medium">{gettext("Circadian Scheduling")}</div>
                  <div class="text-gray-500">{gettext("Daily pattern learning")}</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="text-pink-400 font-medium">{gettext("Resource Arbitration")}</div>
                  <div class="text-gray-500">{gettext("Competitive allocation")}</div>
                </div>
              </div>
            </div>

            <%!-- Open Source Note --%>
            <div class="text-center text-gray-500 text-sm">
              <p>
                {gettext("Built with")} <span class="text-red-400">♥</span>{" "}
                {gettext("for humans who believe technology should serve connection, not extraction.")}
              </p>
            </div>
          </div>
        </div>

        <%!-- Research Tab Section --%>
        <div :if={@detail_level == :research} class="order-1">
          <div class="inline-block px-3 py-1 bg-amber-500/20 text-amber-400 rounded-full text-xs font-medium mb-6">
            {gettext("RESEARCH")}
          </div>

          <h2 class="text-2xl font-semibold text-white mb-4 text-center">
            <.hl
              text={gettext("Scientific **foundations** for human connection")}
              color="amber"
            />
          </h2>

          <p class="text-gray-400 text-center mb-8 max-w-2xl mx-auto">
            {gettext(
              "Our approach is grounded in peer-reviewed research on physiological synchronization, care networks, and wearable technology for mental health."
            )}
          </p>

          <%!-- Brain Connectivity Visualization --%>
          <div class="mb-10 grid grid-cols-1 md:grid-cols-2 gap-4">
            <a
              href="https://www.frontiersin.org/journals/integrative-neuroscience/articles/10.3389/fnint.2020.00003/full"
              target="_blank"
              rel="noopener noreferrer"
              class="rounded-xl overflow-hidden border border-gray-700/50 block hover:border-purple-500/50 transition-colors"
            >
              <picture>
                <source srcset={~p"/images/brain_rois.webp"} type="image/webp" />
                <img
                  src={~p"/images/brain_rois.jpg"}
                  alt="Empathy brain networks: Resonance Network (34 ROIs) and Control Network (22 ROIs)"
                  class="w-full"
                  loading="lazy"
                  width="949"
                  height="1265"
                />
              </picture>
              <div class="bg-gray-800/80 px-3 py-2">
                <p class="text-xs text-gray-400">
                  {gettext("Empathy Resonance & Control Networks")}
                </p>
                <p class="text-[10px] text-gray-500">
                  Morelli &amp; Lieberman, 2020 (CC BY 4.0)
                </p>
              </div>
            </a>
            <a
              href="https://arxiv.org/html/2403.07089v1"
              target="_blank"
              rel="noopener noreferrer"
              class="rounded-xl overflow-hidden border border-gray-700/50 block hover:border-purple-500/50 transition-colors"
            >
              <picture>
                <source srcset={~p"/images/brain_connectome.webp"} type="image/webp" />
                <img
                  src={~p"/images/brain_connectome.jpg"}
                  alt="Brain connectome graph showing empathy-related connectivity between Insula, Amygdala, ACC and other regions"
                  class="w-full"
                  loading="lazy"
                  width="1200"
                  height="1318"
                />
              </picture>
              <div class="bg-gray-800/80 px-3 py-2">
                <p class="text-xs text-gray-400">
                  {gettext("Empathy Connectome: Insula, Amygdala, ACC")}
                </p>
                <p class="text-[10px] text-gray-500">
                  Vijayakumar et al., 2024 (arXiv, CC BY 4.0)
                </p>
              </div>
            </a>
          </div>

          <%!-- Research Summary with depth levels --%>
          <div class="mb-8 bg-gradient-to-br from-amber-900/20 via-gray-800/50 to-purple-900/20 rounded-xl p-6 border border-amber-500/20">
            <div class="flex flex-wrap items-center justify-between gap-4 mb-4">
              <h4 class="text-lg font-medium text-white">
                <.icon name="hero-document-text" class="h-5 w-5 inline-block mr-2 text-amber-400" />
                {gettext("Research Synthesis")}
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
                  {gettext("Brief (~300 words)")}
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
                  {gettext("Standard (~900 words)")}
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
                  {gettext("Deep Dive (~1800 words)")}
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

          <%!-- Papers list with section dividers --%>
          <% {recent, foundational} =
            Enum.split_with(@research_papers, fn p -> p.year >= 2024 end) %>

          <div :if={recent != []} class="mb-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="inline-block px-2.5 py-1 bg-amber-500/20 text-amber-400 rounded-full text-xs font-medium">
                {gettext("Recent Research (2024-2025)")}
              </div>
              <div class="flex-1 border-t border-gray-700/50"></div>
            </div>
            <div class="space-y-4">
              <%= for paper <- recent do %>
                <.research_paper_card paper={paper} paper_categories={@paper_categories} />
              <% end %>
            </div>
          </div>

          <div :if={foundational != []} class="mb-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="inline-block px-2.5 py-1 bg-gray-600/30 text-gray-400 rounded-full text-xs font-medium">
                {gettext("Foundational Research (2001-2018)")}
              </div>
              <div class="flex-1 border-t border-gray-700/50"></div>
            </div>
            <div class="space-y-4">
              <%= for paper <- foundational do %>
                <.research_paper_card paper={paper} paper_categories={@paper_categories} />
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Videos Tab --%>
        <div :if={@detail_level == :videos} class="order-1">
          <div class="inline-block px-3 py-1 bg-rose-500/20 text-rose-400 rounded-full text-sm font-medium mb-4">
            {gettext("VIDEOS")}
          </div>
          <h2 class="text-3xl font-bold text-white mb-3">
            {gettext("Recordings of Unique Human Experiences")}
          </h2>
          <p class="text-gray-400 mb-8 max-w-2xl">
            {gettext(
              "Real sensor recordings capturing fascinating moments of human physiology. Each video tells a story through data."
            )}
          </p>

          <div class="space-y-8">
            <%!-- Graph Demo Recording --%>
            <div class="bg-gradient-to-br from-gray-800/80 to-gray-900/80 rounded-xl border border-gray-700/50 overflow-hidden">
              <div class="aspect-video relative">
                <video
                  :if={!@show_full_video}
                  id="video-graph-clip"
                  autoplay
                  muted
                  loop
                  playsinline
                  class="w-full h-full object-cover"
                >
                  <source src={~p"/videos/sensocto-graph-clip.mp4"} type="video/mp4" />
                  <source src={~p"/videos/sensocto-graph-clip.webm"} type="video/webm" />
                </video>
                <video
                  :if={@show_full_video}
                  id="video-graph-full"
                  controls
                  playsinline
                  class="w-full h-full object-cover"
                >
                  <source src={~p"/videos/sensocto-graph.mp4"} type="video/mp4" />
                  <source src={~p"/videos/sensocto-graph.webm"} type="video/webm" />
                </video>
              </div>
              <div class="p-5">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-1">
                      {gettext("Multi-Sensor Graph Visualization")}
                    </h3>
                    <p class="text-gray-400 text-sm">
                      {gettext(
                        "Real-time heart rate, breathing, and gaze data rendered as an interactive force-directed graph. Watch how physiological signals create living, breathing patterns."
                      )}
                    </p>
                  </div>
                  <button
                    phx-click="toggle_full_video"
                    phx-target={@myself}
                    class={"shrink-0 px-4 py-2 rounded-lg text-sm font-medium transition-all " <>
                      if @show_full_video do
                        "bg-rose-500 text-white hover:bg-rose-400"
                      else
                        "bg-gray-700 text-gray-300 hover:bg-gray-600 hover:text-white"
                      end}
                  >
                    <%= if @show_full_video do %>
                      <.icon name="hero-stop" class="h-4 w-4 inline-block mr-1" />
                      {gettext("Show Clip")}
                    <% else %>
                      <.icon name="hero-play" class="h-4 w-4 inline-block mr-1" />
                      {gettext("Watch Full Recording")}
                    <% end %>
                  </button>
                </div>
                <div class="flex items-center gap-3 mt-3">
                  <span class="px-2 py-0.5 bg-rose-500/20 text-rose-400 rounded text-xs">
                    {gettext("Heart Rate")}
                  </span>
                  <span class="px-2 py-0.5 bg-cyan-500/20 text-cyan-400 rounded text-xs">
                    {gettext("Breathing")}
                  </span>
                  <span class="px-2 py-0.5 bg-purple-500/20 text-purple-400 rounded text-xs">
                    {gettext("Gaze")}
                  </span>
                  <span class="text-gray-500 text-xs ml-auto">{gettext("31 seconds")}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Footer CTA (optional, controlled by show_cta prop) --%>
        <div :if={Map.get(assigns, :show_cta, true)} class="mt-12 text-center order-last">
          <.link
            navigate={~p"/sign-in"}
            class="inline-flex items-center gap-2 px-6 py-3 bg-cyan-600 hover:bg-cyan-500 text-white font-medium rounded-lg transition-colors"
          >
            <.icon name="hero-play" class="h-5 w-5" /> {gettext("Get Started")}
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
