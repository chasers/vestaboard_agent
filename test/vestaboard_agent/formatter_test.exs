defmodule VestaboardAgent.FormatterTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Formatter

  setup do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)
    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
    :ok
  end

  defp llm_opts(response_text) do
    [llm_opts: [plug: fn conn -> Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => response_text}]}) end]]
  end

  test "returns formatted text and border color from LLM" do
    opts = llm_opts(~s({"text": "HELLO WORLD", "border_color": "blue"}))
    assert {:ok, "HELLO WORLD", [border: "blue"]} = Formatter.format("hello world", opts)
  end

  test "returns text without border when border_color is missing" do
    opts = llm_opts(~s({"text": "HELLO"}))
    assert {:ok, "HELLO", []} = Formatter.format("hello", opts)
  end

  test "falls back to original text on LLM parse failure" do
    opts = llm_opts("not json at all")
    assert {:ok, "hello", []} = Formatter.format("hello", opts)
  end

  test "falls back to original text on invalid border color" do
    opts = llm_opts(~s({"text": "HI", "border_color": "purple"}))
    assert {:ok, "HI", []} = Formatter.format("hi", opts)
  end

  test "falls back gracefully on HTTP error" do
    opts = [llm_opts: [plug: fn conn -> Plug.Conn.send_resp(conn, 500, "") end]]
    assert {:ok, "hello", []} = Formatter.format("hello", opts)
  end

  test "falls back when no API key configured" do
    Application.put_env(:vestaboard_agent, :llm, api_key: nil)
    System.delete_env("ANTHROPIC_API_KEY")
    assert {:ok, "hello", []} = Formatter.format("hello")
  end

  test "strips JSON markdown fences from LLM response" do
    fenced = "```json\n{\"text\": \"OK\", \"border_color\": \"green\"}\n```"
    opts = llm_opts(fenced)
    assert {:ok, "OK", [border: "green"]} = Formatter.format("ok", opts)
  end

  describe "history-aware formatting" do
    test "includes history in LLM prompt when provided" do
      parent = self()

      opts = [
        history: [%{prompt: "show weather", text: "SUNNY 72F", render_opts: [border: "blue"]}],
        llm_opts: [
          plug: fn conn ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            prompt_text = get_in(decoded, ["messages", Access.at(0), "content"])
            send(parent, {:prompt, prompt_text})
            Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => ~s({"text": "SUNNY", "border_color": "orange"})}]})
          end
        ]
      ]

      assert {:ok, "SUNNY", [border: "orange"]} = Formatter.format("make it orange", opts)

      assert_receive {:prompt, prompt_text}
      assert String.contains?(prompt_text, "show weather")
      assert String.contains?(prompt_text, "SUNNY 72F")
    end

    test "works without history (no history key)" do
      opts = llm_opts(~s({"text": "HELLO", "border_color": "red"}))
      assert {:ok, "HELLO", [border: "red"]} = Formatter.format("hello", opts)
    end
  end
end
