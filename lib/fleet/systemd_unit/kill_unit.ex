require Logger

defmodule OpenAperture.Fleet.SystemdUnit.KillUnit do

  alias OpenAperture.Fleet.SystemdUnit

  @logprefix "[KillUnit]"  

  @spec kill_unit(SystemdUnit.t) :: :ok
  def kill_unit(unit) do
    Logger.info ("#{@logprefix} Attempting to kill unit #{unit.name}...")
    api = SystemdUnit.get_fleet_api(unit.etcd_token)
    case FleetApi.Etcd.list_machines(api) do
      {:error, reason} ->
        Logger.error("#{@logprefix} Unable to kill unit #{unit.name} - Failed to retrieve hosts in cluster #{unit.etcd_token}:  #{inspect reason}")
        :error
      {:ok, nil} ->
        Logger.error("#{@logprefix} Unable to kill unit #{unit.name} - cluster #{unit.etcd_token} returned an invalid host list!")
        :error
      {:ok, []} ->
        Logger.error("#{@logprefix} Unable to kill unit #{unit.name} - cluster #{unit.etcd_token} returned no hosts!")
        :error
      {:ok, cluster_hosts} ->
        :random.seed(:os.timestamp)
        host = List.first(Enum.shuffle(cluster_hosts))

        if OpenAperture.Fleet.SystemdUnit.KillUnit.kill_unit_on_host(unit, host) == :ok do
          Logger.info("#{@logprefix} Successfully killed unit #{unit.name}")
          :ok
        else
          Logger.error("#{@logprefix} Failed to kill unit #{unit.name}")
          :error
        end
    end
  end

  @spec kill_unit_on_host(SystemdUnit.t, FleetApi.Machine.t) :: :ok | :error
  def kill_unit_on_host(unit, host) do
    base_dir = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/kill/#{UUID.uuid1()}"
    File.mkdir_p(base_dir)
    stdout_file = "#{base_dir}/#{UUID.uuid1()}.log"
    stderr_file = "#{base_dir}/#{UUID.uuid1()}.log"

    kill_script = EEx.eval_file("#{System.cwd!()}/templates/fleetctl-kill.sh.eex", [host_ip: host.primaryIP, unit_name: unit.name, verify_result: true])
    kill_script_file = "#{base_dir}/#{UUID.uuid1()}.sh"
    File.write!(kill_script_file, kill_script)

    resolved_cmd = "bash #{kill_script_file} 2> #{stderr_file} > #{stdout_file} < /dev/null"

    Logger.debug ("#{@logprefix} Executing Fleet command:  #{resolved_cmd}")
    try do
      case System.cmd("/bin/bash", ["-c", resolved_cmd], []) do
        {_stdout, 0} ->
          :ok
        {_stdout, return_status} ->
          Logger.error("#{@logprefix} Host #{host.primaryIP} returned an error (#{return_status}) when attempting to kill unit #{unit.name}:\n#{read_output_file(stdout_file)}\n\n#{read_output_file(stderr_file)}")
          :error
      end
    after
      File.rm_rf(base_dir)
    end
  end

  @doc false
  # Method to read in a file and return contents
  # 
  ## Return values
  # 
  # String
  # 
  @spec read_output_file(String.t()) :: String.t()
  defp read_output_file(output_file) do
    if File.exists?(output_file) do
      File.read!(output_file)
    else
      Logger.error("#{@logprefix} Unable to read systemd output file #{output_file} - file does not exist!")
      ""
    end
  end
end