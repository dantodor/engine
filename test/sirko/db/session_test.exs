defmodule Sirko.Db.SessionTest do
  use ExUnit.Case

  doctest Sirko.Db.Session

  import Support.Neo4jHelpers

  alias Sirko.Db, as: Db

  setup do
    on_exit fn ->
      cleanup_db
    end

    :ok
  end

  describe "create/2" do
    test "creates a relation between the starting point and the given page" do
      session_key  = "skey1"
      current_path = "/popular"

      Db.Session.create(session_key, current_path)

      query = """
        MATCH (start:Page)-[session:SESSION { key: {key} }]->(current:Page)
        RETURN start, current, session
      """

      [%{
        "start"   => start_page,
        "current" => current_page,
        "session" => session
      }] = execute_query(query, %{ key: session_key })

      assert start_page["start"] == true
      assert current_page["path"] == current_path
      assert session["created_at"] != nil
    end

    test "does not create extra nodes when the page exists" do
      Db.Session.create("skey1", "/list")
      Db.Session.create("skey2", "/list")

      assert count_pages == 2
    end
  end

  describe "track/2" do
    setup do
      referral_path = "/popular"

      query = """
        CREATE (:Page { path: {path} })
      """

      execute_query(query, %{ path: referral_path })

      { :ok, [referral_path: referral_path] }
    end

    test "creates a relation between 2 pages", %{ referral_path: referral_path } do
      session_key = "skey1"
      current_path = "/list"

      Db.Session.track(session_key, referral_path, current_path)

      query = """
        MATCH (referral:Page)-[session:SESSION {key: {key} }]->(current:Page)
        RETURN referral, current, session
      """

      [%{
        "referral" => referral_page,
        "current"  => current_page,
        "session"  => session
      }] = execute_query(query, %{ key: session_key })

      assert referral_page["path"] == referral_path
      assert current_page["path"] == current_path
      assert session["created_at"] != nil
    end

    test "does not create extra nodes when the page exists", %{ referral_path: referral_path } do
      Db.Session.track("skey1", referral_path, "/list")
      Db.Session.track("skey2", referral_path, "/list")

      assert count_pages == 2
    end
  end

  describe "expire/1" do
    setup do
      session_key = "skey20"

      load_fixture("diverse_sessions")

      Db.Session.expire(session_key)

      { :ok, [session_key: session_key] }
    end

    test "creates a relation to the exit point", %{ session_key: session_key } do
      assert count_expired_session(session_key) == 1
    end

    test "does not affect foreign sessions" do
      assert count_expired_session("skey21") == 0
    end
  end

  describe "all_inactive/1" do
    setup do
      load_fixture("diverse_sessions")

      :ok
    end

    test "returns keys of sessions which are inactive for 1 hr" do
      session_keys = Db.Session.all_inactive(60 * 60 * 1000)

      assert session_keys == ["skey21", "skey20"]
    end
  end

  defp count_expired_session(session_key) do
    query = """
      MATCH (:Page { path: "/popular" })-[s:SESSION { key: {key} }]->(:Page { exit: true })
      RETURN count(s) AS count
    """

    [%{ "count" => count }] = execute_query(query, %{ key: session_key })

    count
  end

  defp count_pages do
    query = "MATCH (n:Page) RETURN count(n) AS nodes_count"

    [%{ "nodes_count" => count }] = execute_query(query)

    count
  end
end