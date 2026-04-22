defmodule VestaboardAgent.TelegramBot do
  @moduledoc """
  Telegram bot that forwards messages to VestaboardAgent.display/1.

  Long-polls getUpdates so no public URL is required. Start automatically
  when TELEGRAM_BOT_TOKEN is present in the environment.

  ## Commands

  - `/status` — reply with the current board text
  - `/clear`  — blank the board

  ## Auth

  Set TELEGRAM_ALLOWED_USERS to a comma-separated list of Telegram chat IDs
  to restrict access. If unset, the bot accepts messages from anyone.
  """

  use GenServer
  require Logger

  @poll_timeout 30
  @base_url "https://api.telegram.org"

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    token = System.get_env("TELEGRAM_BOT_TOKEN")

    if token do
      Logger.info("TelegramBot starting")
      state = %{token: token, offset: 0, allowed: parse_allowed_users()}
      send(self(), :poll)
      {:ok, state}
    else
      Logger.warning("TelegramBot: TELEGRAM_BOT_TOKEN not set, bot disabled")
      :ignore
    end
  end

  @impl true
  def handle_info(:poll, state) do
    state = fetch_updates(state)
    send(self(), :poll)
    {:noreply, state}
  end

  # --- Polling ---

  defp fetch_updates(%{token: token, offset: offset} = state) do
    url = "#{@base_url}/bot#{token}/getUpdates"

    case Req.get(url, params: [offset: offset, timeout: @poll_timeout], receive_timeout: (@poll_timeout + 5) * 1_000) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => updates}}} ->
        new_offset = process_updates(updates, state)
        %{state | offset: new_offset}

      {:ok, %{status: 200, body: %{"ok" => false, "description" => desc}}} ->
        Logger.error("TelegramBot getUpdates error: #{desc}")
        state

      {:error, reason} ->
        Logger.warning("TelegramBot poll failed: #{inspect(reason)}")
        Process.sleep(5_000)
        state
    end
  end

  defp process_updates([], state), do: state.offset

  defp process_updates(updates, state) do
    Enum.each(updates, &handle_update(&1, state))
    updates |> List.last() |> Map.fetch!("update_id") |> Kernel.+(1)
  end

  defp handle_update(%{"message" => %{"chat" => %{"id" => chat_id}, "text" => text}}, state) do
    if allowed?(chat_id, state.allowed) do
      handle_message(chat_id, String.trim(text), state)
    else
      send_message(state.token, chat_id, "Sorry, you're not authorized to use this bot.")
    end
  end

  defp handle_update(_update, _state), do: :ok

  # --- Message dispatch ---

  defp handle_message(chat_id, "/status", state) do
    reply =
      case VestaboardAgent.Dispatcher.last_board() do
        nil -> "Board has no state yet."
        %{text: ""} -> "Board is blank."
        %{text: text} -> "Current board:\n<pre>#{html_escape(text)}</pre>"
      end

    send_message(state.token, chat_id, reply)
  end

  defp handle_message(chat_id, "/clear", state) do
    blank = List.duplicate(List.duplicate(0, 22), 6)

    case VestaboardAgent.Dispatcher.dispatch(blank) do
      {:ok, _} -> send_message(state.token, chat_id, "Board cleared.")
      {:error, reason} -> send_message(state.token, chat_id, "Error: #{inspect(reason)}")
    end
  end

  defp handle_message(chat_id, text, state) do
    token = state.token
    Task.start(fn ->
      t0 = System.monotonic_time(:millisecond)
      result = VestaboardAgent.display(text)
      elapsed = System.monotonic_time(:millisecond) - t0
      send_message(token, chat_id, format_reply(result, elapsed))
    end)
  end

  # --- Reply formatting ---

  defp format_reply({:ok, _}, elapsed) do
    board = VestaboardAgent.Dispatcher.last_board()
    board_text = (board && board.text != "" && board.text) || "(blank)"

    border_line =
      case board && border_color_name(board.grid) do
        nil -> ""
        name -> "\nBorder: #{name}"
      end

    "Displayed in #{elapsed}ms#{border_line}\n<pre>#{html_escape(board_text)}</pre>"
  end

  defp format_reply({:error, :no_match}, _elapsed) do
    "Sorry, I couldn't figure out what to display. Try rephrasing."
  end

  defp format_reply({:error, reason}, _elapsed) do
    "Error: #{html_escape(inspect(reason))}"
  end

  defp border_color_name(grid) do
    first_row = hd(grid)
    code = hd(first_row)

    if code != 0 and Enum.all?(first_row, &(&1 == code)) do
      VestaboardAgent.Renderer.color_codes()
      |> Enum.find_value(fn {name, c} -> if c == code, do: name end)
    end
  end

  # --- Telegram API ---

  defp send_message(token, chat_id, text) do
    url = "#{@base_url}/bot#{token}/sendMessage"

    case Req.post(url, json: %{chat_id: chat_id, text: text, parse_mode: "HTML"}) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{body: body}} ->
        Logger.warning("TelegramBot sendMessage failed: #{inspect(body)}")

      {:error, reason} ->
        Logger.warning("TelegramBot sendMessage error: #{inspect(reason)}")
    end
  end

  # --- Auth ---

  defp parse_allowed_users do
    case System.get_env("TELEGRAM_ALLOWED_USERS") do
      nil -> :all
      "" -> :all
      csv -> csv |> String.split(",") |> Enum.map(&String.trim/1) |> MapSet.new()
    end
  end

  defp allowed?(_chat_id, :all), do: true
  defp allowed?(chat_id, allowed), do: MapSet.member?(allowed, to_string(chat_id))

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
