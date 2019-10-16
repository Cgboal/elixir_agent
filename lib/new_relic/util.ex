defmodule NewRelic.Util do
  @moduledoc false

  alias NewRelic.Util.Vendor

  def hostname do
    maybe_heroku_dyno_hostname() || get_hostname()
  end

  def pid, do: System.get_pid() |> String.to_integer()

  def time_to_ms({megasec, sec, microsec}),
    do: (megasec * 1_000_000 + sec) * 1_000 + round(microsec / 1_000)

  def process_name(pid) do
    case Process.info(pid, :registered_name) do
      nil -> nil
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
    end
  end

  def metric_join(segments) when is_list(segments) do
    segments
    |> Enum.filter(& &1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.replace_leading(&1, "/", ""))
    |> Enum.map(&String.replace_trailing(&1, "/", ""))
    |> Enum.join("/")
  end

  def deep_flatten(attrs) when is_list(attrs) do
    Enum.flat_map(attrs, &deep_flatten/1)
  end

  def deep_flatten({key, value}) when is_list(value) do
    Enum.with_index(value)
    |> Enum.flat_map(fn {v, index} -> deep_flatten({"#{key}.#{index}", v}) end)
  end

  def deep_flatten({key, value}) when is_map(value) do
    Enum.flat_map(value, fn {k, v} -> deep_flatten({"#{key}.#{k}", v}) end)
  end

  def deep_flatten({key, value}) do
    [{key, value}]
  end

  def elixir_environment() do
    build_info = System.build_info()

    [
      ["Language", "Elixir"],
      ["Elixir Version", build_info[:version]],
      ["OTP Version", build_info[:otp_release]],
      ["Elixir build", build_info[:build]]
    ]
  end

  @nr_metadata_prefix "NEW_RELIC_METADATA_"
  def metadata() do
    System.get_env()
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, @nr_metadata_prefix) end)
    |> Enum.into(%{})
  end

  def utilization() do
    %{
      metadata_version: 5,
      logical_processors: :erlang.system_info(:logical_processors),
      total_ram_mib: get_system_memory(),
      hostname: hostname()
    }
    |> maybe_add_ip_addresses
    |> maybe_add_fqdn
    |> maybe_add_linux_boot_id()
    |> Vendor.maybe_add_vendors()
  end

  def maybe_heroku_dyno_hostname do
    System.get_env("DYNO")
    |> case do
      nil -> nil
      "scheduler." <> _ -> "scheduler.*"
      "run." <> _ -> "run.*"
      name -> name
    end
  end

  def maybe_add_linux_boot_id(util) do
    case File.read("/proc/sys/kernel/random/boot_id") do
      {:ok, boot_id} -> Map.put(util, "boot_id", boot_id)
      _ -> util
    end
  end

  def maybe_add_ip_addresses(util) do
    case :inet.getif() do
      {:ok, addrs} ->
        ip_address = Enum.map(addrs, fn {ip, _, _} -> to_string(:inet.ntoa(ip)) end)
        Map.put(util, :ip_address, ip_address)

      _ ->
        util
    end
  end

  def maybe_add_fqdn(util) do
    case :net_adm.dns_hostname(:net_adm.localhost()) do
      {:ok, fqdn} -> Map.put(util, :full_hostname, to_string(fqdn))
      _ -> util
    end
  end

  def get_host(url) do
    case URI.parse(url) do
      %{host: nil} -> url
      %{host: host} -> host
    end
  end

  @mb 1024 * 1024
  defp get_system_memory() do
    case :memsup.get_system_memory_data()[:system_total_memory] do
      nil -> nil
      bytes -> trunc(bytes / @mb)
    end
  end

  defp get_hostname do
    with {:ok, name} <- :inet.gethostname(), do: to_string(name)
  end
end
