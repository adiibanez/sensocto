defmodule Sensocto.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :sensocto

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          seed_lobby_playlist(repo)
        end)
    end
  end

  defp seed_lobby_playlist(repo) do
    alias Sensocto.Media.Playlist
    alias Sensocto.Media.PlaylistItem
    import Ecto.Query

    # Create or get lobby playlist
    lobby =
      case repo.one(from(p in Playlist, where: p.is_lobby == true)) do
        nil ->
          repo.insert!(%Playlist{name: "Lobby Playlist", is_lobby: true})

        existing ->
          existing
      end

    IO.puts("Lobby playlist id: #{lobby.id}")

    # Seed videos
    videos = [
      {"B7dAPZ8Qu0Q", "Barcelona Gipsy balKan Orchestra Live"},
      {"xbIePmGzjz4", "Bob marley ge kaala manna"},
      {"UrOxCPIUsyw", "Taraf De Haidouks"},
      {"mFSRCG4DrmI", "Newen Afrobeat feat. Seun Kuti"},
      {"8Pa9x9fZBtY", "Dire Straits - Sultans Of Swing"},
      {"bLkfzVSp49c", "Bob Marley Live at Rainbow"},
      {"WgqaxMOKfnI", "Billy Strings Tiny Desk"},
      {"tUApO77uUUk", "Cypress Hill Tiny Desk"},
      {"CUN8pdgA0m8", "Action Bronson Tiny Desk"},
      {"wTqCthvtL8k", "Hermanos Gutierrez Tiny Desk"},
      {"aYjjDeFvGjs", "Mad Caddies Live"},
      {"o6J1pdwZ3sc", "Mahala Rai Banda"},
      {"FssULNGSZIA", "Danny Carey Pneuma"},
      {"bdneye4pzMw", "Sting And Shaggy Tiny Desk"}
    ]

    existing =
      repo.all(from(pi in PlaylistItem, where: pi.playlist_id == ^lobby.id, select: pi.youtube_video_id))
      |> MapSet.new()

    videos
    |> Enum.with_index()
    |> Enum.each(fn {{vid, title}, idx} ->
      unless MapSet.member?(existing, vid) do
        repo.insert!(%PlaylistItem{
          playlist_id: lobby.id,
          youtube_video_id: vid,
          youtube_url: "https://www.youtube.com/watch?v=#{vid}",
          title: title,
          thumbnail_url: "https://img.youtube.com/vi/#{vid}/hqdefault.jpg",
          position: idx
        })

        IO.puts("Added: #{title}")
      else
        IO.puts("Skipped (exists): #{title}")
      end
    end)

    IO.puts("Done seeding lobby playlist!")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
