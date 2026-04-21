#!/usr/bin/env elixir

# Reads VESTABOARD_ENABLEMENT_API_KEY from the environment and enables
# the local API on the board found via ARP/mDNS.
# On success, prints the API key to add to your .env as VESTABOARD_CLOUD_API_KEY.

Mix.install([{:req, "~> 0.5"}, {:jason, "~> 1.4"}])

defmodule EnableLocalAPI do
  @port 7000

  def run do
    token = System.get_env("VESTABOARD_ENABLEMENT_API_KEY") ||
      raise "VESTABOARD_ENABLEMENT_API_KEY is not set in your environment"

    ip = find_board!()
    IO.puts("Enabling local API on #{ip}:#{@port}...")

    url = "http://#{ip}:#{@port}/local-api/enablement"

    case Req.post(url,
           headers: [{"x-vestaboard-local-api-enablement-token", token}],
           receive_timeout: 5_000,
           retry: false
         ) do
      {:ok, %{status: s, body: raw}} when s in 200..299 ->
        body = if is_binary(raw), do: Jason.decode!(raw), else: raw
        api_key = body["apiKey"] || body["api_key"] ||
          raise "Unexpected response body: #{inspect(body)}"

        IO.puts("""

        Local API enabled!

        Add this to your .env:

          VESTABOARD_LOCAL_API_KEY=#{api_key}
          VESTABOARD_BASE_URL=#{ip}
        """)

      {:ok, %{status: status, body: body}} ->
        IO.puts("Failed — HTTP #{status}: #{inspect(body)}")
        System.halt(1)

      {:error, reason} ->
        IO.puts("Request failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp find_board! do
    known_macs = [
      "4C:93:A6:03:3C:C0",
      "4C:93:A6:03:5C:5B",
      "4C:93:A6:02:C8:EC"
    ]

    normalized = Enum.map(known_macs, &normalize_mac/1)

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
end

EnableLocalAPI.run()
