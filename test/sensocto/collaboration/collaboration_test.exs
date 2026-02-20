defmodule Sensocto.CollaborationTest do
  @moduledoc """
  Tests for Collaboration domain resources: Poll, PollOption, Vote.
  """
  use Sensocto.DataCase, async: true
  require Ash.Query

  alias Sensocto.Accounts.User
  alias Sensocto.Collaboration.{Poll, PollOption, Vote}

  defp create_user do
    Ash.Seed.seed!(User, %{
      email: "collab_#{System.unique_integer([:positive])}@test.com",
      confirmed_at: DateTime.utc_now()
    })
  end

  defp create_poll(creator, attrs \\ %{}) do
    default = %{
      title: "Test Poll",
      poll_type: :single_choice,
      visibility: :public,
      results_visible: :always,
      status: :open,
      creator_id: creator.id
    }

    Ash.Seed.seed!(Poll, Map.merge(default, attrs))
  end

  defp create_option(poll, label, position \\ 0) do
    Ash.Seed.seed!(PollOption, %{
      poll_id: poll.id,
      label: label,
      position: position
    })
  end

  # ── Poll ──────────────────────────────────────────────────────────────

  describe "Poll" do
    test "creates a poll with required fields" do
      user = create_user()
      poll = create_poll(user, %{title: "Best language?"})

      assert poll.title == "Best language?"
      assert poll.poll_type == :single_choice
      assert poll.status == :open
      assert poll.creator_id == user.id
    end

    test "title is required" do
      user = create_user()

      assert_raise Ash.Error.Unknown, fn ->
        Ash.Seed.seed!(Poll, %{creator_id: user.id, title: nil})
      end
    end

    test "public_open returns only public open polls" do
      user = create_user()
      open = create_poll(user, %{title: "Open", visibility: :public, status: :open})
      _closed = create_poll(user, %{title: "Closed", visibility: :public, status: :closed})
      _private = create_poll(user, %{title: "Private", visibility: :private, status: :open})

      polls = Ash.read!(Poll, action: :public_open, authorize?: false)
      ids = Enum.map(polls, & &1.id)

      assert open.id in ids
    end

    test "by_creator returns polls for a specific user" do
      u1 = create_user()
      u2 = create_user()

      p1 = create_poll(u1)
      _p2 = create_poll(u2)

      polls =
        Poll
        |> Ash.Query.for_read(:by_creator, %{creator_id: u1.id})
        |> Ash.read!(authorize?: false)

      assert length(polls) == 1
      assert hd(polls).id == p1.id
    end

    test "vote_count aggregate works" do
      user = create_user()
      poll = create_poll(user)
      opt = create_option(poll, "Option A")

      Ash.Seed.seed!(Vote, %{
        poll_id: poll.id,
        option_id: opt.id,
        user_id: user.id
      })

      [reloaded] =
        Poll
        |> Ash.Query.for_read(:by_creator, %{creator_id: user.id})
        |> Ash.Query.load(:vote_count)
        |> Ash.read!(authorize?: false)

      assert reloaded.vote_count == 1
    end
  end

  # ── PollOption ────────────────────────────────────────────────────────

  describe "PollOption" do
    test "creates options with label and position" do
      user = create_user()
      poll = create_poll(user)

      opt = create_option(poll, "Yes", 0)
      assert opt.label == "Yes"
      assert opt.position == 0
      assert opt.poll_id == poll.id
    end

    test "vote_count aggregate on option" do
      user = create_user()
      poll = create_poll(user)
      opt = create_option(poll, "Elixir")

      Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt.id, user_id: user.id})

      opts = Ash.read!(PollOption, authorize?: false, load: [:vote_count])
      found = Enum.find(opts, &(&1.id == opt.id))
      assert found.vote_count == 1
    end
  end

  # ── Vote ──────────────────────────────────────────────────────────────

  describe "Vote" do
    test "creates a vote" do
      user = create_user()
      poll = create_poll(user)
      opt = create_option(poll, "Option")

      vote =
        Ash.Seed.seed!(Vote, %{
          poll_id: poll.id,
          option_id: opt.id,
          user_id: user.id
        })

      assert vote.poll_id == poll.id
      assert vote.option_id == opt.id
      assert vote.user_id == user.id
      assert vote.weight == 1
    end

    test "unique constraint prevents duplicate votes" do
      user = create_user()
      poll = create_poll(user)
      opt = create_option(poll, "Option")

      Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt.id, user_id: user.id})

      assert_raise Ash.Error.Unknown, fn ->
        Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt.id, user_id: user.id})
      end
    end

    test "different users can vote on same option" do
      u1 = create_user()
      u2 = create_user()
      poll = create_poll(u1)
      opt = create_option(poll, "Popular")

      v1 = Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt.id, user_id: u1.id})
      v2 = Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt.id, user_id: u2.id})

      assert v1.id != v2.id
    end

    test "user can vote on different options in same poll" do
      user = create_user()
      poll = create_poll(user, %{poll_type: :multiple_choice})
      opt1 = create_option(poll, "A", 0)
      opt2 = create_option(poll, "B", 1)

      v1 = Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt1.id, user_id: user.id})
      v2 = Ash.Seed.seed!(Vote, %{poll_id: poll.id, option_id: opt2.id, user_id: user.id})

      assert v1.id != v2.id
    end
  end
end
