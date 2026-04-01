<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";
  import * as d3 from "d3";
  import Graph from "graphology";
  import Sigma from "sigma";
  import forceAtlas2 from "graphology-layout-forceatlas2";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; value: number }>;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  const COLORS = [
    '#ef4444', // Red
    '#f97316', // Orange
    '#eab308', // Yellow
    '#22c55e', // Green
    '#06b6d4', // Cyan
    '#3b82f6', // Blue
    '#8b5cf6', // Violet
    '#ec4899', // Pink
    '#14b8a6', // Teal
    '#f59e0b', // Amber
    '#6366f1', // Indigo
    '#10b981', // Emerald
    '#f43f5e', // Rose
    '#0ea5e9', // Sky
    '#a855f7', // Purple
    '#84cc16', // Lime
    '#e879f9', // Fuchsia
    '#fb923c', // Light orange
    '#2dd4bf', // Light teal
    '#818cf8'  // Light indigo
  ];

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 100;
  const PHASE_BUFFER_SIZE = 20; // HRV data at ~0.2Hz, 20 samples = ~100s of context

  const TIME_WINDOWS = [
    { label: '30s', ms: 30 * 1000 },
    { label: '1min', ms: 60 * 1000 },
    { label: '5min', ms: 5 * 60 * 1000 }
  ];

  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);
  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();
  let sensorNames: Map<string, string> = new Map();
  let pendingUpdates: Map<string, Array<{ x: number; y: number }>> = new Map();
  let rafId: number | null = null;
  let lastUpdateTime = 0;
  let lastExtremesUpdate = 0;
  let lastTrimTime = 0;
  let lastSyncCompute = 0;
  let dirtySeriesIds: Set<string> = new Set();
  let syncDirty = false;

  // HRV stress state counts - updated imperatively in the RAF loop
  let latestValues: Map<string, number> = new Map();
  let stressedCount = $state(0);
  let moderateCount = $state(0);
  let relaxedCount = $state(0);
  let groupMeanRmssd = $state(0);

  // Phase synchronization (Kuramoto order parameter)
  let phaseBuffers: Map<string, number[]> = new Map();
  let phaseSync = $state(0);
  let smoothedSync = 0;

  // Sync history for chart visualization
  let syncHistory: Array<{ x: number; y: number }> = [];
  const SYNC_SERIES_NAME = 'Phase Sync';

  // Pairwise synchronization heatmap
  let viewMode = $state<'chart' | 'heatmap' | 'tree' | 'graph'>('chart');
  let pairwiseSyncMatrix: Map<string, number> = new Map(); // "sensorA|sensorB" -> smoothed PLV [0,1]
  let heatmapSensorIds = $state<string[]>([]);
  let heatmapData = $state<number[][]>([]);
  const PAIRWISE_SMOOTHING = 0.8; // higher = smoother (slower to react)

  function updateHrvStates() {
    let stressed = 0, moderate = 0, relaxed = 0;
    let sum = 0, count = 0;

    latestValues.forEach((value) => {
      if (value < 20) stressed++;
      else if (value <= 50) moderate++;
      else relaxed++;
      sum += value;
      count++;
    });

    stressedCount = stressed;
    moderateCount = moderate;
    relaxedCount = relaxed;
    groupMeanRmssd = count > 0 ? Math.round(sum / count) : 0;
  }

  function addToPhaseBuffer(sensorId: string, value: number) {
    let buffer = phaseBuffers.get(sensorId);
    if (!buffer) {
      buffer = [];
      phaseBuffers.set(sensorId, buffer);
    }
    buffer.push(value);
    if (buffer.length > PHASE_BUFFER_SIZE) {
      buffer.splice(0, buffer.length - PHASE_BUFFER_SIZE);
    }
  }

  // Estimate instantaneous HRV phase for each sensor,
  // then compute the Kuramoto order parameter R = |mean(e^(i*theta))|.
  // R ranges from 0 (random phases) to 1 (perfect synchrony).
  // Being a circular mean, a few outliers only moderately reduce R.
  function computePhaseSync() {
    const phases: number[] = [];

    phaseBuffers.forEach((buffer) => {
      if (buffer.length < 8) return;

      const n = buffer.length;
      let min = buffer[0], max = buffer[0];
      for (let i = 1; i < n; i++) {
        if (buffer[i] < min) min = buffer[i];
        if (buffer[i] > max) max = buffer[i];
      }
      const range = max - min;
      if (range < 2) return;

      const current = buffer[n - 1];
      const norm = Math.max(0, Math.min(1, (current - min) / range));

      // Derivative from last 5 samples for stable sign estimation
      const lookback = Math.min(5, n - 1);
      const derivative = buffer[n - 1] - buffer[n - 1 - lookback];
      const rising = derivative >= 0;

      // Map normalized value + direction to phase angle [0, 2pi]
      // Rising:  min->max maps to 0->pi
      // Falling: max->min maps to pi->2pi
      const baseAngle = Math.acos(1 - 2 * norm);
      const phase = rising ? baseAngle : (2 * Math.PI - baseAngle);
      phases.push(phase);
    });

    if (phases.length < 2) return;

    // Kuramoto order parameter
    let sumCos = 0, sumSin = 0;
    for (const theta of phases) {
      sumCos += Math.cos(theta);
      sumSin += Math.sin(theta);
    }
    const R = Math.sqrt(
      (sumCos / phases.length) ** 2 +
      (sumSin / phases.length) ** 2
    );

    // Exponential moving average for smooth display
    smoothedSync = smoothedSync === 0 ? R : 0.85 * smoothedSync + 0.15 * R;
    phaseSync = Math.round(smoothedSync * 100);

    // Record to history
    syncHistory.push({ x: Date.now(), y: phaseSync });
    if (syncHistory.length > MAX_DATA_POINTS) {
      syncHistory = syncHistory.slice(syncHistory.length - MAX_DATA_POINTS);
    }
    syncDirty = true;
  }

  // Compute pairwise phase locking value (PLV) between all sensor pairs.
  // PLV(i,j) = |cos(θ_i - θ_j)| smoothed over time.
  // Result: updates heatmapSensorIds (sorted) and heatmapData (N×N matrix).
  function computePairwiseSync() {
    if (viewMode !== 'heatmap' && viewMode !== 'tree' && viewMode !== 'graph') return;

    // Collect sensors with valid phases
    const sensorPhases: Array<{ id: string; phase: number }> = [];

    phaseBuffers.forEach((buffer, sensorId) => {
      if (buffer.length < 8) return;

      const n = buffer.length;
      let min = buffer[0], max = buffer[0];
      for (let i = 1; i < n; i++) {
        if (buffer[i] < min) min = buffer[i];
        if (buffer[i] > max) max = buffer[i];
      }
      const range = max - min;
      if (range < 2) return;

      const current = buffer[n - 1];
      const norm = Math.max(0, Math.min(1, (current - min) / range));
      const lookback = Math.min(5, n - 1);
      const derivative = buffer[n - 1] - buffer[n - 1 - lookback];
      const baseAngle = Math.acos(1 - 2 * norm);
      const phase = derivative >= 0 ? baseAngle : (2 * Math.PI - baseAngle);

      sensorPhases.push({ id: sensorId, phase });
    });

    if (sensorPhases.length < 2) return;

    // Sort by sensor ID for stable ordering
    sensorPhases.sort((a, b) => a.id.localeCompare(b.id));

    const ids = sensorPhases.map(s => s.id);
    const n = ids.length;
    const matrix: number[][] = Array.from({ length: n }, () => new Array(n).fill(1));

    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const phaseDiff = sensorPhases[i].phase - sensorPhases[j].phase;
        // PLV for single time point: use cosine similarity of phase difference
        // cos(Δθ) ranges [-1, 1], map to [0, 1]
        const instantPlv = (Math.cos(phaseDiff) + 1) / 2;

        const key = `${ids[i]}|${ids[j]}`;
        const prev = pairwiseSyncMatrix.get(key);
        const smoothed = prev !== undefined
          ? PAIRWISE_SMOOTHING * prev + (1 - PAIRWISE_SMOOTHING) * instantPlv
          : instantPlv;
        pairwiseSyncMatrix.set(key, smoothed);

        matrix[i][j] = smoothed;
        matrix[j][i] = smoothed;
      }
    }

    heatmapSensorIds = ids;
    heatmapData = matrix;
  }

  // ── Tree-based clustered heatmap (dendrogram view) ──────────────────

  let treeSvgEl: SVGSVGElement;
  let treeContainer: HTMLDivElement;
  let treeNeedsRebuild = $state(false);
  let treeCutHeight = $state(0.5); // Draggable cluster cut threshold [0, 1] normalized
  let treeClusterCount = $state(0);
  let focusedCluster = $state<number | null>(null); // Click-to-focus cluster
  interface ClusterSummary {
    id: number;
    color: string;
    members: string[];
    meanPlv: number;
    stressCounts: Record<string, number>;
  }
  let clusterSummaries = $state<ClusterSummary[]>([]);

  interface ClusterNode {
    id: number;
    left: ClusterNode | null;
    right: ClusterNode | null;
    height: number;
    items: number[]; // leaf indices
  }

  function agglomerativeClustering(distMatrix: number[][]): ClusterNode {
    const n = distMatrix.length;
    if (n === 0) return { id: 0, left: null, right: null, height: 0, items: [] };
    if (n === 1) return { id: 0, left: null, right: null, height: 0, items: [0] };

    let clusters: ClusterNode[] = Array.from({ length: n }, (_, i) => ({
      id: i, left: null, right: null, height: 0, items: [i]
    }));

    let nextId = n;
    const active = new Set<number>(Array.from({ length: n }, (_, i) => i));

    while (active.size > 1) {
      let minDist = Infinity, mergeA = -1, mergeB = -1;
      const activeArr = [...active];
      for (let ii = 0; ii < activeArr.length; ii++) {
        for (let jj = ii + 1; jj < activeArr.length; jj++) {
          const a = activeArr[ii], b = activeArr[jj];
          let total = 0, pairCount = 0;
          for (const ai of clusters[a].items) {
            for (const bi of clusters[b].items) {
              total += distMatrix[ai][bi];
              pairCount++;
            }
          }
          const avg = pairCount > 0 ? total / pairCount : 0;
          if (avg < minDist) { minDist = avg; mergeA = a; mergeB = b; }
        }
      }

      const newCluster: ClusterNode = {
        id: nextId++,
        left: clusters[mergeA],
        right: clusters[mergeB],
        height: minDist,
        items: [...clusters[mergeA].items, ...clusters[mergeB].items]
      };
      clusters.push(newCluster);
      active.delete(mergeA);
      active.delete(mergeB);
      active.add(clusters.length - 1);
    }

    return clusters[clusters.length - 1];
  }

  function getLeafOrder(node: ClusterNode): number[] {
    if (!node.left && !node.right) return node.items;
    return [...(node.left ? getLeafOrder(node.left) : []), ...(node.right ? getLeafOrder(node.right) : [])];
  }

  function getClusterCenter(node: ClusterNode, positions: Map<number, number>): number {
    const leaves = getLeafOrder(node);
    const sum = leaves.reduce((s, i) => s + (positions.get(i) || 0), 0);
    return sum / leaves.length;
  }

  // Assign cluster IDs by cutting the dendrogram at a given height
  function cutTree(node: ClusterNode, cutDist: number): Map<number, number> {
    const assignments = new Map<number, number>();
    let nextCluster = 0;

    function walk(n: ClusterNode) {
      if (n.height <= cutDist || (!n.left && !n.right)) {
        const cid = nextCluster++;
        for (const leaf of n.items) assignments.set(leaf, cid);
      } else {
        if (n.left) walk(n.left);
        if (n.right) walk(n.right);
      }
    }
    walk(node);
    return assignments;
  }

  // Cluster palette — distinct hues for up to 10 clusters
  const CLUSTER_COLORS = [
    '#3b82f6', '#f97316', '#22c55e', '#a855f7', '#ef4444',
    '#06b6d4', '#eab308', '#ec4899', '#14b8a6', '#6366f1'
  ];

  interface DendroSeg { x1: number; y1: number; x2: number; y2: number; color: string; }

  function dendrogramSegmentsColored(
    node: ClusterNode,
    positions: Map<number, number>,
    heightScale: (h: number) => number,
    clusterAssignments: Map<number, number>,
    cutDist: number
  ): DendroSeg[] {
    if (!node.left || !node.right) return [];
    const leftC = getClusterCenter(node.left, positions);
    const rightC = getClusterCenter(node.right, positions);
    const mergeY = heightScale(node.height);
    const leftY = node.left.left ? heightScale(node.left.height) : heightScale(0);
    const rightY = node.right.left ? heightScale(node.right.height) : heightScale(0);

    // Color: if this merge is below the cut, use the cluster color; else gray
    function branchColor(child: ClusterNode): string {
      if (child.height > cutDist) return '#4b556366'; // above cut = gray
      const leafClusters = child.items.map(i => clusterAssignments.get(i) ?? 0);
      const cid = leafClusters[0];
      return CLUSTER_COLORS[cid % CLUSTER_COLORS.length];
    }

    const leftColor = branchColor(node.left);
    const rightColor = branchColor(node.right);
    const horizColor = node.height > cutDist ? '#4b556366' : leftColor;

    return [
      { x1: leftC, y1: leftY, x2: leftC, y2: mergeY, color: leftColor },
      { x1: rightC, y1: rightY, x2: rightC, y2: mergeY, color: rightColor },
      { x1: leftC, y1: mergeY, x2: rightC, y2: mergeY, color: horizColor },
      ...dendrogramSegmentsColored(node.left, positions, heightScale, clusterAssignments, cutDist),
      ...dendrogramSegmentsColored(node.right, positions, heightScale, clusterAssignments, cutDist),
    ];
  }

  // Sequential color scale: Plasma (colorblind-safe, perceptually uniform)
  const treeColorScale = d3.scaleSequential(d3.interpolatePlasma).domain([0, 1]);
  const LOW_PLV_THRESHOLD = 0.3; // opacity gating threshold
  const HIGH_PLV_THRESHOLD = 0.8; // pulse animation threshold

  // Get stress category for a sensor
  function getStressCategory(sensorId: string): 'stressed' | 'moderate' | 'relaxed' | 'unknown' {
    const val = latestValues.get(sensorId);
    if (val === undefined) return 'unknown';
    if (val < 20) return 'stressed';
    if (val <= 50) return 'moderate';
    return 'relaxed';
  }

  const STRESS_COLORS: Record<string, string> = {
    stressed: '#ef4444', moderate: '#eab308', relaxed: '#22c55e', unknown: '#374151'
  };

  function renderTreeHeatmap() {
    if (!treeSvgEl || !treeContainer) return;
    if (heatmapSensorIds.length < 2 || heatmapData.length < 2) return;

    const n = heatmapSensorIds.length;
    const syncMatrix = heatmapData;

    // Convert sync matrix (similarity) to distance matrix
    const distMatrix: number[][] = Array.from({ length: n }, (_, i) =>
      Array.from({ length: n }, (_, j) => i === j ? 0 : 1 - (syncMatrix[i]?.[j] ?? 0))
    );

    const tree = agglomerativeClustering(distMatrix);
    const leafOrder = getLeafOrder(tree);
    const orderedIds = leafOrder.map(i => heatmapSensorIds[i]);
    const maxH = tree.height || 1;

    // Cut tree at current threshold
    const cutDist = treeCutHeight * maxH;
    const clusterAssignments = cutTree(tree, cutDist);
    const clusterCount = new Set(clusterAssignments.values()).size;
    treeClusterCount = clusterCount;

    // Compute mean PLV per sensor (for annotation bar)
    const meanPlvs = new Map<number, number>();
    for (let i = 0; i < n; i++) {
      let sum = 0, cnt = 0;
      for (let j = 0; j < n; j++) {
        if (i !== j) { sum += (syncMatrix[i]?.[j] ?? 0); cnt++; }
      }
      meanPlvs.set(i, cnt > 0 ? sum / cnt : 0);
    }

    // ── Build cluster summaries for cards below SVG ──
    const clusterMap = new Map<number, number[]>(); // cid → original indices
    for (const [origIdx, cid] of clusterAssignments) {
      if (!clusterMap.has(cid)) clusterMap.set(cid, []);
      clusterMap.get(cid)!.push(origIdx);
    }
    const summaries: ClusterSummary[] = [];
    for (const [cid, members] of [...clusterMap.entries()].sort((a, b) => a[0] - b[0])) {
      const memberIds = members.map(i => heatmapSensorIds[i]);
      // Mean intra-cluster PLV
      let plvSum = 0, plvCnt = 0;
      for (let i = 0; i < members.length; i++) {
        for (let j = i + 1; j < members.length; j++) {
          plvSum += syncMatrix[members[i]]?.[members[j]] ?? 0;
          plvCnt++;
        }
      }
      const stressCounts: Record<string, number> = { stressed: 0, moderate: 0, relaxed: 0, unknown: 0 };
      for (const id of memberIds) {
        stressCounts[getStressCategory(id)]++;
      }
      summaries.push({
        id: cid,
        color: CLUSTER_COLORS[cid % CLUSTER_COLORS.length],
        members: memberIds,
        meanPlv: plvCnt > 0 ? plvSum / plvCnt : 0,
        stressCounts,
      });
    }
    clusterSummaries = summaries;

    // Layout dimensions — amplified dendrograms
    const DENDRO_H = 70;
    const DENDRO_W = 80;
    const ANNO_W = 36;  // annotation tracks (3 tracks × 10px + gaps)
    const LABEL_W = 80;
    const LABEL_H = 80;
    const GAP = 3;      // gap between cluster blocks
    const containerW = treeContainer.clientWidth - 16;
    const cellSize = Math.max(24, Math.min(48, (containerW - DENDRO_W - ANNO_W - LABEL_W) / n));
    const gridSize = cellSize * n;
    const totalW = DENDRO_W + ANNO_W + gridSize + LABEL_W + 12;
    const totalH = DENDRO_H + LABEL_H + gridSize + 12;

    const svg = d3.select(treeSvgEl)
      .attr('viewBox', `0 0 ${totalW} ${totalH}`)
      .attr('width', null)
      .attr('height', null)
      .style('width', '100%')
      .style('max-height', '100%')
      .style('aspect-ratio', `${totalW} / ${totalH}`);
    svg.selectAll('*').remove();

    const annoX0 = DENDRO_W + 2;
    const gridX0 = DENDRO_W + ANNO_W + 4;
    const gridY0 = DENDRO_H + LABEL_H;

    // ── Hover crosshair group (rendered on top later) ──
    const crosshairG = svg.append('g').attr('class', 'crosshairs').style('pointer-events', 'none');

    // ── Row dendrogram (left side) with cluster coloring ──
    const rowPositions = new Map<number, number>();
    leafOrder.forEach((origIdx, pos) => {
      rowPositions.set(origIdx, gridY0 + pos * cellSize + cellSize / 2);
    });

    const rowHeightScale = (h: number) => DENDRO_W - 4 - (h / maxH) * (DENDRO_W - 8);

    const rowSegs = dendrogramSegmentsColored(tree, rowPositions, rowHeightScale, clusterAssignments, cutDist);
    const rowG = svg.append('g').attr('class', 'row-dendro');
    rowG.selectAll('line').data(rowSegs).join('line')
      .attr('x1', d => d.y1).attr('y1', d => d.x1)
      .attr('x2', d => d.y2).attr('y2', d => d.x2)
      .attr('stroke', d => d.color).attr('stroke-width', 1.8)
      .attr('stroke-linecap', 'round');

    // ── Cluster cut line (row dendrogram) — draggable with bigger handle ──
    const cutX = rowHeightScale(cutDist);
    const cutLineG = svg.append('g').attr('class', 'cut-line');
    cutLineG.append('line')
      .attr('x1', cutX).attr('y1', gridY0 - 2)
      .attr('x2', cutX).attr('y2', gridY0 + gridSize + 2)
      .attr('stroke', '#f97316').attr('stroke-width', 1.5)
      .attr('stroke-dasharray', '6,4')
      .attr('opacity', 0.9);
    // Bigger drag handle with visual affordance
    const handleW = 16, handleH = 14;
    cutLineG.append('rect')
      .attr('x', cutX - handleW / 2).attr('y', gridY0 - handleH - 4)
      .attr('width', handleW).attr('height', handleH)
      .attr('rx', 3)
      .attr('fill', '#f97316').attr('opacity', 0.95)
      .attr('cursor', 'ew-resize')
      .attr('filter', 'drop-shadow(0 1px 2px rgba(0,0,0,0.4))')
      .call(d3.drag<SVGRectElement, unknown>()
        .on('drag', (event) => {
          const newX = Math.max(4, Math.min(DENDRO_W - 4, event.x));
          const newHeight = (DENDRO_W - 4 - newX) / (DENDRO_W - 8);
          treeCutHeight = Math.max(0.05, Math.min(0.95, newHeight));
        })
      );
    // Grip lines on drag handle
    for (let gy = -3; gy <= 3; gy += 3) {
      cutLineG.append('line')
        .attr('x1', cutX - 4).attr('y1', gridY0 - handleH / 2 - 4 + gy)
        .attr('x2', cutX + 4).attr('y2', gridY0 - handleH / 2 - 4 + gy)
        .attr('stroke', 'rgba(0,0,0,0.3)').attr('stroke-width', 1)
        .attr('pointer-events', 'none');
    }
    // Label showing cluster count
    cutLineG.append('text')
      .attr('x', cutX).attr('y', gridY0 - handleH - 8)
      .attr('text-anchor', 'middle')
      .attr('fill', '#f97316').attr('font-size', '9px').attr('font-weight', 'bold').attr('font-family', 'monospace')
      .text(`${clusterCount}`);

    // ── Column dendrogram (top) with cluster coloring ──
    const colPositions = new Map<number, number>();
    leafOrder.forEach((origIdx, pos) => {
      colPositions.set(origIdx, gridX0 + pos * cellSize + cellSize / 2);
    });

    const colHeightScale = (h: number) => DENDRO_H + LABEL_H - 4 - (h / maxH) * (DENDRO_H - 8);

    const colSegs = dendrogramSegmentsColored(tree, colPositions, colHeightScale, clusterAssignments, cutDist);
    const colG = svg.append('g').attr('class', 'col-dendro');
    colG.selectAll('line').data(colSegs).join('line')
      .attr('x1', d => d.x1).attr('y1', d => d.y1)
      .attr('x2', d => d.x2).attr('y2', d => d.y2)
      .attr('stroke', d => d.color).attr('stroke-width', 1.8)
      .attr('stroke-linecap', 'round');

    // Column cut line
    const colCutY = colHeightScale(cutDist);
    cutLineG.append('line')
      .attr('x1', gridX0 - 2).attr('y1', colCutY)
      .attr('x2', gridX0 + gridSize + 2).attr('y2', colCutY)
      .attr('stroke', '#f97316').attr('stroke-width', 1.5)
      .attr('stroke-dasharray', '6,4')
      .attr('opacity', 0.9);

    // ── Annotation sidebars (left of grid) ──
    const annoG = svg.append('g').attr('class', 'annotations');
    const TRACK_W = 10;
    const TRACK_GAP = 1;

    // Track 1: Cluster membership (clickable for focus)
    orderedIds.forEach((id, ri) => {
      const origIdx = leafOrder[ri];
      const cid = clusterAssignments.get(origIdx) ?? 0;
      const isFocused = focusedCluster === null || focusedCluster === cid;
      annoG.append('rect')
        .attr('x', annoX0)
        .attr('y', gridY0 + ri * cellSize + 1)
        .attr('width', TRACK_W)
        .attr('height', cellSize - 2)
        .attr('rx', 1)
        .attr('fill', CLUSTER_COLORS[cid % CLUSTER_COLORS.length])
        .attr('opacity', isFocused ? 0.9 : 0.25)
        .attr('cursor', 'pointer')
        .on('click', () => { focusedCluster = focusedCluster === cid ? null : cid; requestAnimationFrame(() => renderTreeHeatmap()); })
        .append('title').text(`Cluster ${cid + 1} — click to focus`);
    });

    // Track 2: Stress state (RMSSD category)
    orderedIds.forEach((id, ri) => {
      const origIdx = leafOrder[ri];
      const cid = clusterAssignments.get(origIdx) ?? 0;
      const isFocused = focusedCluster === null || focusedCluster === cid;
      const stress = getStressCategory(id);
      annoG.append('rect')
        .attr('x', annoX0 + TRACK_W + TRACK_GAP)
        .attr('y', gridY0 + ri * cellSize + 1)
        .attr('width', TRACK_W)
        .attr('height', cellSize - 2)
        .attr('rx', 1)
        .attr('fill', STRESS_COLORS[stress])
        .attr('opacity', isFocused ? 0.9 : 0.25)
        .append('title').text(`HRV: ${stress} (${Math.round(latestValues.get(id) ?? 0)}ms)`);
    });

    // Track 3: Mean PLV bar
    const maxMeanPlv = Math.max(...[...meanPlvs.values()], 0.01);
    orderedIds.forEach((id, ri) => {
      const origIdx = leafOrder[ri];
      const cid = clusterAssignments.get(origIdx) ?? 0;
      const isFocused = focusedCluster === null || focusedCluster === cid;
      const mean = meanPlvs.get(origIdx) ?? 0;
      const barW = (mean / maxMeanPlv) * TRACK_W;
      annoG.append('rect')
        .attr('x', annoX0 + 2 * (TRACK_W + TRACK_GAP))
        .attr('y', gridY0 + ri * cellSize + 1)
        .attr('width', TRACK_W)
        .attr('height', cellSize - 2)
        .attr('rx', 1)
        .attr('fill', '#1e293b');
      annoG.append('rect')
        .attr('x', annoX0 + 2 * (TRACK_W + TRACK_GAP))
        .attr('y', gridY0 + ri * cellSize + 1)
        .attr('width', Math.max(1, barW))
        .attr('height', cellSize - 2)
        .attr('rx', 1)
        .attr('fill', '#f97316')
        .attr('opacity', isFocused ? 0.7 : 0.15)
        .append('title').text(`Mean PLV: ${Math.round(mean * 100)}%`);
    });

    // Annotation track labels (top)
    const annoLabels = [
      { x: annoX0 + TRACK_W / 2, label: 'C' },
      { x: annoX0 + TRACK_W + TRACK_GAP + TRACK_W / 2, label: 'S' },
      { x: annoX0 + 2 * (TRACK_W + TRACK_GAP) + TRACK_W / 2, label: 'P' },
    ];
    annoLabels.forEach(({ x, label }) => {
      annoG.append('text')
        .attr('x', x).attr('y', gridY0 - 4)
        .attr('text-anchor', 'middle')
        .attr('fill', '#6b7280').attr('font-size', '7px').attr('font-family', 'monospace')
        .text(label);
    });

    // ── Column labels (rotated) ──
    const colLabels = svg.append('g');
    orderedIds.forEach((id, ci) => {
      const origIdx = leafOrder[ci];
      const cid = clusterAssignments.get(origIdx) ?? 0;
      const isFocused = focusedCluster === null || focusedCluster === cid;
      colLabels.append('text')
        .attr('x', gridX0 + ci * cellSize + cellSize / 2)
        .attr('y', gridY0 - 4)
        .attr('text-anchor', 'start')
        .attr('transform', `rotate(-50, ${gridX0 + ci * cellSize + cellSize / 2}, ${gridY0 - 4})`)
        .attr('fill', isFocused ? '#9ca3af' : '#9ca3af44')
        .attr('font-size', '10px')
        .attr('font-family', 'monospace')
        .text(getDisplayName(id));
    });

    // ── Row labels (with cluster color indicator) ──
    const rowLabels = svg.append('g');
    orderedIds.forEach((id, ri) => {
      const origIdx = leafOrder[ri];
      const cid = clusterAssignments.get(origIdx) ?? 0;
      const isFocused = focusedCluster === null || focusedCluster === cid;
      const baseColor = sensorColors.get(id) || '#9ca3af';
      rowLabels.append('text')
        .attr('x', gridX0 + gridSize + 6)
        .attr('y', gridY0 + ri * cellSize + cellSize / 2 + 3)
        .attr('text-anchor', 'start')
        .attr('fill', isFocused ? baseColor : baseColor + '44')
        .attr('font-size', '10px')
        .attr('font-family', 'monospace')
        .text(getDisplayName(id));
    });

    // ── Determine cluster boundaries for gap lines ──
    const clusterBoundaries: number[] = [];
    for (let ri = 1; ri < orderedIds.length; ri++) {
      const prevCluster = clusterAssignments.get(leafOrder[ri - 1]);
      const currCluster = clusterAssignments.get(leafOrder[ri]);
      if (prevCluster !== currCluster) clusterBoundaries.push(ri);
    }

    // ── Heatmap cells with opacity gating, cluster focus, and hover crosshairs ──
    const cellsG = svg.append('g');
    for (let ri = 0; ri < orderedIds.length; ri++) {
      const rowOrigIdx = leafOrder[ri];
      const rowCid = clusterAssignments.get(rowOrigIdx) ?? 0;
      for (let ci = 0; ci < orderedIds.length; ci++) {
        const colOrigIdx = leafOrder[ci];
        const colCid = clusterAssignments.get(colOrigIdx) ?? 0;
        const val = syncMatrix[rowOrigIdx]?.[colOrigIdx] ?? 0;
        const isDiag = ri === ci;
        const isLow = !isDiag && val < LOW_PLV_THRESHOLD;

        // Cluster focus dimming
        const inFocus = focusedCluster === null || (focusedCluster === rowCid && focusedCluster === colCid);
        const dimFactor = inFocus ? 1 : 0.15;

        const rect = cellsG.append('rect')
          .attr('x', gridX0 + ci * cellSize + 1)
          .attr('y', gridY0 + ri * cellSize + 1)
          .attr('width', cellSize - 2)
          .attr('height', cellSize - 2)
          .attr('rx', 2)
          .attr('fill', isDiag ? 'rgba(249, 115, 22, 0.12)' : treeColorScale(val))
          .attr('opacity', (isLow ? 0.25 : 1) * dimFactor)
          .attr('stroke', '#0a0f14')
          .attr('stroke-width', 0.5)
          .attr('cursor', 'crosshair');

        // Pulse glow on high-sync pairs
        const isHighSync = !isDiag && val >= HIGH_PLV_THRESHOLD && inFocus;
        if (isHighSync) {
          cellsG.append('rect')
            .attr('x', gridX0 + ci * cellSize + 1)
            .attr('y', gridY0 + ri * cellSize + 1)
            .attr('width', cellSize - 2)
            .attr('height', cellSize - 2)
            .attr('rx', 2)
            .attr('fill', 'none')
            .attr('stroke', treeColorScale(val))
            .attr('stroke-width', 2)
            .attr('pointer-events', 'none')
            .attr('class', 'high-sync-pulse');
        }

        // Hover crosshairs
        rect.on('mouseenter', () => {
          crosshairG.selectAll('*').remove();
          // Horizontal highlight bar
          crosshairG.append('rect')
            .attr('x', gridX0).attr('y', gridY0 + ri * cellSize)
            .attr('width', gridSize).attr('height', cellSize)
            .attr('fill', 'rgba(249, 115, 22, 0.06)')
            .attr('pointer-events', 'none');
          // Vertical highlight bar
          crosshairG.append('rect')
            .attr('x', gridX0 + ci * cellSize).attr('y', gridY0)
            .attr('width', cellSize).attr('height', gridSize)
            .attr('fill', 'rgba(249, 115, 22, 0.06)')
            .attr('pointer-events', 'none');
          // Highlight border on hovered cell
          crosshairG.append('rect')
            .attr('x', gridX0 + ci * cellSize + 1)
            .attr('y', gridY0 + ri * cellSize + 1)
            .attr('width', cellSize - 2).attr('height', cellSize - 2)
            .attr('rx', 2)
            .attr('fill', 'none')
            .attr('stroke', '#f97316').attr('stroke-width', 2)
            .attr('pointer-events', 'none');
        }).on('mouseleave', () => {
          crosshairG.selectAll('*').remove();
        });

        rect.append('title')
          .text(isDiag
            ? getDisplayName(orderedIds[ri])
            : `${getDisplayName(orderedIds[ri])} ↔ ${getDisplayName(orderedIds[ci])}: ${Math.round(val * 100)}%`
          );

        if (isDiag) {
          cellsG.append('circle')
            .attr('cx', gridX0 + ci * cellSize + cellSize / 2)
            .attr('cy', gridY0 + ri * cellSize + cellSize / 2)
            .attr('r', Math.min(7, cellSize / 4))
            .attr('fill', sensorColors.get(orderedIds[ri]) || '#f97316')
            .attr('opacity', dimFactor)
            .attr('pointer-events', 'none');
        } else if (cellSize >= 28 && !isLow && inFocus) {
          cellsG.append('text')
            .attr('x', gridX0 + ci * cellSize + cellSize / 2)
            .attr('y', gridY0 + ri * cellSize + cellSize / 2 + 4)
            .attr('text-anchor', 'middle')
            .attr('fill', val > 0.6 ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.8)')
            .attr('font-size', '10px')
            .attr('font-family', 'monospace')
            .attr('pointer-events', 'none')
            .text(Math.round(val * 100));
        }
      }
    }

    // ── Cluster gap lines (orange separators between cluster blocks) ──
    const gapG = svg.append('g').attr('class', 'cluster-gaps');
    for (const boundary of clusterBoundaries) {
      gapG.append('line')
        .attr('x1', gridX0 - 1).attr('y1', gridY0 + boundary * cellSize)
        .attr('x2', gridX0 + gridSize + 1).attr('y2', gridY0 + boundary * cellSize)
        .attr('stroke', '#f9731666').attr('stroke-width', 2);
      gapG.append('line')
        .attr('x1', gridX0 + boundary * cellSize).attr('y1', gridY0 - 1)
        .attr('x2', gridX0 + boundary * cellSize).attr('y2', gridY0 + gridSize + 1)
        .attr('stroke', '#f9731666').attr('stroke-width', 2);
    }

    // Move crosshairs to top of SVG for proper layering
    treeSvgEl.appendChild(crosshairG.node()!);

    // ── Inline color legend (bottom right) ──
    const legX = gridX0 + gridSize - 110;
    const legY = gridY0 + gridSize + 4;
    const legG = svg.append('g');
    const defs = svg.append('defs');
    const grad = defs.append('linearGradient').attr('id', 'tree-plasma-grad');
    [0, 0.25, 0.5, 0.75, 1].forEach(t => {
      grad.append('stop').attr('offset', `${t * 100}%`).attr('stop-color', treeColorScale(t));
    });
    legG.append('rect').attr('x', legX).attr('y', legY).attr('width', 100).attr('height', 6).attr('rx', 2).attr('fill', 'url(#tree-plasma-grad)');
    legG.append('text').attr('x', legX).attr('y', legY + 14).attr('fill', '#6b7280').attr('font-size', '7px').attr('font-family', 'monospace').text('0% sync');
    legG.append('text').attr('x', legX + 100).attr('y', legY + 14).attr('text-anchor', 'end').attr('fill', '#6b7280').attr('font-size', '7px').attr('font-family', 'monospace').text('100% sync');
  }

  // Trigger tree rebuild when heatmap data, view mode, or cut height changes
  $effect(() => {
    const _cut = treeCutHeight; // reactive dependency
    if (viewMode === 'tree' && heatmapSensorIds.length >= 2) {
      requestAnimationFrame(() => renderTreeHeatmap());
    }
    if (viewMode === 'graph' && heatmapSensorIds.length >= 2) {
      requestAnimationFrame(() => renderSyncGraph());
    }
  });

  // ── Sigma.js Sync Graph ──────────────────────────────────────────────
  let graphContainer: HTMLDivElement;
  let sigmaInstance: Sigma | null = null;
  let sigmaGraph: Graph | null = null;
  let graphClusterCount = $state(0);
  const EDGE_MIN_PLV = 0.15; // Only show edges above this sync threshold
  const NODE_BASE_SIZE = 8;

  function renderSyncGraph() {
    if (!graphContainer || heatmapSensorIds.length < 2 || heatmapData.length < 2) return;

    const n = heatmapSensorIds.length;
    const syncMatrix = heatmapData;

    // Build distance matrix and cluster
    const distMatrix: number[][] = Array.from({ length: n }, (_, i) =>
      Array.from({ length: n }, (_, j) => i === j ? 0 : 1 - (syncMatrix[i]?.[j] ?? 0))
    );
    const tree = agglomerativeClustering(distMatrix);
    const maxH = tree.height || 1;
    const cutDist = treeCutHeight * maxH;
    const clusterAssignments = cutTree(tree, cutDist);
    const clusterCount = new Set(clusterAssignments.values()).size;
    graphClusterCount = clusterCount;

    // Compute mean PLV per sensor for node sizing
    const meanPlvs = new Map<number, number>();
    for (let i = 0; i < n; i++) {
      let sum = 0, cnt = 0;
      for (let j = 0; j < n; j++) {
        if (i !== j) { sum += (syncMatrix[i]?.[j] ?? 0); cnt++; }
      }
      meanPlvs.set(i, cnt > 0 ? sum / cnt : 0);
    }

    // Build or update graphology graph
    const isNew = !sigmaGraph || !sigmaInstance;
    const graph = sigmaGraph || new Graph({ type: 'undirected' });

    // Track existing nodes/edges for diff
    const existingNodes = new Set(graph.nodes());
    const existingEdges = new Set(graph.edges());
    const neededNodes = new Set<string>();
    const neededEdges = new Set<string>();

    // Add/update nodes — use stable per-sensor color for identification,
    // cluster membership shown via border color
    for (let i = 0; i < n; i++) {
      const id = heatmapSensorIds[i];
      neededNodes.add(id);
      const clusterId = clusterAssignments.get(i) ?? 0;
      const clusterColor = CLUSTER_COLORS[clusterId % CLUSTER_COLORS.length];
      const color = sensorColors.get(id) || COLORS[i % COLORS.length];
      const meanSync = meanPlvs.get(i) ?? 0;
      const size = NODE_BASE_SIZE + meanSync * 8; // 8-16 range
      const label = getDisplayName(id);

      if (existingNodes.has(id)) {
        graph.setNodeAttribute(id, 'color', color);
        graph.setNodeAttribute(id, 'size', size);
        graph.setNodeAttribute(id, 'label', label);
        graph.setNodeAttribute(id, 'borderColor', clusterColor);
        graph.setNodeAttribute(id, 'clusterId', clusterId);
      } else {
        // Spread initial positions by cluster for better layout
        const angle = (clusterId / Math.max(1, clusterCount)) * 2 * Math.PI + (i * 0.3);
        const radius = 2 + Math.random() * 2;
        graph.addNode(id, {
          x: Math.cos(angle) * radius,
          y: Math.sin(angle) * radius,
          size,
          color,
          label,
          borderColor: clusterColor,
          clusterId,
        });
      }
    }

    // Add/update edges (only above threshold)
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const plv = syncMatrix[i]?.[j] ?? 0;
        const idA = heatmapSensorIds[i];
        const idB = heatmapSensorIds[j];
        const edgeId = `${idA}|${idB}`;
        neededEdges.add(edgeId);

        if (plv >= EDGE_MIN_PLV) {
          const edgeColor = getHeatmapColor(plv);
          const edgeSize = 0.5 + plv * 4; // 0.5-4.5 range
          const sameCluster = (clusterAssignments.get(i) ?? -1) === (clusterAssignments.get(j) ?? -2);

          if (existingEdges.has(edgeId)) {
            graph.setEdgeAttribute(edgeId, 'color', edgeColor);
            graph.setEdgeAttribute(edgeId, 'size', edgeSize);
          } else if (graph.hasEdge(edgeId)) {
            graph.setEdgeAttribute(edgeId, 'color', edgeColor);
            graph.setEdgeAttribute(edgeId, 'size', edgeSize);
          } else {
            try {
              graph.addEdgeWithKey(edgeId, idA, idB, {
                color: edgeColor,
                size: edgeSize,
                type: sameCluster ? 'line' : 'line',
              });
            } catch { /* edge may already exist */ }
          }
        } else {
          // Remove weak edges
          if (graph.hasEdge(edgeId)) graph.dropEdge(edgeId);
        }
      }
    }

    // Remove stale nodes
    for (const id of existingNodes) {
      if (!neededNodes.has(id)) graph.dropNode(id);
    }
    // Remove stale edges (not in current sensor set)
    for (const eid of existingEdges) {
      if (!neededEdges.has(eid) && graph.hasEdge(eid)) graph.dropEdge(eid);
    }

    // Apply ForceAtlas2 layout (short burst for positioning)
    if (graph.order >= 2) {
      forceAtlas2.assign(graph, {
        iterations: isNew ? 100 : 30,
        settings: {
          gravity: 1.5,
          scalingRatio: 4,
          strongGravityMode: true,
          barnesHutOptimize: graph.order > 50,
          slowDown: 5,
        },
      });
    }

    if (isNew) {
      sigmaGraph = graph;
      sigmaInstance = new Sigma(graph, graphContainer, {
        defaultEdgeType: 'line',
        renderLabels: true,
        labelColor: { color: '#e5e7eb' },
        labelFont: 'monospace',
        labelSize: 11,
        labelWeight: '500',
        stagePadding: 30,
        defaultNodeColor: '#f97316',
        defaultEdgeColor: '#374151',
        nodeReducer: (node, data) => {
          const res = { ...data };
          // Draw border ring via larger hidden node (simulated)
          if (data.borderColor) {
            res.borderColor = data.borderColor;
          }
          return res;
        },
        edgeReducer: (_edge, data) => {
          return { ...data };
        },
      });

      // Hover: highlight connected edges
      sigmaInstance.on('enterNode', ({ node }) => {
        const neighbors = new Set(graph.neighbors(node));
        sigmaInstance!.setSetting('nodeReducer', (n, data) => {
          if (n === node || neighbors.has(n)) return { ...data };
          return { ...data, color: '#1e293b', label: '' };
        });
        sigmaInstance!.setSetting('edgeReducer', (edge, data) => {
          const [src, tgt] = graph.extremities(edge);
          if (src === node || tgt === node) return { ...data, size: data.size * 1.5 };
          return { ...data, hidden: true };
        });
      });

      sigmaInstance.on('leaveNode', () => {
        sigmaInstance!.setSetting('nodeReducer', (_, data) => ({ ...data }));
        sigmaInstance!.setSetting('edgeReducer', (_, data) => ({ ...data }));
      });
    } else {
      sigmaInstance!.refresh();
    }
  }

  function cleanupSigma() {
    if (sigmaInstance) {
      sigmaInstance.kill();
      sigmaInstance = null;
      sigmaGraph = null;
    }
  }

  function getHeatmapColor(value: number): string {
    // 0 = red (desynchronized), 0.5 = yellow, 1 = green (synchronized)
    if (value >= 0.75) {
      // Green range
      const t = (value - 0.75) / 0.25;
      const g = Math.round(180 + t * 17);
      return `rgb(34, ${g}, 94)`;
    } else if (value >= 0.5) {
      // Yellow-green range
      const t = (value - 0.5) / 0.25;
      const r = Math.round(234 - t * 200);
      const g = Math.round(179 + t * 18);
      return `rgb(${r}, ${g}, ${Math.round(8 + t * 86)})`;
    } else if (value >= 0.25) {
      // Orange-yellow range
      const t = (value - 0.25) / 0.25;
      const r = Math.round(249 - t * 15);
      const g = Math.round(115 + t * 64);
      return `rgb(${r}, ${g}, ${Math.round(22 - t * 14)})`;
    } else {
      // Red-orange range
      const t = value / 0.25;
      const r = Math.round(239 + t * 10);
      const g = Math.round(68 + t * 47);
      return `rgb(${r}, ${g}, ${Math.round(68 - t * 46)})`;
    }
  }

  function getSyncColor(pct: number): string {
    if (pct >= 80) return '#22c55e';
    if (pct >= 60) return '#84cc16';
    if (pct >= 40) return '#eab308';
    if (pct >= 20) return '#f97316';
    return '#ef4444';
  }

  function getSyncLabel(pct: number): string {
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    if (pct >= 40) return 'Partial';
    if (pct >= 20) return 'Low';
    return 'None';
  }

  function getDisplayName(sensorId: string): string {
    return sensorNames.get(sensorId) || (sensorId.length > 12 ? sensorId.slice(-8) : sensorId);
  }

  // Extract RMSSD from payload (number or {rmssd: number, sdnn?: number} map)
  function extractRmssd(payload: any): number | null {
    if (typeof payload === 'number') return payload;
    if (payload && typeof payload === 'object') {
      const v = payload.rmssd ?? payload.value ?? payload.v;
      return typeof v === 'number' ? v : null;
    }
    return null;
  }

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, COLORS[index % COLORS.length]);
      }
      if (sensor.sensor_name) {
        sensorNames.set(sensor.sensor_id, sensor.sensor_name);
      }
    });
  }

  // Per-sensor EMA state for chart smoothing
  let emaValues: Map<string, number> = new Map();
  const EMA_ALPHA = 0.25; // 0 = fully smoothed, 1 = no smoothing

  function addDataPoint(sensorId: string, value: number, timestamp?: number) {
    // Apply EMA smoothing for chart display
    const prev = emaValues.get(sensorId);
    const smoothed = prev !== undefined
      ? EMA_ALPHA * value + (1 - EMA_ALPHA) * prev
      : value;
    emaValues.set(sensorId, smoothed);

    const pending = pendingUpdates.get(sensorId) || [];
    pending.push({ x: timestamp || Date.now(), y: Math.round(smoothed * 100) / 100 });
    pendingUpdates.set(sensorId, pending);
    latestValues.set(sensorId, smoothed);
    addToPhaseBuffer(sensorId, value);
  }

  // Track new points per sensor for incremental chart updates
  let incrementalPoints: Map<string, Array<{ x: number; y: number }>> = new Map();

  function processPendingUpdates(): boolean {
    if (pendingUpdates.size === 0) return false;

    pendingUpdates.forEach((points, sensorId) => {
      let data = sensorData.get(sensorId) || [];
      data.push(...points);
      if (data.length > MAX_DATA_POINTS) {
        data = data.slice(data.length - MAX_DATA_POINTS);
      }
      sensorData.set(sensorId, data);
      dirtySeriesIds.add(sensorId);

      // Accumulate for incremental chart update
      const inc = incrementalPoints.get(sensorId) || [];
      inc.push(...points);
      incrementalPoints.set(sensorId, inc);
    });

    pendingUpdates.clear();
    return true;
  }

  function rafLoop(timestamp: number) {
    try {
      if (timestamp - lastUpdateTime >= UPDATE_INTERVAL_MS) {
        const hadData = processPendingUpdates();
        updateChart(hadData, timestamp);
        if (hadData) {
          updateHrvStates();
          // Sync computation every 500ms (not every 100ms) — HRV data is slow anyway
          if (timestamp - lastSyncCompute >= 500) {
            computePhaseSync();
            computePairwiseSync();
            lastSyncCompute = timestamp;
          }
        }
        lastUpdateTime = timestamp;
      }
    } catch (e) {
      console.warn("[CompositeHRV] RAF error, recovering:", e);
      if (!chart && chartContainer) createChart();
    }
    rafId = requestAnimationFrame(rafLoop);
  }

  function createChart() {
    if (!chartContainer) return;
    if (chart) {
      chart.destroy();
    }

    const series: Highcharts.SeriesOptionsType[] = Array.from(sensorData.entries()).map(([sensorId, data]) => ({
      type: 'spline' as const,
      id: `sensor-${sensorId}`,
      name: getDisplayName(sensorId),
      data: data.map(d => [d.x, d.y]),
      color: sensorColors.get(sensorId) || '#f97316',
      lineWidth: 1.5,
      yAxis: 0,
      marker: { enabled: false },
      animation: false,
      states: {
        hover: {
          lineWidth: 2.5
        }
      }
    }));

    // Add sync history as colored area at bottom
    series.push({
      type: 'area' as const,
      name: SYNC_SERIES_NAME,
      data: syncHistory.map(d => [d.x, d.y]),
      yAxis: 1,
      lineWidth: 0,
      marker: { enabled: false },
      animation: false,
      fillOpacity: 0.6,
      enableMouseTracking: true,
      showInLegend: false,
      tooltip: {
        pointFormatter: function() {
          const c = this.y < 20 ? '#ef4444' : this.y < 40 ? '#f97316' : this.y < 60 ? '#eab308' : this.y < 80 ? '#84cc16' : '#22c55e';
          return `<span style="color:${c}">\u25CF</span> Phase Sync: <b>${Math.round(this.y)}%</b><br/>`;
        }
      },
      zones: [
        { value: 20, color: '#ef4444' },
        { value: 40, color: '#f97316' },
        { value: 60, color: '#eab308' },
        { value: 80, color: '#84cc16' },
        { color: '#22c55e' }
      ]
    });

    chart = Highcharts.chart(chartContainer, {
      chart: {
        type: 'spline',
        backgroundColor: '#0a0f14',
        animation: false,
        style: {
          fontFamily: 'monospace'
        },
        spacingTop: 5,
        spacingRight: 5,
        spacingBottom: 5,
        spacingLeft: 5,
        zooming: {
          type: 'x'
        }
      },
      title: {
        text: undefined
      },
      credits: {
        enabled: false
      },
      xAxis: {
        type: 'datetime',
        title: {
          text: undefined
        },
        labels: {
          style: {
            color: '#f97316',
            fontSize: '9px'
          },
          format: '{value:%H:%M:%S}'
        },
        crosshair: {
          width: 1,
          color: 'rgba(249, 115, 22, 0.4)',
          dashStyle: 'Dot'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(249, 115, 22, 0.15)',
        minorGridLineWidth: 0,
        lineColor: 'rgba(249, 115, 22, 0.3)',
        tickColor: 'rgba(249, 115, 22, 0.3)'
      },
      yAxis: [{
        // Primary: RMSSD values
        title: {
          text: 'ms',
          style: {
            color: '#f97316',
            fontSize: '10px'
          },
          margin: 5
        },
        min: 0,
        max: 120,
        height: '85%',
        labels: {
          style: {
            color: '#f97316',
            fontSize: '9px'
          },
          format: '{value:.0f}'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(249, 115, 22, 0.15)',
        minorGridLineWidth: 0,
        plotBands: [{
          from: 20,
          to: 80,
          color: 'rgba(249, 115, 22, 0.03)',
          label: {
            text: 'Normal range',
            style: { color: 'rgba(249, 115, 22, 0.3)', fontSize: '9px' },
            align: 'right'
          }
        }]
      }, {
        // Secondary: Sync percentage (bottom strip)
        title: { text: undefined },
        min: 0,
        max: 100,
        top: '88%',
        height: '12%',
        offset: 0,
        labels: { enabled: false },
        gridLineWidth: 0
      }],
      legend: {
        enabled: true,
        align: 'center',
        verticalAlign: 'bottom',
        layout: 'horizontal',
        floating: false,
        backgroundColor: 'transparent',
        borderWidth: 0,
        itemStyle: {
          color: '#9ca3af',
          fontSize: '9px'
        },
        itemHoverStyle: {
          color: '#ffffff'
        },
        itemMarginTop: 2,
        itemMarginBottom: 0,
        margin: 5,
        padding: 0
      },
      tooltip: {
        backgroundColor: 'rgba(10, 15, 20, 0.95)',
        borderColor: 'rgba(249, 115, 22, 0.5)',
        borderWidth: 1,
        style: {
          color: '#f97316',
          fontSize: '11px'
        },
        xDateFormat: '%H:%M:%S.%L',
        valueDecimals: 1,
        valueSuffix: 'ms',
        shared: true
      },
      plotOptions: {
        spline: {
          animation: false,
          lineWidth: 1.5
        },
        series: {
          animation: false,
          turboThreshold: 10000,
          states: {
            hover: {
              lineWidthPlus: 1
            }
          }
        }
      },
      series: series
    });
  }

  function getFilteredData(data: Array<{ x: number; y: number }>, cutoff: number): Array<[number, number]> {
    let lo = 0, hi = data.length;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (data[mid].x < cutoff) lo = mid + 1;
      else hi = mid;
    }
    const result: Array<[number, number]> = new Array(data.length - lo);
    for (let i = lo; i < data.length; i++) {
      result[i - lo] = [data[i].x, data[i].y];
    }
    return result;
  }

  function updateChart(hadData: boolean, timestamp: number) {
    if (!chart) {
      if (chartContainer && sensorData.size > 0) createChart();
      return;
    }

    if (!chart.container || !chartContainer?.isConnected) {
      chart = null;
      return;
    }

    if (!hadData) {
      if (timestamp - lastExtremesUpdate >= 500) {
        const now = Date.now();
        chart.xAxis[0].setExtremes(now - selectedWindowMs, now, true, false);
        lastExtremesUpdate = timestamp;
      }
      return;
    }

    const now = Date.now();
    const cutoff = now - selectedWindowMs;
    let needsRedraw = false;
    let needsFullRedraw = false;

    dirtySeriesIds.forEach((sensorId) => {
      const seriesId = `sensor-${sensorId}`;
      const existingSeries = chart!.get(seriesId) as Highcharts.Series | null;

      if (existingSeries) {
        // Incremental: add only new points (much faster than setData)
        const newPts = incrementalPoints.get(sensorId);
        if (newPts && newPts.length > 0) {
          for (const pt of newPts) {
            existingSeries.addPoint([pt.x, pt.y], false, false, false);
          }
          needsRedraw = true;
        }
      } else {
        // New series — full data needed
        const data = sensorData.get(sensorId);
        if (!data) return;
        const index = Array.from(sensorData.keys()).indexOf(sensorId);
        const filteredData = getFilteredData(data, cutoff);
        chart!.addSeries({
          type: 'spline',
          id: seriesId,
          name: getDisplayName(sensorId),
          data: filteredData,
          yAxis: 0,
          color: sensorColors.get(sensorId) || COLORS[index % COLORS.length],
          lineWidth: 1.5,
          marker: { enabled: false },
          animation: false
        }, false);
        needsRedraw = true;
        needsFullRedraw = true;
      }
    });
    dirtySeriesIds.clear();
    incrementalPoints.clear();

    if (syncDirty) {
      const syncSeries = chart.series.find(s => s.name === SYNC_SERIES_NAME);
      if (syncSeries) {
        // Incremental: add only last sync point
        const last = syncHistory[syncHistory.length - 1];
        if (last) {
          syncSeries.addPoint([last.x, last.y], false, false, false);
          needsRedraw = true;
        }
      } else if (syncHistory.length > 0) {
        const filteredSync = getFilteredData(syncHistory, cutoff);
        chart.addSeries({
          type: 'area',
          name: SYNC_SERIES_NAME,
          data: filteredSync,
          yAxis: 1,
          lineWidth: 0,
          marker: { enabled: false },
          animation: false,
          fillOpacity: 0.6,
          enableMouseTracking: true,
          showInLegend: false,
          tooltip: {
            pointFormatter: function() {
              const c = this.y < 20 ? '#ef4444' : this.y < 40 ? '#f97316' : this.y < 60 ? '#eab308' : this.y < 80 ? '#84cc16' : '#22c55e';
              return `<span style="color:${c}">\u25CF</span> Phase Sync: <b>${Math.round(this.y)}%</b><br/>`;
            }
          },
          zones: [
            { value: 20, color: '#ef4444' },
            { value: 40, color: '#f97316' },
            { value: 60, color: '#eab308' },
            { value: 80, color: '#84cc16' },
            { color: '#22c55e' }
          ]
        }, false);
        needsRedraw = true;
      }
      syncDirty = false;
    }

    if (needsRedraw) {
      chart.xAxis[0].setExtremes(now - selectedWindowMs, now, false);
      chart.redraw(false);
      lastExtremesUpdate = timestamp;

      // Periodically trim old points from series to prevent unbounded growth
      // Only do this every 5s to avoid overhead
      if (needsFullRedraw || timestamp - lastTrimTime > 5000) {
        lastTrimTime = timestamp;
        chart.series.forEach(s => {
          while (s.data.length > 0 && (s.data[0] as any).x < cutoff) {
            s.data[0].remove(false, false);
          }
        });
      }
    }
  }

  function setTimeWindow(ms: number) {
    selectedWindowMs = ms;
    // Recreate chart with new window — full setData needed
    if (chart) {
      chart.destroy();
      chart = null;
    }
    createChart();
  }

  function consumeSeedBuffer(): boolean {
    const seedBuffer = (window as any).__compositeSeedBuffer;
    if (!Array.isArray(seedBuffer) || seedBuffer.length === 0) return false;

    let consumed = 0;
    seedBuffer.forEach((event: any) => {
      if (event.attribute_id === "hrv" && Array.isArray(event.data)) {
        const sid = event.sensor_id;
        if (!sensorData.has(sid)) {
          const index = sensorData.size;
          sensorColors.set(sid, COLORS[index % COLORS.length]);
          sensorData.set(sid, []);
        }
        event.data.forEach((m: any) => {
          const v = extractRmssd(m?.payload);
          if (v !== null) {
            addDataPoint(sid, v, m.timestamp);
          }
        });
        consumed++;
      } else if (event.attribute_id === "hrv_sync" && Array.isArray(event.data)) {
        event.data.forEach((m: any) => {
          if (typeof m?.payload === "number") {
            syncHistory.push({ x: m.timestamp, y: m.payload });
          }
        });
        syncDirty = true;
        consumed++;
      }
    });
    (window as any).__compositeSeedBuffer = [];
    if (consumed > 0) processPendingUpdates();
    return consumed > 0;
  }

  onMount(() => {
    initializeSensorData();
    createChart();
    rafId = requestAnimationFrame(rafLoop);

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload, timestamp } = e.detail;

      if (attribute_id === "hrv") {
        const value = extractRmssd(payload);

        if (value !== null) {
          if (!sensorData.has(sensor_id)) {
            const index = sensorData.size;
            sensorColors.set(sensor_id, COLORS[index % COLORS.length]);
            sensorData.set(sensor_id, []);
          }
          addDataPoint(sensor_id, value, timestamp);
        }
      }
    };

    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;
      if (attributeId === "hrv") {
        const data = e?.detail?.data;

        if (Array.isArray(data) && data.length > 0) {
          if (!sensorData.has(eventSensorId)) {
            const index = sensorData.size;
            sensorColors.set(eventSensorId, COLORS[index % COLORS.length]);
            sensorData.set(eventSensorId, []);
          }
          data.forEach((measurement: any) => {
            const value = extractRmssd(measurement?.payload);
            const timestamp = measurement?.timestamp;
            if (value !== null) {
              addDataPoint(eventSensorId, value, timestamp);
            }
          });
        } else if (data?.payload !== undefined) {
          const value = extractRmssd(data.payload);
          if (value !== null) {
            if (!sensorData.has(eventSensorId)) {
              const index = sensorData.size;
              sensorColors.set(eventSensorId, COLORS[index % COLORS.length]);
              sensorData.set(eventSensorId, []);
            }
            addDataPoint(eventSensorId, value, data.timestamp);
          }
        }
      } else if (attributeId === "hrv_sync") {
        const data = e?.detail?.data;
        if (Array.isArray(data) && data.length > 0) {
          data.forEach((m: any) => {
            if (typeof m?.payload === "number") {
              syncHistory.push({ x: m.timestamp, y: m.payload });
            }
          });
          syncDirty = true;
        }
      }
    };

    window.addEventListener(
      "composite-measurement-event",
      handleCompositeMeasurement as EventListener
    );

    window.addEventListener(
      "accumulator-data-event",
      handleAccumulatorEvent as EventListener
    );

    // Signal readiness - the hook will replay any buffered seed data
    if (consumeSeedBuffer()) {
      sensorData.forEach((_data, sensorId) => dirtySeriesIds.add(sensorId));
      syncDirty = true;
      updateChart(true, performance.now());
    }
    window.dispatchEvent(new CustomEvent('composite-component-ready'));

    return () => {
      window.removeEventListener(
        "composite-measurement-event",
        handleCompositeMeasurement as EventListener
      );
      window.removeEventListener(
        "accumulator-data-event",
        handleAccumulatorEvent as EventListener
      );
    };
  });

  onDestroy(() => {
    if (rafId) {
      cancelAnimationFrame(rafId);
    }
    if (chart) {
      chart.destroy();
    }
    cleanupSigma();
  });
