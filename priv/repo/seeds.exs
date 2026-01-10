# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sensocto.Repo.insert!(%Sensocto.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Sensocto.Repo
alias Sensocto.Media.Playlist
alias Sensocto.Media.PlaylistItem
import Ecto.Query

# Seed the lobby playlist with default videos
# This is idempotent - it will only create the lobby playlist if it doesn't exist

lobby_playlist =
  case Repo.one(from p in Playlist, where: p.is_lobby == true) do
    nil ->
      %Playlist{}
      |> Playlist.lobby_changeset(%{name: "Lobby Playlist"})
      |> Repo.insert!()
      |> tap(fn _ -> IO.puts("Created lobby playlist") end)

    existing ->
      IO.puts("Lobby playlist already exists")
      existing
  end

# Lobby playlist seed data - curated music videos
lobby_videos = [
  %{
    youtube_url: "https://www.youtube.com/watch?v=B7dAPZ8Qu0Q",
    youtube_video_id: "B7dAPZ8Qu0Q",
    title: "Barcelona Gipsy balKan Orchestra Live in Apolo 2019 - Sandra Sangiao Last Concert",
    thumbnail_url: "https://img.youtube.com/vi/B7dAPZ8Qu0Q/hqdefault.jpg",
    position: 0
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=xbIePmGzjz4",
    youtube_video_id: "xbIePmGzjz4",
    title: "Bob marley ge kaala manna - Dinba music by Shiuz & ishaantey",
    thumbnail_url: "https://img.youtube.com/vi/xbIePmGzjz4/hqdefault.jpg",
    position: 1
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=UrOxCPIUsyw",
    youtube_video_id: "UrOxCPIUsyw",
    title: "Taraf De Haïdouks, Balkan Romani Music",
    thumbnail_url: "https://img.youtube.com/vi/UrOxCPIUsyw/hqdefault.jpg",
    position: 2
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=mFSRCG4DrmI",
    youtube_video_id: "mFSRCG4DrmI",
    title: "Newen Afrobeat feat. Seun Kuti & Cheick Tidiane Seck - Opposite People (Fela Kuti)",
    thumbnail_url: "https://img.youtube.com/vi/mFSRCG4DrmI/hqdefault.jpg",
    position: 3
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=8Pa9x9fZBtY",
    youtube_video_id: "8Pa9x9fZBtY",
    title: "Dire Straits - Sultans Of Swing (Alchemy Live)",
    thumbnail_url: "https://img.youtube.com/vi/8Pa9x9fZBtY/hqdefault.jpg",
    position: 4
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=bLkfzVSp49c",
    youtube_video_id: "bLkfzVSp49c",
    title: "Bob Marley & The Wailers - Live at the Rainbow (Full Concert)",
    thumbnail_url: "https://img.youtube.com/vi/bLkfzVSp49c/hqdefault.jpg",
    position: 5
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=WgqaxMOKfnI",
    youtube_video_id: "WgqaxMOKfnI",
    title: "Billy Strings: Tiny Desk Concert",
    thumbnail_url: "https://img.youtube.com/vi/WgqaxMOKfnI/hqdefault.jpg",
    position: 6
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=tUApO77uUUk",
    youtube_video_id: "tUApO77uUUk",
    title: "Cypress Hill: Tiny Desk Concert",
    thumbnail_url: "https://img.youtube.com/vi/tUApO77uUUk/hqdefault.jpg",
    position: 7
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=CUN8pdgA0m8",
    youtube_video_id: "CUN8pdgA0m8",
    title: "Action Bronson: Tiny Desk Concert",
    thumbnail_url: "https://img.youtube.com/vi/CUN8pdgA0m8/hqdefault.jpg",
    position: 8
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=wTqCthvtL8k",
    youtube_video_id: "wTqCthvtL8k",
    title: "Hermanos Gutiérrez: Tiny Desk Concert",
    thumbnail_url: "https://img.youtube.com/vi/wTqCthvtL8k/hqdefault.jpg",
    position: 9
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=aYjjDeFvGjs",
    youtube_video_id: "aYjjDeFvGjs",
    title: "Mad Caddies - Mary Melody - Live in Eindhoven - 13 Nov 2023 - 2CAM - 4K",
    thumbnail_url: "https://img.youtube.com/vi/aYjjDeFvGjs/hqdefault.jpg",
    position: 10
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=o6J1pdwZ3sc",
    youtube_video_id: "o6J1pdwZ3sc",
    title: "Mahala Rai Banda @ Iboga Summer Festival 2013 (Xàbia)",
    thumbnail_url: "https://img.youtube.com/vi/o6J1pdwZ3sc/hqdefault.jpg",
    position: 11
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=FssULNGSZIA",
    youtube_video_id: "FssULNGSZIA",
    title: "Danny Carey | \"Pneuma\" by Tool (LIVE IN CONCERT)",
    thumbnail_url: "https://img.youtube.com/vi/FssULNGSZIA/hqdefault.jpg",
    position: 12
  },
  %{
    youtube_url: "https://www.youtube.com/watch?v=bdneye4pzMw",
    youtube_video_id: "bdneye4pzMw",
    title: "Sting And Shaggy: NPR Music Tiny Desk Concert",
    thumbnail_url: "https://img.youtube.com/vi/bdneye4pzMw/hqdefault.jpg",
    position: 13
  }
]

# Get existing video IDs for the lobby playlist
existing_video_ids =
  Repo.all(
    from pi in PlaylistItem,
      where: pi.playlist_id == ^lobby_playlist.id,
      select: pi.youtube_video_id
  )
  |> MapSet.new()

# Insert only new videos
Enum.each(lobby_videos, fn video ->
  if video.youtube_video_id not in existing_video_ids do
    %PlaylistItem{}
    |> PlaylistItem.changeset(Map.put(video, :playlist_id, lobby_playlist.id))
    |> Repo.insert!()

    IO.puts("Added: #{video.title}")
  else
    IO.puts("Skipped (already exists): #{video.title}")
  end
end)

IO.puts("\nLobby playlist seeding complete!")
