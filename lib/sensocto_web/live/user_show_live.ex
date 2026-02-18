defmodule SensoctoWeb.UserShowLive do
  use SensoctoWeb, :live_view
  require Ash.Query

  alias Sensocto.Accounts.User
  alias Sensocto.Accounts.UserSkill

  on_mount {SensoctoWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"id" => user_id}, _session, socket) do
    case Ash.get(User, user_id, authorize?: false) do
      {:ok, user} ->
        if user.is_public do
          skills = load_skills(user.id)

          {:ok,
           socket
           |> assign(:page_title, display_name(user))
           |> assign(:current_path, "/users/#{user.id}")
           |> assign(:user, user)
           |> assign(:skills, skills)}
        else
          {:ok,
           socket
           |> put_flash(:error, "This profile is private")
           |> push_navigate(to: ~p"/users")}
        end

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> push_navigate(to: ~p"/users")}
    end
  end

  defp load_skills(user_id) do
    UserSkill
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> Enum.sort_by(& &1.skill_name)
  end

  defp display_name(user) do
    user.display_name || String.split(to_string(user.email), "@") |> hd()
  end
end
