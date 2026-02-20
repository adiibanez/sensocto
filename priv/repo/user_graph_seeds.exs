# Seeds for User Graph POC
# Run with: mix run priv/repo/user_graph_seeds.exs

alias Sensocto.Accounts.{User, UserSkill, UserConnection}

# Display names for existing users
display_names = %{
  "adrianibanez99@gmail.com" => "Adrian Ibanez",
  "adi.ibanez@freestyleair.com" => "Adi (FreestyleAir)",
  "adi.ibanez@test.com" => "Adi Test",
  "test@example.com" => "Eva Mueller",
  "test.user@test.com" => "Jonas Schmidt",
  "testlitest@test.com" => "Mira Kovacs",
  "testlitest.test@test.com" => "Luca Bernini",
  "test@test.com" => "Sophie Chen",
  "test2.test@test.com" => "Kai Nakamura",
  "osx_edge@test.com" => "Nora Eriksson",
  "hoi.du@test.com" => "Felix Huber",
  "hoi.dui@urchig.ch" => "Lea Brunner",
  "lustiges.kerlchen@hoi.dui" => "Marco Rossi"
}

bios = %{
  "Adrian Ibanez" => "Platform architect. Sensors, sound, and systems.",
  "Adi (FreestyleAir)" => "Aerial sports & sensor integration.",
  "Eva Mueller" => "Neuroscience researcher. Brain-body interfaces.",
  "Jonas Schmidt" => "Full-stack dev. Phoenix & Svelte enthusiast.",
  "Mira Kovacs" => "UX designer focused on biofeedback experiences.",
  "Luca Bernini" => "IoT hardware engineer. Wearable prototypes.",
  "Sophie Chen" => "Data scientist. Real-time signal processing.",
  "Kai Nakamura" => "Sound designer. Generative audio from biosignals.",
  "Nora Eriksson" => "DevOps & infrastructure. Edge computing.",
  "Felix Huber" => "Movement science. Biomechanics & motion capture.",
  "Lea Brunner" => "Breathing coach. Wellness tech integration.",
  "Marco Rossi" => "Creative coder. Visualizations & interactive art."
}

emojis = ["🧠", "🎵", "🔬", "💻", "🎨", "🔧", "📊", "🎶", "☁️", "🏃", "🌬️", "🎭"]

skill_pool = [
  "elixir",
  "phoenix",
  "svelte",
  "rust",
  "python",
  "iot",
  "webmidi",
  "neuroscience",
  "ux",
  "devops",
  "signal-processing",
  "machine-learning",
  "breathing-science",
  "biomechanics",
  "creative-coding"
]

levels = [:beginner, :intermediate, :expert]

# Update users with display names, bios, emojis
users = Ash.read!(User, authorize?: false)

user_map =
  for user <- users, into: %{} do
    email_str = to_string(user.email)
    name = Map.get(display_names, email_str)

    if name do
      bio = Map.get(bios, name)
      emoji_idx = rem(:erlang.phash2(name), length(emojis))
      emoji = Enum.at(emojis, emoji_idx)

      user
      |> Ash.Changeset.for_update(
        :update_profile,
        %{display_name: name, bio: bio, status_emoji: emoji}, authorize?: false)
      |> Ash.update!(authorize?: false)

      {user.id, name}
    else
      {user.id, email_str}
    end
  end

user_ids = Map.keys(user_map)
IO.puts("Updated #{length(user_ids)} users with profiles")

# Seed skills (3-5 per user) using Ash.Seed
:rand.seed(:exsss, {42, 42, 42})

# Clear existing skills first
Sensocto.Repo.query!("DELETE FROM user_skills")

for user_id <- user_ids do
  skill_count = Enum.random(3..5)
  selected_skills = Enum.take_random(skill_pool, skill_count)

  for skill <- selected_skills do
    level = Enum.random(levels)

    try do
      Ash.Seed.seed!(UserSkill, %{
        user_id: user_id,
        skill_name: skill,
        level: level
      })
    rescue
      _ -> :ok
    end
  end
end

skill_count = length(Ash.read!(UserSkill, authorize?: false))
IO.puts("Created #{skill_count} skills")

# Seed connections using Ash.Seed
connection_types = [:follows, :collaborates, :mentors]

# Clear existing connections first
Sensocto.Repo.query!("DELETE FROM user_connections")

connections_created =
  for from_id <- user_ids, reduce: 0 do
    acc ->
      others = Enum.reject(user_ids, &(&1 == from_id))
      target_count = Enum.random(2..4)
      targets = Enum.take_random(others, target_count)

      created =
        for to_id <- targets, reduce: 0 do
          inner_acc ->
            type = Enum.random(connection_types)
            strength = Enum.random(3..9)

            try do
              Ash.Seed.seed!(UserConnection, %{
                from_user_id: from_id,
                to_user_id: to_id,
                connection_type: type,
                strength: strength
              })

              inner_acc + 1
            rescue
              _ -> inner_acc
            end
        end

      acc + created
  end

IO.puts("Created #{connections_created} connections")
IO.puts("Done! Run the app and visit /users/graph")
