<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
  import EdgeCurveProgram from "@sigma/edge-curve";
  import forceAtlas2 from "graphology-layout-forceatlas2";
  import FA2Layout from "graphology-layout-forceatlas2/worker";

  interface UserData {
    id: string;
    display_name: string;
    email: string;
    bio: string | null;
    status_emoji: string | null;
    skills: Array<{ skill_name: string; level: string }>;
  }

  interface Connection {
    id: string;
    from_user_id: string;
    to_user_id: string;
    connection_type: string;
    strength: number;
  }

  interface Props {
    users?: UserData[];
    connections?: Connection[];
  }

  let {
    users = [],
    connections = [],
  }: Props = $props();

  let container: HTMLDivElement;
  let graph: Graph;
  let sigma: Sigma | null = null;
  let hoveredNode = $state<string | null>(null);
  let hoverDetails = $state<any>(null);
  let mouseX = $state(0);
  let mouseY = $state(0);
  let fa2Worker: FA2Layout | null = null;
  let highlightedNodes = $state(new Set<string>());

  const connectionColors: Record<string, string> = {
    follows: "#3b82f6",
    collaborates: "#22c55e",
    mentors: "#a855f7",
  };

  const connectionLabels: Record<string, string> = {
    follows: "follows",
    collaborates: "collaborates with",
    mentors: "mentors",
  };

  const skillColors: Record<string, string> = {
    elixir: "#6366f1",
    phoenix: "#f97316",
    svelte: "#ef4444",
    rust: "#d97706",
    python: "#3b82f6",
    iot: "#10b981",
    webmidi: "#ec4899",
    neuroscience: "#8b5cf6",
    ux: "#f43f5e",
    devops: "#6b7280",
    "signal-processing": "#14b8a6",
    "machine-learning": "#7c3aed",
    "breathing-science": "#06b6d4",
    biomechanics: "#84cc16",
    "creative-coding": "#e879f9",
  };

  function getSkillColor(skill: string): string {
    return skillColors[skill] || "#6b7280";
  }

  function buildGraph() {
    graph = new Graph();

    const userConnectionCount = new Map<string, number>();
    for (const conn of connections) {
      userConnectionCount.set(conn.from_user_id, (userConnectionCount.get(conn.from_user_id) || 0) + 1);
      userConnectionCount.set(conn.to_user_id, (userConnectionCount.get(conn.to_user_id) || 0) + 1);
    }

    for (const user of users) {
      const connCount = userConnectionCount.get(user.id) || 0;
      const size = 12 + Math.min(connCount * 2, 16);

      graph.addNode(`user:${user.id}`, {
        label: user.display_name || user.email.split("@")[0],
        size,
        color: "#e5e7eb",
        nodeType: "user",
        data: user,
        x: Math.random() * 100,
        y: Math.random() * 100,
      });
    }

    const allSkills = new Set<string>();
    for (const user of users) {
      for (const skill of user.skills || []) {
        allSkills.add(skill.skill_name);
      }
    }

    for (const skillName of allSkills) {
      const usersWithSkill = users.filter(u =>
        (u.skills || []).some(s => s.skill_name === skillName)
      ).length;

      graph.addNode(`skill:${skillName}`, {
        label: skillName,
        size: 5 + Math.min(usersWithSkill * 1.5, 8),
        color: getSkillColor(skillName),
        nodeType: "skill",
        data: { skill_name: skillName, user_count: usersWithSkill },
        x: Math.random() * 100,
        y: Math.random() * 100,
      });
    }

    for (const conn of connections) {
      const fromId = `user:${conn.from_user_id}`;
      const toId = `user:${conn.to_user_id}`;
      if (graph.hasNode(fromId) && graph.hasNode(toId)) {
        const edgeId = `conn:${conn.id}`;
        if (!graph.hasEdge(edgeId)) {
          graph.addEdgeWithKey(edgeId, fromId, toId, {
            size: 0.5 + conn.strength * 0.15,
            color: connectionColors[conn.connection_type] || "#6b7280",
            curvature: 0.15 + Math.random() * 0.1,
            type: "curved",
            connectionType: conn.connection_type,
          });
        }
      }
    }

    for (const user of users) {
      for (const skill of user.skills || []) {
        const userId = `user:${user.id}`;
        const skillId = `skill:${skill.skill_name}`;
        if (graph.hasNode(userId) && graph.hasNode(skillId)) {
          graph.addEdge(userId, skillId, {
            size: 0.3,
            color: "rgba(75, 85, 99, 0.2)",
            curvature: 0.1 + Math.random() * 0.15,
            type: "curved",
          });
        }
      }
    }
  }

  function initSigma() {
    if (!container || !graph) return;

    sigma = new Sigma(graph, container, {
      renderLabels: true,
      labelRenderedSizeThreshold: 6,
      labelFont: "Inter, system-ui, sans-serif",
      labelSize: 13,
      labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      defaultNodeColor: "#6b7280",
      defaultEdgeColor: "rgba(55, 65, 81, 0.3)",
      defaultEdgeType: "curved",
      edgeProgramClasses: {
        curved: EdgeCurveProgram,
      },
      allowInvalidContainer: true,
      minCameraRatio: 0.1,
      maxCameraRatio: 10,
      nodeReducer: (node, data) => {
        if (highlightedNodes.size === 0) return data;
        if (highlightedNodes.has(node)) return { ...data, zIndex: 1 };
        return { ...data, color: "rgba(45, 55, 72, 0.3)", zIndex: 0 };
      },
      edgeReducer: (_edge, data) => {
        if (highlightedNodes.size === 0) return data;
        return { ...data, color: "rgba(45, 55, 72, 0.15)" };
      },
    });

    sigma.on("enterNode", ({ node }) => {
      hoveredNode = node;
      const attrs = graph.getNodeAttributes(node);
      hoverDetails = attrs;

      const neighbors = new Set<string>([node]);
      graph.forEachNeighbor(node, (neighbor) => neighbors.add(neighbor));
      highlightedNodes = neighbors;
      sigma?.refresh();
    });

    sigma.on("leaveNode", () => {
      hoveredNode = null;
      hoverDetails = null;
      highlightedNodes = new Set();
      sigma?.refresh();
    });

    sigma.on("clickNode", ({ node }) => {
      const attrs = graph.getNodeAttributes(node);
      if (attrs.nodeType === "user" && attrs.data?.id) {
        window.location.href = `/users/${attrs.data.id}`;
      }
    });

    sigma.getMouseCaptor().on("mousemove", (e: any) => {
      mouseX = e.original?.clientX ?? e.x;
      mouseY = e.original?.clientY ?? e.y;
    });
  }

  function runLayout() {
    if (!graph || graph.order === 0) return;

    forceAtlas2.assign(graph, {
      iterations: 100,
      settings: {
        gravity: 1,
        scalingRatio: 8,
        strongGravityMode: false,
        barnesHutOptimize: true,
        barnesHutTheta: 0.5,
        slowDown: 5,
      },
    });
  }

  function startFA2() {
    if (!graph || graph.order === 0) return;
    stopFA2();

    fa2Worker = new FA2Layout(graph, {
      settings: {
        gravity: 1.5,
        scalingRatio: 10,
        strongGravityMode: false,
        barnesHutOptimize: true,
        barnesHutTheta: 0.5,
        slowDown: 3,
      },
    });
    fa2Worker.start();

    setTimeout(() => stopFA2(), 4000);
  }

  function stopFA2() {
    if (fa2Worker) {
      fa2Worker.stop();
      fa2Worker.kill();
      fa2Worker = null;
    }
  }

  onMount(() => {
    if (users.length === 0) return;
    buildGraph();
    initSigma();
    runLayout();
    startFA2();
  });

  onDestroy(() => {
    stopFA2();
    if (sigma) {
      sigma.kill();
      sigma = null;
    }
  });
