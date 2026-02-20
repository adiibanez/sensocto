defmodule Sensocto.AccountsTest do
  @moduledoc """
  Tests for Accounts domain resources: User, UserSkill, UserConnection, GuestSession.
  """
  use Sensocto.DataCase, async: true
  require Ash.Query

  alias Sensocto.Accounts.{User, UserSkill, UserConnection, GuestSession}

  defp create_user(attrs \\ %{}) do
    default = %{
      email: "test_#{System.unique_integer([:positive])}@example.com",
      confirmed_at: DateTime.utc_now()
    }

    Ash.Seed.seed!(User, Map.merge(default, attrs))
  end

  # ── User ──────────────────────────────────────────────────────────────

  describe "User" do
    test "seed creates a user with required fields" do
      user = create_user()
      assert user.id
      assert user.email
    end

    test "list_public only returns public confirmed users" do
      public = create_user(%{is_public: true})
      _private = create_user(%{is_public: false})
      _unconfirmed = Ash.Seed.seed!(User, %{email: "unconf@test.com", confirmed_at: nil})

      users = Ash.read!(User, action: :list_public, authorize?: false)
      ids = Enum.map(users, & &1.id)

      assert public.id in ids
    end

    test "update_profile sets display_name, bio, status_emoji" do
      user = create_user()

      updated =
        user
        |> Ash.Changeset.for_update(
          :update_profile,
          %{display_name: "Test User", bio: "Hello", status_emoji: "🧠"},
          authorize?: false
        )
        |> Ash.update!(authorize?: false)

      assert updated.display_name == "Test User"
      assert updated.bio == "Hello"
      assert updated.status_emoji == "🧠"
    end

    test "update_profile rejects display_name over 50 chars" do
      user = create_user()
      long_name = String.duplicate("a", 51)

      assert {:error, _} =
               user
               |> Ash.Changeset.for_update(
                 :update_profile,
                 %{display_name: long_name},
                 authorize?: false
               )
               |> Ash.update(authorize?: false)
    end

    test "unique_email identity prevents duplicates" do
      email = "unique_#{System.unique_integer([:positive])}@test.com"
      create_user(%{email: email})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(User, %{email: email, confirmed_at: DateTime.utc_now()})
      end
    end

    test "get_by_email finds user by email" do
      user = create_user(%{email: "findme@test.com"})

      found =
        User
        |> Ash.Query.for_read(:get_by_email, %{email: "findme@test.com"})
        |> Ash.read_one!(authorize?: false)

      assert found.id == user.id
    end
  end

  # ── UserSkill ─────────────────────────────────────────────────────────

  describe "UserSkill" do
    test "seed creates a skill for a user" do
      user = create_user()

      skill =
        Ash.Seed.seed!(UserSkill, %{
          user_id: user.id,
          skill_name: "elixir",
          level: :intermediate
        })

      assert skill.skill_name == "elixir"
      assert skill.level == :intermediate
      assert skill.user_id == user.id
    end

    test "unique_user_skill prevents duplicate skill per user" do
      user = create_user()

      Ash.Seed.seed!(UserSkill, %{user_id: user.id, skill_name: "elixir", level: :beginner})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(UserSkill, %{user_id: user.id, skill_name: "elixir", level: :expert})
      end
    end

    test "level must be one of beginner, intermediate, expert" do
      user = create_user()

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(UserSkill, %{user_id: user.id, skill_name: "test", level: :master})
      end
    end

    test "different users can have same skill" do
      u1 = create_user()
      u2 = create_user()

      s1 = Ash.Seed.seed!(UserSkill, %{user_id: u1.id, skill_name: "svelte", level: :beginner})
      s2 = Ash.Seed.seed!(UserSkill, %{user_id: u2.id, skill_name: "svelte", level: :expert})

      assert s1.id != s2.id
    end
  end

  # ── UserConnection ────────────────────────────────────────────────────

  describe "UserConnection" do
    test "seed creates a connection between users" do
      u1 = create_user()
      u2 = create_user()

      conn =
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :collaborates,
          strength: 7
        })

      assert conn.from_user_id == u1.id
      assert conn.to_user_id == u2.id
      assert conn.connection_type == :collaborates
      assert conn.strength == 7
    end

    test "for_user returns connections involving a user" do
      u1 = create_user()
      u2 = create_user()
      u3 = create_user()

      Ash.Seed.seed!(UserConnection, %{
        from_user_id: u1.id,
        to_user_id: u2.id,
        connection_type: :follows
      })

      Ash.Seed.seed!(UserConnection, %{
        from_user_id: u3.id,
        to_user_id: u1.id,
        connection_type: :mentors
      })

      conns =
        UserConnection
        |> Ash.Query.for_read(:for_user, %{user_id: u1.id})
        |> Ash.read!(authorize?: false)

      assert length(conns) == 2
    end

    test "unique_connection prevents duplicate type between same users" do
      u1 = create_user()
      u2 = create_user()

      Ash.Seed.seed!(UserConnection, %{
        from_user_id: u1.id,
        to_user_id: u2.id,
        connection_type: :follows
      })

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :follows
        })
      end
    end

    test "same users can have different connection types" do
      u1 = create_user()
      u2 = create_user()

      c1 =
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :follows
        })

      c2 =
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :collaborates
        })

      assert c1.id != c2.id
    end

    test "strength defaults to 5" do
      u1 = create_user()
      u2 = create_user()

      conn =
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :follows
        })

      assert conn.strength == 5
    end

    test "strength must be between 1 and 10" do
      u1 = create_user()
      u2 = create_user()

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :follows,
          strength: 0
        })
      end

      assert_raise Ash.Error.Invalid, fn ->
        Ash.Seed.seed!(UserConnection, %{
          from_user_id: u1.id,
          to_user_id: u2.id,
          connection_type: :mentors,
          strength: 11
        })
      end
    end
  end

  # ── GuestSession ──────────────────────────────────────────────────────

  describe "GuestSession" do
    test "create and read back a guest session" do
      guest_id = "guest_#{System.unique_integer([:positive])}"

      session =
        Ash.Seed.seed!(GuestSession, %{
          id: guest_id,
          display_name: "Visitor",
          token: "tok_#{System.unique_integer([:positive])}"
        })

      assert session.id == guest_id
      assert session.display_name == "Visitor"
      assert session.last_active_at
    end

    test "by_id finds a guest session" do
      guest_id = "guest_#{System.unique_integer([:positive])}"

      Ash.Seed.seed!(GuestSession, %{
        id: guest_id,
        display_name: "FindMe",
        token: "tok_find"
      })

      found =
        GuestSession
        |> Ash.Query.for_read(:by_id, %{id: guest_id})
        |> Ash.read_one!(authorize?: false)

      assert found.display_name == "FindMe"
    end

    test "touch updates last_active_at" do
      guest_id = "guest_#{System.unique_integer([:positive])}"

      session =
        Ash.Seed.seed!(GuestSession, %{
          id: guest_id,
          display_name: "Touch",
          token: "tok_touch",
          last_active_at: ~U[2025-01-01 00:00:00Z]
        })

      updated =
        session
        |> Ash.Changeset.for_update(:touch, %{}, authorize?: false)
        |> Ash.update!(authorize?: false)

      assert DateTime.compare(updated.last_active_at, session.last_active_at) == :gt
    end
  end
end
