#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5"}])

defmodule TestConnectivity do
  @port 7000
  @known_macs [
    "4C:93:A6:03:3C:C0",
    "4C:93:A6:03:5C:5B",
    "4C:93:A6:02:C8:EC"
  ]

  def run do
    api_key = System.get_env("VESTABOARD_LOCAL_API_KEY") ||
      raise "VESTABOARD_LOCAL_API_KEY is not set in your .env"

    ip = find_board!()
    url = "http://#{ip}:#{@port}/local-api/message"

    IO.puts("Testing connectivity to #{url}...")

    case Req.get(url,
           headers: [{"x-vestaboard-local-api-key", api_key}],
           receive_timeout: 5_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("Connected! Current board state:")
        IO.puts("  Status: 200 OK")
        IO.puts("  Server: #{server_header(body)}")
        IO.puts("  Grid: #{grid_summary(body)}")

      {:ok, %{status: 403}} ->
        IO.puts("Authentication failed — check VESTABOARD_CLOUD_API_KEY in your .env")
        System.halt(1)

      {:ok, %{status: status, body: body}} ->
        IO.puts("Unexpected response — HTTP #{status}: #{inspect(body)}")
        System.halt(1)

      {:error, reason} ->
        IO.puts("Connection failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp find_board! do
    normalized = Enum.map(@known_macs, &normalize_mac/1)
    case arp_lookup(normalized) do
      {:ok, ip} ->
        IO.puts("Board found via ARP: #{ip}")
        ip
      :error ->
        raise "Could not find Vestaboard on the network. Run `make find` first."
    end
  end

  defp arp_lookup(normalized_macs) do
    {output, 0} = System.cmd("arp", ["-a"], stderr_to_stdout: true)
    output
    |> String.split("\n")
    |> Enum.find_value(:error, fn line ->
      with mac when mac != nil <- extract_mac(line),
           true <- normalize_mac(mac) in normalized_macs,
           ip when ip != nil <- extract_ip(line) do
        {:ok, ip}
      else
        _ -> nil
      end
    end)
  end

  defp extract_ip(line) do
    case Regex.run(~r/\((\d+\.\d+\.\d+\.\d+)\)/, line) do
      [_, ip] -> ip
      _ -> nil
    end
  end

  defp extract_mac(line) do
    case Regex.run(~r/((?:[0-9a-fA-F]{1,2}[:\-]){5}[0-9a-fA-F]{1,2})/, line) do
      [_, mac] -> mac
      _ -> nil
    end
  end

  defp normalize_mac(mac) do
    mac
    |> String.upcase()
    |> String.replace("-", ":")
    |> String.split(":")
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
  end

  defp server_header(body) when is_map(body), do: "n/a"
  defp server_header(_), do: "n/a"

  defp grid_summary(body) when is_list(body) do
    rows = length(body)
    cols = body |> List.first([]) |> length()
    "#{rows}x#{cols} character grid"
  end
  defp grid_summary(body), do: inspect(body)
end

TestConnectivity.run()
