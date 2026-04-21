#!/usr/bin/env elixir

known_macs = [
  "4C:93:A6:03:3C:C0",
  "4C:93:A6:03:5C:5B",
  "4C:93:A6:02:C8:EC"
]

defmodule FindVestaboard do
  @port 7000
  @timeout 1_000
  @hostname "vestaboard-083d7e78.local"

  def run(known_macs) do
    normalized = Enum.map(known_macs, &normalize_mac/1)

    IO.puts("Checking ARP table for known Vestaboard MACs...")
    case arp_lookup(normalized) do
      {:ok, ip} ->
        IO.puts("Found via ARP: #{ip}")
        verify(ip)

      :error ->
        IO.puts("Not in ARP table. Trying mDNS...")
        case mdns_lookup() do
          {:ok, ip} ->
            IO.puts("Found via mDNS: #{ip}")
            verify(ip)

          :error ->
            IO.puts("mDNS failed. Scanning subnet for port #{@port}...")
            scan_subnet(normalized)
        end
    end
  end

  # --- ARP lookup ---

  defp arp_lookup(normalized_macs) do
    case System.cmd("arp", ["-a"], stderr_to_stdout: true) do
      {output, 0} ->
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

      _ ->
        :error
    end
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

  # --- mDNS lookup ---

  defp mdns_lookup do
    case :inet.getaddr(to_charlist(@hostname), :inet) do
      {:ok, {a, b, c, d}} -> {:ok, "#{a}.#{b}.#{c}.#{d}"}
      _ -> :error
    end
  end

  # --- Subnet scan ---

  defp scan_subnet(normalized_macs) do
    local_ip = local_ip()
    subnet = local_ip |> String.split(".") |> Enum.take(3) |> Enum.join(".")
    IO.puts("Scanning #{subnet}.0/24 (this takes ~15s)...\n")

    results =
      1..254
      |> Task.async_stream(
        fn i ->
          ip = "#{subnet}.#{i}"
          with true <- port_open?(ip),
               :ok <- check_arp_for_mac(ip, normalized_macs) do
            ip
          else
            _ -> nil
          end
        end,
        max_concurrency: 50,
        timeout: 5_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, ip} when is_binary(ip) -> [ip]
        _ -> []
      end)

    case results do
      [] ->
        IO.puts("No board found. Check the Vestaboard app (Settings → Developer) for the IP.")
      ips ->
        IO.puts("Vestaboard candidate(s) found:")
        Enum.each(ips, &verify/1)
    end
  end

  # Re-check ARP for a specific IP to confirm its MAC matches
  defp check_arp_for_mac(ip, normalized_macs) do
    case System.cmd("arp", [ip], stderr_to_stdout: true) do
      {output, 0} ->
        mac = extract_mac(output)
        if mac && normalize_mac(mac) in normalized_macs, do: :ok, else: :error
      _ -> :error
    end
  end

  # --- Verify by hitting the API ---

  defp verify(ip) do
    url = "http://#{ip}:#{@port}/local-api/message"
    case Req.get(url, receive_timeout: @timeout, retry: false) do
      {:ok, %{status: status, headers: headers}} when status in [200, 400, 403] ->
        server = headers["server"] |> List.wrap() |> List.first("")
        IO.puts("  #{ip}:#{@port} — #{status} (#{server})")
        ip
      _ ->
        IO.puts("  #{ip}:#{@port} — not responding on local API port")
        nil
    end
  end

  defp port_open?(ip) do
    case :gen_tcp.connect(to_charlist(ip), @port, [:binary, active: false], @timeout) do
      {:ok, sock} -> :gen_tcp.close(sock); true
      _ -> false
    end
  end

  defp local_ip do
    {:ok, ifs} = :inet.getifaddrs()
    ifs
    |> Enum.flat_map(fn {_name, opts} ->
      opts
      |> Keyword.get_values(:addr)
      |> Enum.filter(fn
        {a, _, _, _} -> a not in [127, 169] and a != 0
        _ -> false
      end)
    end)
    |> List.first({192, 168, 0, 1})
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end

Mix.install([{:req, "~> 0.5"}])
FindVestaboard.run(known_macs)
