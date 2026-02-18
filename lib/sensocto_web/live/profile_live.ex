defmodule SensoctoWeb.ProfileLive do
  use SensoctoWeb, :live_view
  require Logger
  require Ash.Query

  alias Sensocto.Accounts.UserSkill

  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Map.get(user, :is_guest) do
      {:ok, push_navigate(socket, to: ~p"/settings")}
    else
      skills = load_skills(user.id)

      form =
        to_form(%{
          "display_name" => user.display_name || "",
          "bio" => user.bio || "",
          "status_emoji" => user.status_emoji || "",
          "timezone" => user.timezone || "Europe/Berlin",
          "is_public" => user.is_public
        })

      {:ok,
       socket
       |> assign(:page_title, "Profile")
       |> assign(:current_path, "/profile")
       |> assign(:user, user)
       |> assign(:skills, skills)
       |> assign(:form, form)
       |> assign(:skill_form, to_form(%{"skill_name" => "", "level" => "beginner"}))
       |> assign(:saved, false)}
    end
  end

  @impl true
  def handle_event("validate", %{"display_name" => _} = params, socket) do
    form =
      to_form(%{
        "display_name" => params["display_name"] || "",
        "bio" => params["bio"] || "",
        "status_emoji" => params["status_emoji"] || "",
        "timezone" => params["timezone"] || "Europe/Berlin",
        "is_public" => Map.has_key?(params, "is_public")
      })

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_profile", params, socket) do
    user = socket.assigns.user

    attrs = %{
      display_name: blank_to_nil(params["display_name"]),
      bio: blank_to_nil(params["bio"]),
      status_emoji: blank_to_nil(params["status_emoji"]),
      timezone: params["timezone"],
      is_public: Map.has_key?(params, "is_public")
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

  defp load_skills(user_id) do
    UserSkill
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> Enum.sort_by(& &1.skill_name)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val
end