</script>

<div class="composite-chart-container">
  <div class="chart-header">
    <div class="header-left">
      <h2>HRV Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="stats-bar">
      <span class="hrv-state has-tooltip" data-tooltip="Stressed — RMSSD below 20ms. High sympathetic (fight-or-flight) activity">
        <svg class="hrv-svg stressed" viewBox="0 0 16 16" width="12" height="12">
          <path d="M3 4 L8 12 L13 4 Z" fill="currentColor" opacity="0.8"/>
        </svg>
        {stressedCount}
      </span>
      <span class="hrv-state has-tooltip" data-tooltip="Moderate — RMSSD 20-50ms. Balanced autonomic nervous system activity">
        <svg class="hrv-svg moderate" viewBox="0 0 16 16" width="12" height="12">
          <rect x="2" y="6" width="12" height="4" rx="1" fill="currentColor" opacity="0.8"/>
        </svg>
        {moderateCount}
      </span>
      <span class="hrv-state has-tooltip" data-tooltip="Relaxed — RMSSD above 50ms. High parasympathetic (rest-and-digest) activity">
        <svg class="hrv-svg relaxed" viewBox="0 0 16 16" width="12" height="12">
          <path d="M3 12 L8 4 L13 12 Z" fill="currentColor" opacity="0.8"/>
        </svg>
        {relaxedCount}
      </span>
      <span class="stat-divider"></span>
      <span class="hrv-mean has-tooltip" data-tooltip="Group Mean RMSSD — average of successive RR-interval differences across all participants. Higher = greater vagal tone / relaxation">x&#x0304; {groupMeanRmssd}<span class="hrv-unit">ms</span></span>
      <span class="stat-divider"></span>
      <span class="sync-value has-tooltip" data-tooltip="Phase Sync (Kuramoto) — how synchronized HRV oscillations are across participants. 0% = random, 100% = perfectly in sync" style="color: {getSyncColor(phaseSync)}">{phaseSync}%</span>
    </div>
    <div class="header-controls">
      <div class="view-mode-selector">
        <button
          class="time-btn"
          class:active={viewMode === 'chart'}
          onclick={() => { cleanupSigma(); viewMode = 'chart'; if (chart) setTimeout(() => chart?.reflow(), 50); }}
          title="Kuramoto time-series chart"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.5">
            <polyline points="1,12 4,8 7,10 10,4 13,6 15,2"/>
          </svg>
          Chart
        </button>
        <button
          class="time-btn"
          class:active={viewMode === 'heatmap'}
          onclick={() => { cleanupSigma(); viewMode = 'heatmap'; }}
          title="Pairwise synchronization heatmap"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="currentColor">
            <rect x="1" y="1" width="4" height="4" rx="0.5" opacity="0.9"/>
            <rect x="6" y="1" width="4" height="4" rx="0.5" opacity="0.5"/>
            <rect x="11" y="1" width="4" height="4" rx="0.5" opacity="0.2"/>
            <rect x="1" y="6" width="4" height="4" rx="0.5" opacity="0.5"/>
            <rect x="6" y="6" width="4" height="4" rx="0.5" opacity="0.9"/>
            <rect x="11" y="6" width="4" height="4" rx="0.5" opacity="0.4"/>
            <rect x="1" y="11" width="4" height="4" rx="0.5" opacity="0.2"/>
            <rect x="6" y="11" width="4" height="4" rx="0.5" opacity="0.4"/>
            <rect x="11" y="11" width="4" height="4" rx="0.5" opacity="0.9"/>
          </svg>
          Heatmap
        </button>
        <button
          class="time-btn"
          class:active={viewMode === 'tree'}
          onclick={() => { cleanupSigma(); viewMode = 'tree'; }}
          title="Clustered dendrogram heatmap"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.2">
            <line x1="8" y1="2" x2="8" y2="6"/>
            <line x1="4" y1="6" x2="12" y2="6"/>
            <line x1="4" y1="6" x2="4" y2="9"/>
            <line x1="12" y1="6" x2="12" y2="9"/>
            <rect x="2" y="9" width="4" height="5" rx="0.5" fill="currentColor" opacity="0.5"/>
            <rect x="10" y="9" width="4" height="5" rx="0.5" fill="currentColor" opacity="0.8"/>
          </svg>
          Tree
        </button>
        <button
          class="time-btn"
          class:active={viewMode === 'graph'}
          onclick={() => { viewMode = 'graph'; cleanupSigma(); requestAnimationFrame(() => renderSyncGraph()); }}
          title="Force-directed sync graph"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.2">
            <circle cx="4" cy="4" r="2" fill="currentColor" opacity="0.7"/>
            <circle cx="12" cy="4" r="2" fill="currentColor" opacity="0.7"/>
            <circle cx="8" cy="13" r="2" fill="currentColor" opacity="0.7"/>
            <line x1="5.5" y1="5" x2="10.5" y2="5" opacity="0.6"/>
            <line x1="4.5" y1="5.5" x2="7.5" y2="11.5" opacity="0.6"/>
            <line x1="11.5" y1="5.5" x2="8.5" y2="11.5" opacity="0.6"/>
          </svg>
          Graph
        </button>
      </div>
      {#if viewMode === 'chart'}
        <div class="time-window-selector">
          {#each TIME_WINDOWS as window}
            <button
              class="time-btn"
              class:active={selectedWindowMs === window.ms}
              onclick={() => setTimeWindow(window.ms)}
            >
              {window.label}
            </button>
          {/each}
        </div>
      {/if}
    </div>
  </div>
  <div class="sync-bar">
    <div
      class="sync-bar-fill"
      style="width: {phaseSync}%; background: {getSyncColor(phaseSync)}"
    ></div>
  </div>
  {#if viewMode === 'chart'}
    <div class="chart-wrapper" bind:this={chartContainer}></div>
  {:else if viewMode === 'graph'}
    <div class="graph-section">
      <div class="heatmap-header">
        <span class="heatmap-title">Sync Network</span>
        <div class="tree-anno-legend">
          <span class="anno-key" title="Edge thickness = PLV strength"><span class="anno-dot" style="background:#22c55e"></span>Sync</span>
          <span class="anno-key" title="Border color = cluster membership"><span class="anno-dot" style="background:#3b82f6"></span>Cluster</span>
          {#if graphClusterCount > 0}
            <span class="cluster-badge">{graphClusterCount} clusters</span>
          {/if}
        </div>
      </div>
      {#if heatmapSensorIds.length >= 2}
        <div class="graph-canvas" bind:this={graphContainer}></div>
      {:else}
        <div class="heatmap-empty">
          Waiting for ≥2 sensors with HRV phase data...
        </div>
      {/if}
    </div>
  {:else if viewMode === 'tree'}
    <div class="heatmap-section" bind:this={treeContainer}>
      <div class="heatmap-header">
        <span class="heatmap-title">Clustered HRV Synchronization</span>
        <div class="tree-anno-legend">
          <span class="anno-key" title="C = Cluster membership"><span class="anno-dot" style="background:#3b82f6"></span>C</span>
          <span class="anno-key" title="S = Stress state (RMSSD)"><span class="anno-dot" style="background:#22c55e"></span>S</span>
          <span class="anno-key" title="P = Mean PLV bar"><span class="anno-dot" style="background:#f97316"></span>P</span>
          {#if treeClusterCount > 0}
            <span class="cluster-badge">{treeClusterCount} clusters</span>
          {/if}
          {#if focusedCluster !== null}
            <button class="focus-reset-btn" onclick={() => { focusedCluster = null; requestAnimationFrame(() => renderTreeHeatmap()); }}>
              Show all
            </button>
          {/if}
        </div>
      </div>
      {#if heatmapSensorIds.length >= 2}
        <div class="heatmap-scroll">
          <svg bind:this={treeSvgEl} class="heatmap-svg"></svg>
        </div>
        {#if clusterSummaries.length > 1}
          <div class="cluster-cards">
            {#each clusterSummaries as cluster}
              <button
                class="cluster-card"
                class:focused={focusedCluster === cluster.id}
                class:dimmed={focusedCluster !== null && focusedCluster !== cluster.id}
                onclick={() => { focusedCluster = focusedCluster === cluster.id ? null : cluster.id; requestAnimationFrame(() => renderTreeHeatmap()); }}
                style="--cluster-color: {cluster.color}"
              >
                <div class="cluster-card-header">
                  <span class="cluster-card-dot" style="background: {cluster.color}"></span>
                  <span class="cluster-card-label">C{cluster.id + 1}</span>
                  <span class="cluster-card-count">{cluster.members.length}</span>
                </div>
                <div class="cluster-card-plv" title="Mean intra-cluster PLV">
                  <div class="cluster-plv-bar" style="width: {Math.round(cluster.meanPlv * 100)}%; background: {cluster.color}"></div>
                  <span class="cluster-plv-val">{Math.round(cluster.meanPlv * 100)}%</span>
                </div>
                <div class="cluster-card-stress">
                  {#if cluster.stressCounts.relaxed > 0}
                    <span class="stress-pip" style="background: #22c55e" title="{cluster.stressCounts.relaxed} relaxed">{cluster.stressCounts.relaxed}</span>
                  {/if}
                  {#if cluster.stressCounts.moderate > 0}
                    <span class="stress-pip" style="background: #eab308" title="{cluster.stressCounts.moderate} moderate">{cluster.stressCounts.moderate}</span>
                  {/if}
                  {#if cluster.stressCounts.stressed > 0}
                    <span class="stress-pip" style="background: #ef4444" title="{cluster.stressCounts.stressed} stressed">{cluster.stressCounts.stressed}</span>
                  {/if}
                </div>
              </button>
            {/each}
          </div>
        {/if}
      {:else}
        <div class="heatmap-empty">
          Waiting for ≥2 sensors with HRV phase data...
        </div>
      {/if}
    </div>
  {:else}
    <div class="heatmap-section">
      <div class="heatmap-header">
        <span class="heatmap-title">Pairwise HRV Synchronization</span>
        <div class="heatmap-legend">
          <span class="legend-label">Low</span>
          <div class="legend-gradient"></div>
          <span class="legend-label">High</span>
        </div>
      </div>
      {#if heatmapSensorIds.length >= 2}
        {@const n = heatmapSensorIds.length}
        {@const cellSize = Math.max(28, Math.min(56, 500 / n))}
        {@const labelWidth = 80}
        {@const headerHeight = 100}
        {@const gridWidth = n * cellSize}
        {@const svgWidth = labelWidth + gridWidth + 2}
        {@const svgHeight = headerHeight + gridWidth + 2}
        <div class="heatmap-scroll">
          <svg
            viewBox="0 0 {svgWidth} {svgHeight}"
            class="heatmap-svg"
            preserveAspectRatio="xMidYMid meet"
          >
            <!-- Column labels (top, rotated -45°) -->
            {#each heatmapSensorIds as id, i}
              {@const cx = labelWidth + i * cellSize + cellSize / 2}
              {@const cy = headerHeight - 6}
              <text
                x={cx}
                y={cy}
                text-anchor="start"
                transform="rotate(-45, {cx}, {cy})"
                class="heatmap-label"
              >{getDisplayName(id)}</text>
            {/each}

            <!-- Row labels (left) + cells -->
            {#each heatmapSensorIds as rowId, i}
              <text
                x={labelWidth - 6}
                y={headerHeight + i * cellSize + cellSize / 2 + 3}
                text-anchor="end"
                class="heatmap-label"
              >{getDisplayName(rowId)}</text>

              {#each heatmapSensorIds as _colId, j}
                {@const value = heatmapData[i]?.[j] ?? 0}
                <rect
                  x={labelWidth + j * cellSize + 1}
                  y={headerHeight + i * cellSize + 1}
                  width={cellSize - 2}
                  height={cellSize - 2}
                  rx="2"
                  fill={i === j ? 'rgba(249, 115, 22, 0.15)' : getHeatmapColor(value)}
                  opacity={i === j ? 1 : 0.85}
                >
                  <title>{i === j ? getDisplayName(rowId) : `${getDisplayName(rowId)} ↔ ${getDisplayName(_colId)}: ${Math.round(value * 100)}%`}</title>
                </rect>
                {#if i === j}
                  <circle
                    cx={labelWidth + j * cellSize + cellSize / 2}
                    cy={headerHeight + i * cellSize + cellSize / 2}
                    r={Math.min(8, cellSize / 3.5)}
                    fill={sensorColors.get(rowId) || '#f97316'}
                  />
                {:else if cellSize >= 28}
                  <text
                    x={labelWidth + j * cellSize + cellSize / 2}
                    y={headerHeight + i * cellSize + cellSize / 2 + 4}
                    text-anchor="middle"
                    class="cell-value"
                  >{Math.round(value * 100)}</text>
                {/if}
              {/each}
            {/each}
          </svg>
        </div>
      {:else}
        <div class="heatmap-empty">
          Waiting for ≥2 sensors with HRV phase data...
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .composite-chart-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(249, 115, 22, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    display: flex;
    flex-direction: column;
    box-shadow:
      0 0 20px rgba(249, 115, 22, 0.05),
      inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.2rem 0.5rem;
    background: rgba(249, 115, 22, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(249, 115, 22, 0.2);
    gap: 0.5rem;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    min-width: 0;
  }

  .chart-header h2 {
    font-size: 0.75rem;
    font-weight: 600;
    color: #f97316;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    white-space: nowrap;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #f97316;
    font-family: monospace;
    opacity: 0.7;
    white-space: nowrap;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .hrv-state {
    display: flex;
    align-items: center;
    gap: 0.15rem;
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    color: #f97316;
    font-variant-numeric: tabular-nums;
  }

  .hrv-svg {
    flex-shrink: 0;
  }

  .hrv-svg.stressed { color: #ef4444; }
  .hrv-svg.moderate { color: #eab308; }
  .hrv-svg.relaxed { color: #22c55e; }

  .hrv-mean {
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    color: #f97316;
    font-variant-numeric: tabular-nums;
  }

  .hrv-unit {
    font-size: 0.55rem;
    opacity: 0.6;
    margin-left: 1px;
  }

  .stat-divider {
    width: 1px;
    height: 0.8rem;
    background: rgba(249, 115, 22, 0.2);
  }

  .sync-value {
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    font-variant-numeric: tabular-nums;
  }

  .has-tooltip {
    position: relative;
    cursor: help;
  }

  .has-tooltip::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 6px);
    left: 50%;
    transform: translateX(-50%);
    background: rgba(10, 15, 20, 0.95);
    color: #e5e7eb;
    font-size: 0.65rem;
    font-weight: 400;
    font-family: system-ui, sans-serif;
    line-height: 1.4;
    padding: 0.35rem 0.5rem;
    border-radius: 0.25rem;
    border: 1px solid rgba(249, 115, 22, 0.3);
    white-space: normal;
    width: max-content;
    max-width: 220px;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.15s ease;
    z-index: 100;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  }

  .has-tooltip:hover::after {
    opacity: 1;
  }

  @media (max-width: 480px) {
    .composite-chart-container { padding: 0.15rem; }
    .chart-header { flex-wrap: nowrap; gap: 0.2rem; padding: 0.1rem 0.2rem; margin-bottom: 0.1rem; }
    .header-left { gap: 0.2rem; flex-shrink: 0; }
    .chart-header h2 { font-size: 0.55rem; letter-spacing: 0; }
    .sensor-count { display: none; }
    .stats-bar { gap: 0.25rem; }
    .hrv-state { font-size: 0.6rem; }
    .hrv-svg { width: 10px; height: 10px; }
    .hrv-mean { font-size: 0.6rem; }
    .sync-value { font-size: 0.6rem; }
    .stat-divider { height: 0.6rem; }
    .sync-bar { height: 2px; margin-bottom: 0.1rem; }
    .time-window-selector { gap: 0.1rem; flex-shrink: 0; }
    .time-btn { padding: 0.1rem 0.2rem; font-size: 0.5rem; }
    .heatmap-section { min-height: 100px; }
    .heatmap-title { font-size: 0.55rem; }
    .view-mode-selector .time-btn svg { display: none; }
  }

  .sync-bar {
    height: 3px;
    background: rgba(249, 115, 22, 0.1);
    border-radius: 2px;
    margin-bottom: 0.25rem;
    overflow: hidden;
  }

  .sync-bar-fill {
    height: 100%;
    border-radius: 2px;
    transition: width 0.3s ease, background 0.3s ease;
    box-shadow: 0 0 6px currentColor;
  }

  .time-window-selector {
    display: flex;
    gap: 0.25rem;
  }

  .time-btn {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    font-family: monospace;
    background: rgba(249, 115, 22, 0.1);
    border: 1px solid rgba(249, 115, 22, 0.3);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .time-btn:hover {
    background: rgba(249, 115, 22, 0.2);
    color: #f97316;
  }

  .time-btn.active {
    background: rgba(249, 115, 22, 0.3);
    border-color: #f97316;
    color: #f97316;
    box-shadow: 0 0 8px rgba(249, 115, 22, 0.3);
  }

  .header-controls {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .view-mode-selector {
    display: flex;
    gap: 0.15rem;
  }

  .view-mode-selector .time-btn {
    display: flex;
    align-items: center;
    gap: 0.2rem;
  }

  .heatmap-section {
    flex: 1;
    min-height: 200px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .heatmap-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 0.25rem;
    margin-bottom: 0.25rem;
  }

  .heatmap-title {
    font-size: 0.65rem;
    font-family: monospace;
    color: #f97316;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.8;
  }

  .heatmap-legend {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .legend-label {
    font-size: 0.55rem;
    font-family: monospace;
    color: #9ca3af;
  }

  .legend-gradient {
    width: 60px;
    height: 6px;
    border-radius: 3px;
    background: linear-gradient(to right, #ef4444, #f97316, #eab308, #84cc16, #22c55e);
  }

  .legend-gradient-tree {
    width: 60px;
    height: 6px;
    border-radius: 3px;
    background: linear-gradient(to right, #0d0887, #7e03a8, #cc4778, #f89441, #f0f921);
  }

  .tree-anno-legend {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .anno-key {
    display: flex;
    align-items: center;
    gap: 0.15rem;
    font-size: 0.6rem;
    font-family: monospace;
    color: #9ca3af;
    cursor: help;
  }

  .anno-dot {
    width: 6px;
    height: 6px;
    border-radius: 1px;
    flex-shrink: 0;
  }

  .cluster-badge {
    font-size: 0.6rem;
    font-family: monospace;
    color: #f97316;
    background: rgba(249, 115, 22, 0.15);
    padding: 0.1rem 0.3rem;
    border-radius: 0.2rem;
    border: 1px solid rgba(249, 115, 22, 0.3);
  }

  .focus-reset-btn {
    font-size: 0.55rem;
    font-family: monospace;
    color: #9ca3af;
    background: rgba(156, 163, 175, 0.1);
    border: 1px solid rgba(156, 163, 175, 0.2);
    padding: 0.1rem 0.35rem;
    border-radius: 0.2rem;
    cursor: pointer;
    transition: all 0.15s;
  }
  .focus-reset-btn:hover {
    color: #f97316;
    border-color: rgba(249, 115, 22, 0.4);
  }

  .cluster-cards {
    display: flex;
    gap: 0.35rem;
    padding: 0.35rem 0.5rem;
    overflow-x: auto;
    flex-shrink: 0;
  }

  .cluster-card {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    min-width: 70px;
    padding: 0.3rem 0.4rem;
    background: rgba(15, 23, 42, 0.6);
    border: 1px solid rgba(100, 116, 139, 0.15);
    border-radius: 0.35rem;
    cursor: pointer;
    transition: all 0.2s;
    font-family: monospace;
  }
  .cluster-card:hover {
    border-color: var(--cluster-color, #f97316);
    background: rgba(15, 23, 42, 0.8);
  }
  .cluster-card.focused {
    border-color: var(--cluster-color, #f97316);
    box-shadow: 0 0 6px rgba(249, 115, 22, 0.2);
  }
  .cluster-card.dimmed {
    opacity: 0.35;
  }

  .cluster-card-header {
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }
  .cluster-card-dot {
    width: 8px;
    height: 8px;
    border-radius: 2px;
    flex-shrink: 0;
  }
  .cluster-card-label {
    font-size: 0.6rem;
    color: #e2e8f0;
    font-weight: bold;
  }
  .cluster-card-count {
    font-size: 0.5rem;
    color: #64748b;
    margin-left: auto;
  }

  .cluster-card-plv {
    position: relative;
    height: 4px;
    background: rgba(30, 41, 59, 0.8);
    border-radius: 2px;
    overflow: hidden;
  }
  .cluster-plv-bar {
    height: 100%;
    border-radius: 2px;
    transition: width 0.3s;
  }
  .cluster-plv-val {
    position: absolute;
    right: 0;
    top: -10px;
    font-size: 0.45rem;
    color: #94a3b8;
  }

  .cluster-card-stress {
    display: flex;
    gap: 0.15rem;
  }
  .stress-pip {
    font-size: 0.45rem;
    color: #0f172a;
    font-weight: bold;
    width: 12px;
    height: 12px;
    border-radius: 2px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  @keyframes sync-pulse {
    0%, 100% { opacity: 0; stroke-width: 1.5; }
    50% { opacity: 0.8; stroke-width: 3; }
  }
  :global(.high-sync-pulse) {
    animation: sync-pulse 2.5s ease-in-out infinite;
  }

  .heatmap-scroll {
    flex: 1;
    overflow: auto;
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 0.5rem;
  }

  .heatmap-svg {
    max-width: 100%;
    max-height: 100%;
    width: auto;
    height: auto;
  }

  .heatmap-label {
    font-size: 13px;
    font-family: monospace;
    fill: #9ca3af;
  }

  .cell-value {
    font-size: 12px;
    font-family: monospace;
    fill: rgba(255, 255, 255, 0.85);
    pointer-events: none;
  }

  .heatmap-empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-family: monospace;
    color: #9ca3af;
    opacity: 0.6;
  }

  .chart-wrapper {
    flex: 1;
    min-height: 200px;
    background:
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 19px,
        rgba(249, 115, 22, 0.03) 19px,
        rgba(249, 115, 22, 0.03) 20px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 19px,
        rgba(249, 115, 22, 0.03) 19px,
        rgba(249, 115, 22, 0.03) 20px
      ),
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 99px,
        rgba(249, 115, 22, 0.08) 99px,
        rgba(249, 115, 22, 0.08) 100px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 99px,
        rgba(249, 115, 22, 0.08) 99px,
        rgba(249, 115, 22, 0.08) 100px
      );
    border-radius: 0.25rem;
  }

  .graph-section {
    flex: 1;
    min-height: 200px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .graph-canvas {
    flex: 1;
    min-height: 200px;
    border-radius: 0.25rem;
    background: #060a0e;
    position: relative;
  }

  /* Sigma renders canvases absolutely positioned — container needs relative */
  .graph-canvas :global(canvas) {
    border-radius: 0.25rem;
  }
</style>
