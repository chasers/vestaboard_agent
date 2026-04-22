defmodule VestaboardAgent.Agents.ConversationalAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.ConversationalAgent

  describe "name/0 and keywords/0" do
    test "name is 'conversational'" do
      assert ConversationalAgent.name() == "conversational"
    end

    test "keywords is empty (LLM-routed only)" do
      assert ConversationalAgent.keywords() == []
    end
  end

  describe "handle/2" do
    setup do
      Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
      on_exit(fn -> Application.delete_env(:vestaboard_agent, :llm) end)
      :ok
    end

    test "returns {:ok, text} when LLM responds" do
      plug = {Req.Test, ConversationalAgentTest}

      Req.Test.stub(ConversationalAgentTest, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "All is one.\nBe present."}]})
      end)

      assert {:ok, text} = ConversationalAgent.handle("who is god", %{llm_opts: [plug: plug]})
      assert String.contains?(text, "All is one")
    end

    test "returns {:error, _} on API failure" do
      plug = {Req.Test, ConversationalAgentTestError}

      Req.Test.stub(ConversationalAgentTestError, fn conn ->
        Plug.Conn.send_resp(conn, 500, "error")
      end)

      assert {:error, _} = ConversationalAgent.handle("who is god", %{llm_opts: [plug: plug]})
    end
  end
end