</script>

<div class="relative w-full h-full bg-gray-950 rounded-lg overflow-hidden">
  <div bind:this={container} class="w-full h-full"></div>

  <!-- Legend -->
  <div class="absolute top-3 right-3 bg-gray-900/90 backdrop-blur-sm rounded-lg p-3 text-xs space-y-1.5">
    <div class="text-gray-400 font-medium mb-1">Connections</div>
    <div class="flex items-center gap-2">
      <span class="w-3 h-0.5 rounded" style="background: #3b82f6"></span>
      <span class="text-gray-300">follows</span>
    </div>
    <div class="flex items-center gap-2">
      <span class="w-3 h-0.5 rounded" style="background: #22c55e"></span>
      <span class="text-gray-300">collaborates</span>
    </div>
    <div class="flex items-center gap-2">
      <span class="w-3 h-0.5 rounded" style="background: #a855f7"></span>
      <span class="text-gray-300">mentors</span>
    </div>
    <div class="text-gray-400 font-medium mt-2 mb-1">Nodes</div>
    <div class="flex items-center gap-2">
      <span class="w-2.5 h-2.5 rounded-full bg-gray-200"></span>
      <span class="text-gray-300">user</span>
    </div>
    <div class="flex items-center gap-2">
      <span class="w-2 h-2 rounded-full bg-indigo-500"></span>
      <span class="text-gray-300">skill</span>
    </div>
  </div>

  <!-- Hover tooltip -->
  {#if hoveredNode && hoverDetails}
    <div
      class="fixed z-50 bg-gray-900/95 backdrop-blur-sm text-white rounded-lg shadow-xl p-3 pointer-events-none max-w-64"
      style="left: {mouseX + 12}px; top: {mouseY - 12}px;"
    >
      {#if hoverDetails.nodeType === "user"}
        <div class="flex items-center gap-2 mb-1">
          {#if hoverDetails.data?.status_emoji}
            <span class="text-lg">{hoverDetails.data.status_emoji}</span>
          {/if}
          <span class="font-medium">{hoverDetails.label}</span>
        </div>
        {#if hoverDetails.data?.bio}
          <p class="text-xs text-gray-400 mb-1">{hoverDetails.data.bio}</p>
        {/if}
        {#if hoverDetails.data?.skills?.length}
          <div class="flex flex-wrap gap-1 mt-1">
            {#each hoverDetails.data.skills as skill}
              <span
                class="text-[10px] px-1.5 py-0.5 rounded-full"
                style="background: {getSkillColor(skill.skill_name)}33; color: {getSkillColor(skill.skill_name)}"
              >
                {skill.skill_name}
              </span>
            {/each}
          </div>
        {/if}
        <p class="text-[10px] text-gray-500 mt-1">Click to view profile</p>
      {:else if hoverDetails.nodeType === "skill"}
        <div class="flex items-center gap-2">
          <span
            class="w-2.5 h-2.5 rounded-full"
            style="background: {getSkillColor(hoverDetails.data?.skill_name)}"
          ></span>
          <span class="font-medium">{hoverDetails.label}</span>
        </div>
        <p class="text-xs text-gray-400">{hoverDetails.data?.user_count} user(s)</p>
      {/if}
    </div>
  {/if}

  <!-- Empty state -->
  {#if users.length === 0}
    <div class="absolute inset-0 flex items-center justify-center">
      <p class="text-gray-500">No users to display</p>
    </div>
  {/if}
</div>
