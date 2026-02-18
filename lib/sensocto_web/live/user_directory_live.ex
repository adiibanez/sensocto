defmodule SensoctoWeb.UserDirectoryLive do
  use SensoctoWeb, :live_view

  alias Sensocto.Accounts.User

  on_mount {SensoctoWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    users = load_users()

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:current_path, "/users")
     |> assign(:users, users)
     |> assign(:search, "")}
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
end
