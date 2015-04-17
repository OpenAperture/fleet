require Logger

defmodule OpenAperture.Fleet.SystemdUnit do
  alias OpenAperture.Fleet.FleetAPIInstances
  alias FleetApi.Etcd
  @doc """
  Creates a `GenServer` representing a systemd Unit.

  ## Options

  The `options` option defines the Map of configuration options that should be 
  passed to systemd.

  ## Return values

  If the server is successfully created and initialized, the function returns
  `{:ok, pid}`, where pid is the pid of the server. If there already exists a
  process with the specified server name, the function returns
  `{:error, {:already_started, pid}}` with the pid of that process.

  If the `init/1` callback fails with `reason`, the function returns
  `{:error, reason}`. Otherwise, if it returns `{:stop, reason}`
  or `:ignore`, the process is terminated and the function returns
  `{:error, reason}` or `:ignore`, respectively.
  """
  @spec create(Map) :: {:ok, pid} | {:error, String.t()}
  def create(options) do
    Agent.start_link(fn -> options end)
  end

  @doc """
  Method to generate a new EtcdCluster agent

  ## Options

  The `options` option defines the Map of configuration options that should be 
  passed to systemd.

  ## Return Values

  pid
  """
  @spec create!(String.t()) :: pid
  def create!(options) do
    case create(options) do
      {:ok, cluster} -> cluster
      {:error, reason} -> raise "Failed to create OpenAperture.Fleet.SystemdUnit:  #{reason}"
    end
  end  

  @doc """
  Method to store the associated etcd_token
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet
  
  """
  @spec set_etcd_token(pid, String.t()) :: term
  def set_etcd_token(unit, etcd_token) do
    unit_options = Agent.get(unit, fn options -> options end)
    new_options = Map.merge(unit_options, %{etcd_token: etcd_token})
    new_options = Map.merge(new_options, %{"etcd_token": etcd_token})

    Agent.update(unit, fn _ -> new_options end)
  end

  @doc """
  Method to store the assigned port
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `port` provides the assigned integer port
  
  """
  @spec set_assigned_port(pid, Integer) :: term
  def set_assigned_port(unit, port) do
    unit_options = Agent.get(unit, fn options -> options end)
    new_options = Map.merge(unit_options, %{dst_port: port})
    new_options = Map.merge(new_options, %{"dst_port": port})

    Agent.update(unit, fn _ -> new_options end)
  end

  @doc """
  Method to retrieve the assigned port
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Value

  The assigned integer port
  
  """
  @spec get_assigned_port(pid) :: term
  def get_assigned_port(unit) do
    unit_options = Agent.get(unit, fn options -> options end)
    unit_options[:dst_port]
  end

  @doc """
  Method to refresh the state of the Unit from the cluster
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet
  
  """
  @spec refresh(pid, String.t()) :: term
  def refresh(unit, etcd_token \\ nil) do
    unit_options = Agent.get(unit, fn options -> options end)

    resolved_etcd_token = resolve_fleet_pid(unit, etcd_token)
    Logger.debug("Refreshing unit #{unit_options["name"]} on cluster...")
    refreshed_options = Etcd.get_unit(resolved_etcd_token, unit_options["name"])
    if refreshed_options["name"] == nil || String.length(refreshed_options["name"]) == 0 do
      Logger.error("The refresh for unit #{unit_options["name"]} has failed - the returned data is invalid:  #{inspect refreshed_options}")
    else
      Agent.update(unit, fn _ -> refreshed_options end)
    end

    set_etcd_token(unit, resolved_etcd_token)
  end

  @doc """
  Method to retrieve the unit name
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Values

  String
  
  """
  @spec get_unit_name(pid) :: String.t()
  def get_unit_name(unit) do
    unit_options = Agent.get(unit, fn options -> options end)
    unit_options["name"]
  end

  @doc """
  Method to retrieve the unit name
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Values

  String
  
  """
  @spec get_machine_id(pid) :: String.t()
  def get_machine_id(unit) do
    unit_options = Agent.get(unit, fn options -> options end)
    unit_options["machineID"]
  end

  @doc """
  Method to determine if the unit is in a launched state (according to Fleet)
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Values

  true or {false, state}
  
  """
  @spec is_launched?(pid) :: term
  def is_launched?(unit) do
		unit_options = Agent.get(unit, fn options -> options end)  	
    case unit_options["currentState"] do
      "launched" -> true
      _ -> {false, unit_options["currentState"]}
    end
  end

  @doc """
  Method to determine if the unit is in active (according to systemd)
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Values

  true or {false, active_state, load_state, sub_state}

  active_state:  http://www.freedesktop.org/software/systemd/man/systemd.html
  load_state:  http://www.freedesktop.org/software/systemd/man/systemd.unit.html
  sub_state:  http://www.freedesktop.org/software/systemd/man/systemd.html  
  
  """
  @spec is_active?(pid, String.t()) :: term
  def is_active?(unit, etcd_token \\ nil) do
  	unit_options = Agent.get(unit, fn options -> options end)
  	current_unit_states = Etcd.list_unit_states(resolve_fleet_pid(unit, etcd_token))
    if (current_unit_states != nil ) do
      requested_state = Enum.reduce(current_unit_states, nil, fn(current_state, requested_state)->
        if ((requested_state == nil) && unit_options["name"] != nil && String.contains?(current_state["name"], unit_options["name"])) do
          requested_state = current_state
        end
        requested_state
      end)
      if (requested_state != nil) do
  	    case requested_state["systemdActiveState"] do
  	    	"active" -> true
  	    	_ -> {false, requested_state["systemdActiveState"], requested_state["systemdLoadState"], requested_state["systemdSubState"]}
  	    end
  	  else
  	  	{false, nil, nil, nil}
  	  end
    else
      Logger.error("Unable to verify the state of unit #{unit_options["name"]}!  Please verify that all hosts in the etcd cluster are running Fleet version 0.8.3 or greater!")   
      {false, nil, nil, nil}
    end
  end

  @doc """
  Method to spin up a new unit within a fleet cluster
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet

  ## Return Values

  boolean; true if unit was launched
  
  """
  @spec spinup_unit(pid, String.t()) :: term
  def spinup_unit(unit, etcd_token \\ nil) do
  	unit_options = Agent.get(unit, fn options -> options end)
  	Logger.info ("Deploying unit #{unit_options["name"]}...")
    case Etcd.set_unit(resolve_fleet_pid(unit, etcd_token), unit_options["name"], FleetApi.Unit.from_map(unit_options)) do
      :ok ->
        Logger.debug ("Successfully loaded unit #{unit_options["name"]}")
        true
      {:error, reason} ->
        Logger.error ("Failed to created unit #{unit_options["name"]}:  #{inspect reason}")
        false
    end
  end

  @doc """
  Method to tear down an existing unit within a fleet cluster
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet

  ## Return Values

  boolean; true if unit was destroyed
  """
  @spec teardown_unit(pid, String.t()) :: term
  def teardown_unit(unit, etcd_token \\ nil) do
  	unit_options = Agent.get(unit, fn options -> options end)

    Logger.info ("Tearing down unit #{unit_options["name"]}...")
    case Etcd.delete_unit(resolve_fleet_pid(unit, etcd_token), unit_options["name"]) do
      :ok ->
        Logger.debug ("Successfully deleted unit #{unit_options["name"]}")        
        wait_for_unit_teardown(unit, etcd_token)
      {:error, reason} ->
        Logger.error ("Failed to deleted unit #{unit_options["name"]}:  #{inspect reason}")
    end
  end

  @doc false
  # Method to stall until a container has shut down
  #
  ## Options
  #
  # The `unit` option defines the Unit PID
  #
  # The `etcd_token` option is an optional String representing a supplied etcd_token
  #
  @spec wait_for_unit_teardown(pid, String.t()) :: String.t()
  defp wait_for_unit_teardown(unit, etcd_token) do
    unit_options = Agent.get(unit, fn options -> options end)
    Logger.info ("Verifying unit #{unit_options["name"]} has stopped...")

    resolved_etcd_token = resolve_fleet_pid(unit, etcd_token)
    case Etcd.get_unit(resolved_etcd_token, unit_options["name"]) do
      :ok ->
        Logger.debug ("Unit #{unit_options["name"]} is still stopping...")
        :timer.sleep(10000)
        wait_for_unit_teardown(unit, resolved_etcd_token)
      {:error, %{code: 404}} ->
        Logger.info ("Unit #{unit_options["name"]} has stopped")

        case is_active?(unit) do
          true -> 
              Logger.debug ("Unit #{unit_options["name"]} is still active...")
              :timer.sleep(10000)
              wait_for_unit_teardown(unit, resolved_etcd_token)
          {false, "activating", _, _} -> 
              Logger.debug ("Unit #{unit_options["name"]} is still starting up...")
              :timer.sleep(10000)
              wait_for_unit_teardown(unit, resolved_etcd_token)
          {false, _, _, _} -> 
            Logger.info ("Unit #{unit_options["name"]} is no longer active")
        end
    end
  end

  @doc false
  # Method to either return a passed in etcd token or look it up in the unit's options
  #
  ## Options
  #
  # The `unit` option defines the Unit PID
  #
  # The `etcd_token` option is an optional String representing a supplied etcd_token
  #
  ## Return Values
  #
  # String
  #
  @spec resolve_fleet_pid(pid, String.t()) :: String.t()
  defp resolve_fleet_pid(unit, etcd_token) do
    if (etcd_token == nil), do: etcd_token = Agent.get(unit, fn options -> options end)[:etcd_token]
    FleetAPIInstances.get_instance(etcd_token)
  end

  @doc """
  Method to retrieve the journal logs associated with a Unit
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet

  ## Return Values

  tuple {:ok, stdout, stderr} | {:error, stdout, stderr}
  """
  @spec get_journal(pid, String.t()) :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}
  def get_journal(unit, etcd_token \\ nil) do
    unit_options = Agent.get(unit, fn options -> options end)

    resolved_fleet_pid = resolve_fleet_pid(unit, etcd_token)
    if (unit_options["machineID"] != nil) do
      Logger.debug("Resolving host using machineID #{unit_options["machineID"]}...")
      cluster_hosts = Etcd.list_machines(resolved_fleet_pid)

      requested_host = Enum.reduce(cluster_hosts, nil, fn(cluster_host, requested_host)->
        if ((requested_host == nil) && (requested_host != nil && requested_host["id"] != nil && String.contains?(requested_host["id"], unit_options["machineID"]))) do
          requested_host = cluster_host
        end
        requested_host
      end)
    end

    if requested_host != nil do
      Logger.debug("Retrieving logs from host #{inspect requested_host}...")
      result = execute_journal_request([requested_host], unit_options, true)
    end

    case result do
      {:ok, stdout, stderr} -> {:ok, stdout, stderr}     
      _ -> 
        Logger.debug("Unable to retrieve logs using the unit's machineID (#{inspect requested_host}), defaulting to all hosts in cluster...")
        hosts = Etcd.list_machines(resolved_fleet_pid)
        execute_journal_request(hosts, unit_options, true)
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
  @spec execute_journal_request(List, Map, term) :: {:ok, String.t(), String.t()}| {:ok, String.t(), String.t()}
  def execute_journal_request([requested_host|remaining_hosts], unit_options, verify_result) do
    File.mkdir_p("#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit")
    stdout_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.log"
    stderr_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.log"

    journal_script = EEx.eval_file("#{System.cwd!()}/templates/fleetctl-journal.sh.eex", [host_ip: requested_host["primaryIP"], unit_name: unit_options["name"], verify_result: verify_result])
    journal_script_file = "#{Application.get_env(:openaperture_fleet, :tmpdir)}/systemd_unit/#{UUID.uuid1()}.sh"
    File.write!(journal_script_file, journal_script)

    resolved_cmd = "bash #{journal_script_file} 2> #{stderr_file} > #{stdout_file} < /dev/null"

    Logger.debug ("Executing Fleet command:  #{resolved_cmd}")
    try do
      case System.cmd("/bin/bash", ["-c", resolved_cmd], []) do
        {stdout, 0} ->
          {:ok, read_output_file(stdout_file), read_output_file(stderr_file)}
        {stdout, return_status} ->
          Logger.debug("Host #{requested_host["primaryIP"]} returned an error (#{return_status}) when looking for unit #{unit_options["name"]}:\n#{read_output_file(stdout_file)}\n\n#{read_output_file(stderr_file)}")
          execute_journal_request(remaining_hosts, unit_options, verify_result)
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
  @spec execute_journal_request(List, Map, term) :: {:ok, String.t(), String.t()}| {:error, String.t(), String.t()}
  def execute_journal_request([], unit_options, _) do
    {:error, "Unable to find a host running service #{unit_options["name"]}!", ""}
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
      Logger.error("Unable to read systemd output file #{output_file} - file does not exist!")
      ""
    end
  end  
end