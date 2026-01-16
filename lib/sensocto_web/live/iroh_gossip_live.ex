defmodule SensoctoWeb.Live.IrohGossipLive do
  use SensoctoWeb, :live_view
  alias IrohEx.Native
  alias GossipParser
  alias MermaidGenerator

  @node_cnt 50
  @msg_cnt 1_000
  @rand_msg_delay 50
  @use_random_sender true
  # 3000
  @delay_after_connect 3000
  #
  @delay_after_send 3000
  # Reserved for future use
  @max_send_concurrency 16
  @msg_timeout 30_000
  _ = {@max_send_concurrency, @msg_timeout}

  @impl true
  def mount(_params, _session, socket) do
    Process.send_after(self(), :setup_nodes, 0)

    {:ok,
     socket
     |> put_flash(:info, "Mounted ...")
     |> assign(
       nodes: [],
       nodes_connected: 0,
       mothership_node_ref: nil,
       ticket: nil,
       messages: [],
       message_cnt: 0,
       graph: nil
     )}
  end

  @impl true
  def handle_info(:setup_nodes, socket) do
    pid = self()
    config = IrohEx.NodeConfig.build()
    mothership_node_ref = Native.create_node(pid, config)
    ticket = Native.create_ticket(mothership_node_ref)
    nodes = create_nodes(@node_cnt, pid, config)

    # {:messages, messages} = :erlang.process_info(self(), :messages)

    # nodes_parsed = GossipParser.parse_gossip_messages(messages)
    # mermaid_viz = MermaidGenerator.generate_mermaid_graph(nodes_parsed)

    Process.send_after(self(), :connect_nodes, 0)

    {:noreply,
     socket
     |> put_flash(:info, "Nodes created, connecting ...")
     |> assign(
       nodes: nodes,
       ticket: ticket,
       mothership_node_ref: mothership_node_ref
     )}
  end

  @impl true
  def handle_info(:connect_nodes, socket) do
    pid = self()

    nodes = socket.assigns.nodes
    ticket = socket.assigns.ticket

    tasks =
      Enum.map(nodes, fn n ->
        Task.async(fn ->
          # node_id = Native.gen_node_addr(n)
          Native.connect_node(n, ticket)
          Process.send_after(pid, :inc_connected, 0)
        end)
      end)

    Enum.each(tasks, &Task.await/1)
    Process.send_after(self(), :send_messages, @delay_after_connect)

    {:noreply,
     socket
     |> put_flash(:info, "Nodes connected, sending messages ...")}
  end

  @impl true
  def handle_info(:send_messages, socket) do
    nodes = socket.assigns.nodes

    send_messages(nodes)

    Process.sleep(@delay_after_send)

    {:noreply,
     socket
     |> put_flash(:info, "Messages sent, delivering ... ")}
  end

  @impl true
  def handle_info(:inc_connected, socket) do
    {:noreply, assign(socket, nodes_connected: socket.assigns.nodes_connected + 1)}
  end

  @impl true
  def handle_info(msg, state) do
    # IO.puts("Catchall: #{inspect(msg)}")
    messages = state.assigns.messages ++ [msg]

    {:noreply,
     state
     |> assign(:messages, messages)
     |> assign(:message_cnt, Enum.count(messages))}
  end

  @impl true
  def handle_event("reset", _params, state) do
    {:noreply,
     state
     |> assign(:nodes, [])
     |> assign(:messages, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Gossip Network</h1>
      <h2>Nodes: {@nodes_connected}</h2>

      <div>PID: {inspect(self())}</div>

      <div>Msg cnt: {@message_cnt}</div>
      <!--<h3>Messages Received: {length(@messages)} {inspect(@messages)}</h3>-->
      <pre>{@graph}</pre>

      <.button phx-click="connect" class="btn">Connect</.button>
      <.button phx-click="send_msgs" class="btn">Send!</.button>
      <.button phx-click="reset" class="btn">Reset</.button>
    </div>
    """
  end

  defp create_nodes(count, pid, config) do
    1..count
    |> Enum.map(fn _ -> Task.async(fn -> Native.create_node(pid, config) end) end)
    |> Enum.map(&Task.await/1)
    |> Enum.filter(&is_reference/1)
  end

  defp send_messages(nodes) do
    once_random_node = Enum.random(nodes)

    Native.send_message(once_random_node, "MSG:init")

    Stream.map(1..@msg_cnt, fn x ->
      fn ->
        node = if @use_random_sender, do: Enum.random(nodes), else: once_random_node
        rand_msg_delay = :rand.uniform(@rand_msg_delay)
        Process.sleep(rand_msg_delay)
        Native.send_message(node, "MSG:#{x} rand_delay: #{rand_msg_delay}")
      end
    end)
    |> Task.async_stream(fn action -> action.() end, max_concurrency: Enum.count(nodes))
    |> Enum.to_list()
  end
end

defmodule GossipParser do
  def parse_gossip_messages(messages) do
    Enum.reduce(messages, %{nodes: %{}}, fn
      {:iroh_gossip_neighbor_up, source, discovered}, acc ->
        update_in(acc, [:nodes, source], fn
          nil -> %{peers: [discovered], messages: [], msg_count: 0}
          node -> %{node | peers: [discovered | node.peers || []]}
        end)

      {:iroh_gossip_message_received, source, msg}, acc ->
        update_in(acc, [:nodes, source], fn
          nil ->
            %{peers: [], messages: [msg], msg_count: 1}

          node ->
            %{node | messages: [msg | node.messages || []], msg_count: (node.msg_count || 0) + 1}
        end)

      _other, acc ->
        acc
    end)
  end

  def map_put(data, keys, value) do
    # data = %{} or non empty map
    # keys = [:a, :b, :c]
    # value = 3
    put_in(data, Enum.map(keys, &Access.key(&1, %{})), value)
  end

  def many_map_puts(data, keys_values) do
    # data = %{} or non empty map
    # keys_values = [[keys: [:a, :b, :c], value: 4],[keys: [:z, :y, :x], value: 90]]
    Enum.reduce(keys_values, data, fn x, data ->
      map_put(data, x[:keys], x[:value])
    end)
  end
end

defmodule MermaidGenerator do
  def generate_mermaid_graph(node_data) do
    nodes_string =
      node_data.nodes
      |> Enum.map(fn {node_id, node_info} ->
        # Default to empty list if missing
        messages = Map.get(node_info, :messages, [])

        message_string =
          messages
          |> Enum.with_index()
          # Concise msg info
          |> Enum.map(fn {msg, index} -> "M#{index + 1}: #{msg}" end)
          |> Enum.join("<br>")

        """
        #{node_id}("#{node_id}<br>Msgs: #{Enum.count(messages)}<br>#{message_string}"):::node
        """
      end)
      |> Enum.join("\n")

    connections_string =
      node_data.nodes
      |> Enum.flat_map(fn {source_id, source_info} ->
        Enum.map(source_info.peers, fn target_id ->
          """
          #{source_id} --> #{target_id}
          """
        end)
      end)
      # Remove duplicate connections
      |> Enum.uniq()
      |> Enum.join("\n")

    style_string =
      node_data.nodes
      |> Enum.with_index()
      |> Enum.map(fn {{node_id, _node_info}, index} ->
        colors = [
          "#6495ED",
          "#8FBC8F",
          "#D2691E",
          "#800080",
          "#4682B4",
          "#A0522D",
          "#008080",
          "#BC8F8F",
          "#2F4F4F",
          "#556B2F"
        ]

        color = Enum.at(colors, rem(index, length(colors)))

        """
        style #{node_id} fill:#{color},color:#fff,stroke:#333,stroke-width:2px
        """
      end)
      |> Enum.join("\n")

    """
    graph LR
        classDef node fill:#f9f,stroke:#333,stroke-width:2px,color:#000;

        subgraph Cluster
        direction TB
        #{nodes_string}
        end
        #{connections_string}
        #{style_string}
    """
  end

  def generate_mermaid_sequence(node_data) do
    lifelines =
      node_data.nodes
      |> Enum.map(fn {node_id, _node_info} ->
        """
        participant #{node_id}
        """
      end)
      |> Enum.join("\n")

    messages_string =
      node_data.nodes
      |> Enum.flat_map(fn {source_id, node_info} ->
        messages = Map.get(node_info, :messages, [])

        messages
        |> Enum.with_index()
        |> Enum.map(fn {msg, index} ->
          """
          #{source_id}->>CentralAuth: M#{index + 1}: #{msg}
          activate CentralAuth
          deactivate CentralAuth
          """

          # You may want to infer target from message itself
        end)
      end)
      |> Enum.join("\n")

    """
    sequenceDiagram
    title Message Flow

    #{lifelines}
    participant CentralAuth

    #{messages_string}
    """
  end
end
