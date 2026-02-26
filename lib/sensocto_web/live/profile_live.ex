defmodule SensoctoWeb.ProfileLive do
  use SensoctoWeb, :live_view
  require Logger
  require Ash.Query

  alias Sensocto.Accounts.{User, UserSkill, UserConnection}

  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @connection_types [:follows, :collaborates, :mentors]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Map.get(user, :is_guest) do
      {:ok, push_navigate(socket, to: ~p"/settings")}
    else
      skills = load_skills(user.id)
      {connections, all_users, graph_users, graph_connections} = load_connection_data(user)

      form =
        to_form(%{
          "display_name" => user.display_name || "",
          "bio" => user.bio || "",
          "status_emoji" => user.status_emoji || "",
          "timezone" => user.timezone || "Europe/Berlin"
        })

      {:ok,
       socket
       |> assign(:page_title, "Profile")
       |> assign(:current_path, "/profile")
       |> assign(:user, user)
       |> assign(:skills, skills)
       |> assign(:form, form)
       |> assign(:skill_form, to_form(%{"skill_name" => "", "level" => "beginner"}))
       |> assign(:saved, false)
       |> assign(:connections, connections)
       |> assign(:all_users, all_users)
       |> assign(:graph_users, graph_users)
       |> assign(:graph_connections, graph_connections)
       |> assign(:connection_types, @connection_types)
       |> assign(:user_search, "")
       |> assign(:user_search_results, [])
       |> assign(:selected_user_id, nil)
       |> assign(:selected_user, nil)
       |> assign(:show_user_dropdown, false)}
    end
  end

  @impl true
  def handle_event("validate", %{"display_name" => _} = params, socket) do
    form =
      to_form(%{
        "display_name" => params["display_name"] || "",
        "bio" => params["bio"] || "",
        "status_emoji" => params["status_emoji"] || "",
        "timezone" => params["timezone"] || "Europe/Berlin"
      })

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_profile", params, socket) do
    user = socket.assigns.user

    attrs = %{
      display_name: blank_to_nil(params["display_name"]),
      bio: blank_to_nil(params["bio"]),
      status_emoji: blank_to_nil(params["status_emoji"]),
      timezone: params["timezone"]
    }

    case user
         |> Ash.Changeset.for_update(:update_profile, attrs, actor: user)
         |> Ash.update() do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:saved, true)
         |> put_flash(:info, "Profile updated")}

      {:error, error} ->
        Logger.warning("Profile update failed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to update profile")}
    end
  end

  def handle_event("add_skill", %{"skill_name" => name, "level" => level}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, socket}
    else
      case UserSkill
           |> Ash.Changeset.for_create(:add_skill, %{
             user_id: socket.assigns.user.id,
             skill_name: name,
             level: String.to_existing_atom(level)
           })
           |> Ash.create(authorize?: false) do
        {:ok, _skill} ->
          skills = load_skills(socket.assigns.user.id)

          {:noreply,
           socket
           |> assign(:skills, skills)
           |> assign(:skill_form, to_form(%{"skill_name" => "", "level" => "beginner"}))}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, "Skill already exists or invalid")}
      end
    end
  end

  def handle_event("remove_skill", %{"id" => skill_id}, socket) do
    case Ash.get(UserSkill, skill_id, authorize?: false) do
      {:ok, skill} ->
        Ash.destroy!(skill, authorize?: false)
        skills = load_skills(socket.assigns.user.id)
        {:noreply, assign(socket, :skills, skills)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("search_users", %{"user_search" => query}, socket) do
    query = String.trim(query)

    # If a user is already selected and the query is cleared (e.g. blur), preserve the selection
    if query == "" and not is_nil(socket.assigns.selected_user_id) do
      {:noreply, assign(socket, :show_user_dropdown, false)}
    else
      q = String.downcase(query)

      results =
        if q == "" do
          []
        else
          socket.assigns.all_users
          |> Enum.filter(fn u ->
            name = String.downcase(u.display_name || "")
            email = String.downcase(to_string(u.email))
            String.contains?(name, q) or String.contains?(email, q)
          end)
          |> Enum.take(8)
        end

      {:noreply,
       socket
       |> assign(:user_search, query)
       |> assign(:user_search_results, results)
       |> assign(:show_user_dropdown, results != [])
       |> assign(:selected_user_id, nil)
       |> assign(:selected_user, nil)}
    end
  end

  def handle_event("select_user", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.all_users, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_user_id, id)
     |> assign(:selected_user, user)
     |> assign(:user_search, (user && (user.display_name || to_string(user.email))) || "")
     |> assign(:user_search_results, [])
     |> assign(:show_user_dropdown, false)}
  end

  def handle_event("clear_user_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])
     |> assign(:selected_user_id, nil)
     |> assign(:selected_user, nil)
     |> assign(:show_user_dropdown, false)}
  end

  def handle_event(
        "add_connection",
        %{"to_user_id" => to_user_id, "connection_type" => type},
        socket
      ) do
    user = socket.assigns.user

    if to_user_id == "" or to_user_id == user.id do
      {:noreply, socket}
    else
      conn_type = safe_atom(type, :follows)

      case UserConnection
           |> Ash.Changeset.for_create(
             :create,
             %{connection_type: conn_type, from_user_id: user.id, to_user_id: to_user_id},
             authorize?: false
           )
           |> Ash.create() do
        {:ok, _conn} ->
          {connections, all_users, graph_users, graph_connections} =
            load_connection_data(user)

          {:noreply,
           socket
           |> assign(:connections, connections)
           |> assign(:all_users, all_users)
           |> assign(:graph_users, graph_users)
           |> assign(:graph_connections, graph_connections)
           |> assign(:user_search, "")
           |> assign(:user_search_results, [])
           |> assign(:selected_user_id, nil)
           |> assign(:selected_user, nil)
           |> assign(:show_user_dropdown, false)
           |> put_flash(:info, "Connection added")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Connection already exists")}
      end
    end
  end

  def handle_event("remove_connection", %{"id" => conn_id}, socket) do
    user = socket.assigns.user

    case Ash.get(UserConnection, conn_id, authorize?: false) do
      {:ok, conn} ->
        Ash.destroy!(conn, authorize?: false)
        {connections, all_users, graph_users, graph_connections} = load_connection_data(user)

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:all_users, all_users)
         |> assign(:graph_users, graph_users)
         |> assign(:graph_connections, graph_connections)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_connection", %{"id" => conn_id, "connection_type" => type}, socket) do
    user = socket.assigns.user
    conn_type = safe_atom(type, :follows)

    case Ash.get(UserConnection, conn_id, authorize?: false) do
      {:ok, conn} ->
        conn
        |> Ash.Changeset.for_update(:update, %{connection_type: conn_type}, authorize?: false)
        |> Ash.update!()

        {connections, all_users, graph_users, graph_connections} = load_connection_data(user)

        {:noreply,
         socket
         |> assign(:connections, connections)
         |> assign(:all_users, all_users)
         |> assign(:graph_users, graph_users)
         |> assign(:graph_connections, graph_connections)}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_skills(user_id) do
    UserSkill
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> Enum.sort_by(& &1.skill_name)
  end

  defp load_connection_data(user) do
    user_id = user.id

    connections =
      UserConnection
      |> Ash.Query.for_read(:for_user, %{user_id: user_id})
      |> Ash.read!(authorize?: false)

    # Collect all connected user IDs (both directions)
    connected_ids =
      connections
      |> Enum.flat_map(fn c -> [c.from_user_id, c.to_user_id] end)
      |> Enum.reject(&(&1 == user_id))
      |> Enum.uniq()

    # All public users for the "add connection" dropdown
    all_users =
      User
      |> Ash.Query.filter(is_public == true and id != ^user_id)
      |> Ash.read!(authorize?: false)
      |> Enum.sort_by(fn u -> u.display_name || to_string(u.email) end)

    # Build ego-graph: current user + all 1st-degree connected users
    graph_node_ids = [user_id | connected_ids]

    all_skills = Ash.read!(UserSkill, authorize?: false)
    skills_by_user = Enum.group_by(all_skills, & &1.user_id)

    graph_users =
      User
      |> Ash.Query.filter(id in ^graph_node_ids)
      |> Ash.read!(authorize?: false)
      |> Enum.map(fn u ->
        user_skills =
          (skills_by_user[u.id] || [])
          |> Enum.map(fn s -> %{skill_name: s.skill_name, level: to_string(s.level)} end)

        %{
          id: u.id,
          display_name: u.display_name || String.split(to_string(u.email), "@") |> hd(),
          email: to_string(u.email),
          bio: u.bio,
          status_emoji: u.status_emoji,
          skills: user_skills
        }
      end)

    graph_connections =
      Enum.map(connections, fn c ->
        %{
          id: c.id,
          from_user_id: c.from_user_id,
          to_user_id: c.to_user_id,
          connection_type: to_string(c.connection_type),
          strength: c.strength
        }
      end)

    {connections, all_users, graph_users, graph_connections}
  end

  defp safe_atom(str, default) when is_binary(str) do
    case str do
      "follows" -> :follows
      "collaborates" -> :collaborates
      "mentors" -> :mentors
      _ -> default
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val
end
