require Logger

defmodule OpenAperture.Fleet.SystemdUnit.Journal do

  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.CommonSystemdUtils

  @doc """
  Method to retrieve the journal logs associated with a Unit
  
  ## Options
  
  The `unit` option define the SystemdUnit.t
   
  ## Return Values

  tuple {:ok, stdout, stderr} | {:error, stdout, stderr}
  """
  @spec get_journal(SystemdUnit.t) :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}
  def get_journal(unit) do
    api = SystemdUnit.get_fleet_api(unit.etcd_token)
    cluster_hosts = case FleetApi.Etcd.list_machines(api) do
      {:ok, cluster_hosts} -> cluster_hosts
      {:error, reason} ->
        Logger.error("Failed to retrieve hosts in cluster #{unit.etcd_token}:  #{inspect reason}")
        nil
    end

    requested_host = if (unit.machineID != nil) do
      Logger.debug("Resolving host using machineID #{unit.machineID}...")
      if cluster_hosts == nil || length(cluster_hosts) == 0 do
        nil
      else
        Enum.reduce(cluster_hosts, nil, fn(cluster_host, requested_host)->
          cond do
            requested_host != nil -> requested_host
            cluster_host != nil && cluster_host.id != nil && String.contains?(cluster_host.id, unit.machineID) -> cluster_host
            true -> requested_host
          end
        end)
      end
    else
      nil
    end

    result = if requested_host != nil do
      Logger.debug("Retrieving logs from host #{inspect requested_host}...")
      execute_journal_request([requested_host], unit, false)
    else
      nil
    end

    case result do
      {:ok, stdout, stderr} -> {:ok, stdout, stderr}     
      _ -> 
        Logger.debug("Unable to retrieve logs using the unit's machineID (#{inspect requested_host}), defaulting to all hosts in cluster...")
        execute_journal_request(cluster_hosts, unit, false)
    end
  end

  @doc false
  # Method to execute a journal request against a list of hosts.
  #
  ## Options
  #
  # The list option represents the hosts to be executed against.
  #
  # The `unit_options` option represents the Unit options
  # 
  ## Return values
  # 
  # tuple:  {:ok, stdout, stderr}, {:error, stdout, stderr}
  # 
  @spec execute_journal_request(List, SystemdUnit.t, term) :: {:ok, String.t(), String.t()}| {:ok, String.t(), String.t()}
  def execute_journal_request([requested_host|remaining_hosts], unit, verify_result) do
    File.mkdir_p("#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit")
    stdout_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.log"
    stderr_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.log"

    journal_script = EEx.eval_file("#{System.cwd!()}/templates/fleetctl-journal.sh.eex", [host_ip: requested_host.primaryIP, unit_name: unit.name, verify_result: verify_result])
    journal_script_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.sh"
    File.write!(journal_script_file, journal_script)

    resolved_cmd = "bash #{journal_script_file} 2> #{stderr_file} > #{stdout_file} < /dev/null"

    Logger.debug ("Executing Fleet Journal command:  #{resolved_cmd}")
    try do
      case System.cmd("/bin/bash", ["-c", resolved_cmd], []) do
        {_stdout, 0} ->
          {:ok, CommonSystemdUtils.read_output_file(stdout_file), CommonSystemdUtils.read_output_file(stderr_file)}
        {_stdout, return_status} ->
          Logger.debug("Host #{requested_host.primaryIP} returned an error (#{return_status}) when looking for unit #{unit.name}:\n#{CommonSystemdUtils.read_output_file(stdout_file)}\n\n#{CommonSystemdUtils.read_output_file(stderr_file)}")
          execute_journal_request(remaining_hosts, unit, verify_result)
      end
    after
      File.rm_rf(stdout_file)
      File.rm_rf(stderr_file)
      File.rm_rf(journal_script_file)
    end
  end

  @doc false
  # Method to execute a journal request against a list of hosts.
  #
  ## Options
  #
  # The list option represents the hosts to be executed against.
  #
  # The `unit_options` option represents the Unit options
  # 
  ## Return values
  # 
  # tuple:  {:ok, stdout, stderr}, {:error, stdout, stderr}
  # 
  @spec execute_journal_request([], SystemdUnit.t, term) :: {:ok, String.t(), String.t()}| {:error, String.t(), String.t()}
  def execute_journal_request([], unit, _) do
    {:error, "Unable to find a host running service #{unit.name}!", ""}
  end

  @doc false
  # Method to execute a journal request against a list of hosts.
  #
  ## Options
  #
  # The list option represents the hosts to be executed against.
  #
  # The `unit_options` option represents the Unit options
  # 
  ## Return values
  # 
  # tuple:  {:ok, stdout, stderr}, {:error, stdout, stderr}
  # 
  @spec execute_journal_request(nil, SystemdUnit.t, term) :: {:ok, String.t(), String.t()}| {:error, String.t(), String.t()}
  def execute_journal_request(nil, unit, _) do
    {:error, "Unable to find a host running service #{unit.name} - an invalid host-list was provided!", ""}
  end
end