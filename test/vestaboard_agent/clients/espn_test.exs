defmodule VestaboardAgent.Clients.ESPNTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Clients.ESPN

  defp plug, do: {Req.Test, __MODULE__}

  defp stub(body), do: Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, body) end)

  defp stub_status(status),
    do: Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, status, "") end)

  defp game_fixture(overrides \\ %{}) do
    base = %{
      "events" => [
        %{
          "id" => "abc123",
          "competitions" => [
            %{
              "date" => "2026-04-25T23:30:00Z",
              "status" => %{
                "type" => %{"name" => "STATUS_IN_PROGRESS"},
                "displayClock" => "4:32",
                "period" => 3
              },
              "competitors" => [
                %{
                  "homeAway" => "home",
                  "team" => %{"abbreviation" => "KC", "displayName" => "Kansas City Chiefs"},
                  "score" => "27"
                },
                %{
                  "homeAway" => "away",
                  "team" => %{"abbreviation" => "BUF", "displayName" => "Buffalo Bills"},
                  "score" => "24"
                }
              ]
            }
          ]
        }
      ]
    }

    Map.merge(base, overrides)
  end

  defp set_status(body, status_name) do
    put_in(
      body,
      ["events", Access.at(0), "competitions", Access.at(0), "status", "type", "name"],
      status_name
    )
  end

  test "returns a list of games on 200" do
    stub(game_fixture())
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.id == "abc123"
  end

  test "parses home and away teams" do
    stub(game_fixture())
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.home.abbrev == "KC"
    assert game.away.abbrev == "BUF"
  end

  test "parses scores as integers" do
    stub(game_fixture())
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.home.score == 27
    assert game.away.score == 24
  end

  test "parses clock and period" do
    stub(game_fixture())
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.clock == "4:32"
    assert game.period == 3
  end

  test "STATUS_IN_PROGRESS maps to :in_progress" do
    stub(game_fixture())
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.status == :in_progress
  end

  test "STATUS_FINAL maps to :final" do
    stub(game_fixture() |> set_status("STATUS_FINAL"))
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.status == :final
  end

  test "unknown status maps to :scheduled" do
    stub(game_fixture() |> set_status("STATUS_SCHEDULED"))
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.status == :scheduled
  end

  test "games sorted in-progress first, then scheduled, then final" do
    body = %{
      "events" => [
        game_fixture()["events"]
        |> hd()
        |> put_in(["id"], "final")
        |> put_in(["competitions", Access.at(0), "status", "type", "name"], "STATUS_FINAL"),
        game_fixture()["events"]
        |> hd()
        |> put_in(["id"], "live")
        |> put_in(["competitions", Access.at(0), "status", "type", "name"], "STATUS_IN_PROGRESS"),
        game_fixture()["events"]
        |> hd()
        |> put_in(["id"], "sched")
        |> put_in(["competitions", Access.at(0), "status", "type", "name"], "STATUS_SCHEDULED")
      ]
    }

    stub(body)
    assert {:ok, [g1, g2, g3]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert g1.id == "live"
    assert g2.id == "sched"
    assert g3.id == "final"
  end

  test "returns empty list when events is empty" do
    stub(%{"events" => []})
    assert {:ok, []} = ESPN.scoreboard("football", "nfl", plug: plug())
  end

  test "returns {:error, {:http, status}} on non-200" do
    stub_status(404)
    assert {:error, {:http, 404}} = ESPN.scoreboard("football", "nfl", plug: plug())
  end

  test "handles missing score gracefully" do
    body =
      put_in(
        game_fixture(),
        [
          "events",
          Access.at(0),
          "competitions",
          Access.at(0),
          "competitors",
          Access.at(0),
          "score"
        ],
        nil
      )

    stub(body)
    assert {:ok, [game]} = ESPN.scoreboard("football", "nfl", plug: plug())
    assert game.home.score == nil
  end

  test "passes dates param when provided" do
    Req.Test.stub(__MODULE__, fn conn ->
      query = URI.decode_query(conn.query_string)
      assert query["dates"] == "20260426"
      Req.Test.json(conn, game_fixture())
    end)

    assert {:ok, _} = ESPN.scoreboard("football", "nfl", plug: plug(), dates: "20260426")
  end

  describe "upcoming_game/4" do
    test "returns {:ok, game} when team found on a future date" do
      today_str = Date.utc_today() |> Date.to_string() |> String.replace("-", "")

      Req.Test.stub(__MODULE__, fn conn ->
        query = URI.decode_query(conn.query_string)

        if query["dates"] == today_str do
          Req.Test.json(conn, %{"events" => []})
        else
          Req.Test.json(conn, game_fixture())
        end
      end)

      assert {:ok, game} = ESPN.upcoming_game("football", "nfl", "KC", plug: plug())
      assert game.home.abbrev == "KC"
    end

    test "returns {:error, :not_found} when team absent throughout lookahead" do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"events" => []}) end)
      assert {:error, :not_found} = ESPN.upcoming_game("football", "nfl", "KC", [plug: plug()], 2)
    end

    test "returns first day that contains the team" do
      today_str = Date.utc_today() |> Date.to_string() |> String.replace("-", "")

      tomorrow_str =
        Date.utc_today() |> Date.add(1) |> Date.to_string() |> String.replace("-", "")

      Req.Test.stub(__MODULE__, fn conn ->
        query = URI.decode_query(conn.query_string)

        cond do
          query["dates"] == today_str -> Req.Test.json(conn, %{"events" => []})
          query["dates"] == tomorrow_str -> Req.Test.json(conn, game_fixture())
          true -> Req.Test.json(conn, %{"events" => []})
        end
      end)

      assert {:ok, game} = ESPN.upcoming_game("football", "nfl", "KC", [plug: plug()], 3)
      assert game.home.abbrev == "KC"
    end
  end
end
