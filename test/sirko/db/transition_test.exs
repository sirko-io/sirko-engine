defmodule Sirko.Db.TransitionTest do
  use ExUnit.Case

  import Support.Neo4jHelpers

  alias Sirko.Db, as: Db

  setup do
    on_exit fn ->
      cleanup_db()
    end

    :ok
  end

  describe "track/1" do
    setup do
      session_keys = ["skey10", "skey11"]

      load_fixture("diverse_sessions")

      {:ok, [session_keys: session_keys]}
    end

    test "records transitions between pages", %{ session_keys: session_keys } do
      Db.Transition.track(session_keys)

      start_list = transition_between_pages({"start", true}, {"path", "/list"})

      assert start_list.properties["count"] == 2
      assert start_list.properties["updated_at"] != nil

      list_popular = transition_between_paths("/list", "/popular")

      assert list_popular.properties["count"] == 3
      assert list_popular.properties["updated_at"] != nil

      list_exit = transition_between_pages({"path", "/list"}, {"exit", true})

      assert list_exit.properties["count"] == 1
      assert list_exit.properties["updated_at"] != nil

      popular_exit = transition_between_pages({"path", "/popular"}, {"exit", true})

      assert popular_exit.properties["count"] == 1
      assert popular_exit.properties["updated_at"] != nil
    end

    test "increases counts for a transition when it exists", %{ session_keys: session_keys } do
      load_fixture("transitions")

      initial_transition = transition_between_paths("/list", "/popular")

      Db.Transition.track(session_keys)

      updated_transition = transition_between_paths("/list", "/popular")

      assert updated_transition.properties["count"] == 7
      assert updated_transition.properties["updated_at"] != initial_transition.properties["updated_at"]
    end

    test "does not affect transitions which does not belong to the found session", %{ session_keys: session_keys } do
      load_fixture("transitions")

      Db.Transition.track(session_keys)

      list_details = transition_between_paths("/list", "/details")
      about_popular = transition_between_paths("/about", "/popular")

      assert list_details.properties["count"] == 6
      assert about_popular.properties["count"] == 2
    end
  end

  describe "exclude_sessions/1" do
    setup do
      session_keys = ["skey1", "skey2"]

      load_fixture("diverse_sessions")
      load_fixture("transitions")

      {:ok, [session_keys: session_keys]}
    end

    test "decreases counts for transitions matching the corresponding sessions", %{ session_keys: session_keys } do
      initial_transition = transition_between_paths("/list", "/popular")

      assert initial_transition.properties["count"] == 4

      Db.Transition.exclude_sessions(session_keys)

      updated_transition = transition_between_paths("/list", "/popular")

      assert updated_transition.properties["count"] == 1
    end
  end

  describe "predict/1" do
    setup do
      load_fixture("transitions")

      :ok
    end

    test "returns a map containing info about the next page to be visited" do
      assert Db.Transition.predict("/list") == %{
        "total" => 14,
        "count" => 6,
        "path" => "/details"
      }
    end

    test "returns nil when the current page is unknown" do
      assert Db.Transition.predict("/settings") == nil
    end

    test "takes the path with the most fresh transitions when there are 2 paths with identical counts" do
      assert Db.Transition.predict("/about") == %{
        "total" => 4,
        "count" => 2,
        "path" => "/popular"
      }

    end
  end

  describe "remove_idle/0" do
    setup do
      load_fixture("transitions")

      :ok
    end

    test "removes idle transitions" do
      query = """
        MATCH ()-[t:TRANSITION]->()
        WHERE t.count = 0
        RETURN count(t) > 0 AS exist
      """

      [%{"exist" => exist}] = execute_query(query)

      assert exist == true

      Db.Transition.remove_idle()

      [%{"exist" => exist}] = execute_query(query)

      assert exist == false
    end
  end
end
