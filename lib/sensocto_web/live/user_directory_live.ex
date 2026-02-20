defmodule SensoctoWeb.UserDirectoryLive do
  use SensoctoWeb, :live_view
  require Ash.Query

  alias Sensocto.Accounts.{User, UserSkill, UserConnection}

  on_mount {SensoctoWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    users = load_users()

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:users, users)
     |> assign(:search, "")
     |> assign(:graph_users, [])
     |> assign(:graph_connections, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    action = socket.assigns.live_action

    socket =
      socket
      |> assign(:current_path, if(action == :graph, do: "/users/graph", else: "/users"))
      |> assign(:page_title, if(action == :graph, do: "User Graph", else: "Users"))

    socket =
      if action == :graph do
        {graph_users, graph_connections} = load_graph_data()
        assign(socket, graph_users: graph_users, graph_connections: graph_connections)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    users = load_users(query)
    {:noreply, assign(socket, users: users, search: query)}
  end

  defp load_users(query \\ "") do
    users = Ash.read!(User, action: :list_public, authorize?: false)

    if query == "" do
      users
    else
      q = String.downcase(query)

      Enum.filter(users, fn user ->
        name = String.downcase(user.display_name || "")
        email = String.downcase(to_string(user.email))
        String.contains?(name, q) or String.contains?(email, q)
      end)
    end
    |> Enum.sort_by(fn u -> u.display_name || to_string(u.email) end)
  end

  defp load_graph_data do
    users =
      User
      |> Ash.Query.filter(is_public == true and not is_nil(confirmed_at))
      |> Ash.read!(authorize?: false)

    all_skills = Ash.read!(UserSkill, authorize?: false)
    skills_by_user = Enum.group_by(all_skills, & &1.user_id)

    graph_users =
      Enum.map(users, fn user ->
        user_skills =
          (skills_by_user[user.id] || [])
          |> Enum.map(fn s -> %{skill_name: s.skill_name, level: to_string(s.level)} end)

        %{
          id: user.id,
          display_name: user.display_name || String.split(to_string(user.email), "@") |> hd(),
          email: to_string(user.email),
          bio: user.bio,
          status_emoji: user.status_emoji,
          skills: user_skills
        }
      end)

    connections =
      UserConnection
      |> Ash.read!(authorize?: false)
      |> Enum.map(fn c ->
        %{
          id: c.id,
          from_user_id: c.from_user_id,
          to_user_id: c.to_user_id,
          connection_type: to_string(c.connection_type),
          strength: c.strength
        }
      end)

    {graph_users, connections}
  end
end
