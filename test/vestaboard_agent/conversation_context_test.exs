defmodule VestaboardAgent.ConversationContextTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.ConversationContext

  setup do
    on_exit(fn -> ConversationContext.clear() end)
    ConversationContext.clear()
    :ok
  end

  test "history/0 returns empty list when nothing pushed" do
    assert ConversationContext.history() == []
  end

  test "push/3 adds an entry" do
    ConversationContext.push("hello world", "HELLO WORLD", border: "blue")
    # cast is async — give GenServer a moment to process
    :sys.get_state(ConversationContext)

    [entry] = ConversationContext.history()
    assert entry.prompt == "hello world"
    assert entry.text == "HELLO WORLD"
    assert entry.render_opts == [border: "blue"]
  end

  test "history returns newest entry first" do
    ConversationContext.push("first", "FIRST", [])
    ConversationContext.push("second", "SECOND", border: "red")
    :sys.get_state(ConversationContext)

    [head | _] = ConversationContext.history()
    assert head.prompt == "second"
  end

  test "history is capped at 5 entries" do
    for i <- 1..7 do
      ConversationContext.push("prompt #{i}", "TEXT #{i}", [])
    end

    :sys.get_state(ConversationContext)

    assert length(ConversationContext.history()) == 5
  end

  test "clear/0 empties the history" do
    ConversationContext.push("hello", "HELLO", [])
    :sys.get_state(ConversationContext)
    ConversationContext.clear()

    assert ConversationContext.history() == []
  end
end
