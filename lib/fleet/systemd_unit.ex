require Logger

defmodule OpenAperture.Fleet.SystemdUnit do
  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.FleetApiInstances

  @moduledoc """
  This module contains logic to interact with SystemdUnit modules
  """

  @type t :: %__MODULE__{}
  
  defstruct name: nil,
            options: nil,
            etcd_token: nil, 
            dst_port: nil, 
            desiredState: nil, 
            currentState: nil, 
            machineID: nil, 
            systemdLoadState: nil, 
            systemdActiveState: nil, 
            systemdSubState: nil

  @spec get_fleet_api(String.t) :: pid
  defp get_fleet_api(etcd_token) do
    FleetApiInstances.get_instance(etcd_token)
  end

  @spec build_unit(String.t, FleetApi.Unit.t, FleetApi.UnitState.t) :: SystemdUnit.t
  defp build_unit(etcd_token, unit, unit_state) do
    systemd_unit = %SystemdUnit{
      etcd_token: etcd_token
    }
    systemd_unit = if unit == nil do
      systemd_unit
    else
      %{systemd_unit | 
        name: unit.name,
        options: unit.options,
        desiredState: unit.desiredState,
        currentState: unit.currentState,        
        machineID: unit.machineID,
      }
    end
           
    systemd_unit = if unit_state == nil do
      systemd_unit
    else
      systemd_unit = %{systemd_unit | 
        systemdLoadState: unit_state.systemdLoadState,
        systemdActiveState: unit_state.systemdActiveState,
        systemdSubState: unit_state.systemdSubState
      }

      systemd_unit = if systemd_unit.name == nil do
        %{systemd_unit | name: unit_state.name}
      else
        systemd_unit
      end

      systemd_unit = if systemd_unit.machineID == nil do
        %{systemd_unit | machineID: unit_state.machineID}
      else
        systemd_unit
      end

      systemd_unit
    end

    systemd_unit    
  end

  @doc """
  Method to convert a FleetApi.Unit into a SystemdUnit
  
  ## Options
  
  The `etcd_token` provides the etcd token to connect to fleet

  The `unit` option define the FleetApi.Unit
  
  ## Return Value

  SystemdUnit
  
  """
  @spec from_fleet_unit(String.t(), FleetApi.Unit) :: SystemdUnit.t
  def from_fleet_unit(etcd_token, unit) do
    build_unit(etcd_token, unit, nil)
  end

  @doc """
  Method to retrieve the current SystemdUnit for a unit on the cluster
  
  ## Options
  
  The `etcd_token` provides the etcd token to connect to fleet
  
  ## Return Value

  List of SystemdUnit.t
  """
  @spec get_units(String.t()) :: List
  def get_units(etcd_token) do
    Logger.debug("Retrieving units on cluster #{etcd_token}...")
    api = get_fleet_api(etcd_token)
    units = case FleetApi.Etcd.list_units(api) do
      {:ok, units} -> units
      {:error, reason} -> 
        Logger.error("Failed to retrieve units on cluster #{etcd_token}:  #{inspect reason}")
        nil
    end

    unit_states_by_name = case FleetApi.Etcd.list_unit_states(api) do
      {:ok, unit_states} -> 
        Enum.reduce unit_states, %{}, fn(unit_state, unit_states_by_name) ->
          Map.put(unit_states_by_name, unit_state.name, unit_state)
        end
      {:error, reason} -> 
        Logger.error("Failed to retrieve unit states on cluster #{etcd_token}:  #{inspect reason}")
        %{}
    end 

    if units == nil do
      Enum.reduce Map.values(unit_states_by_name), [], fn(unit_state, systemd_units) ->
        systemd_units ++ [build_unit(etcd_token, nil, unit_state)]
      end
    else
      Enum.reduce units, [], fn(unit, systemd_units) ->
        systemd_units ++ [build_unit(etcd_token, unit, unit_states_by_name[unit.name])]
      end
    end
  end

  @doc """
  Method to retrieve the current SystemdUnit for a unit on the cluster
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  The `etcd_token` provides the etcd token to connect to fleet

  ## Return Value

  SystemdUnit
  
  """
  @spec get_unit(String.t(), String.t()) :: SystemdUnit.t
  def get_unit(unit_name, etcd_token) do
    Logger.debug("Retrieving unit #{unit_name} on cluster #{etcd_token}...")
    api = get_fleet_api(etcd_token)
    unit = case FleetApi.Etcd.get_unit(api, unit_name) do
      {:ok, unit} -> unit
      {:error, reason} -> 
        Logger.error("Failed to retrieve unit #{unit_name} on cluster #{etcd_token}:  #{inspect reason}")
        nil
    end

    unit_states_by_name = case FleetApi.Etcd.list_unit_states(api) do
      {:ok, unit_states} -> 
        Enum.reduce unit_states, %{}, fn(unit_state, unit_states_by_name) ->
          Map.put(unit_states_by_name, unit_state.name, unit_state)
        end
      {:error, reason} -> 
        Logger.error("Failed to retrieve unit states on cluster #{etcd_token}:  #{inspect reason}")
        %{}
    end 

    build_unit(etcd_token, unit, unit_states_by_name[unit_name])
  end

  @doc """
  Method to determine if the unit is in a launched state (according to Fleet)
  
  ## Options
  
  The `unit` option define the Systemd PID
   
  ## Return Values

  true or {false, state}
  
  """
  @spec is_launched?(SystemdUnit.t) :: true | {false, String.t()}
  def is_launched?(unit) do
    case unit.currentState do
      "launched" -> true
      _ -> {false, unit.currentState}
    end
  end

  @doc """
  Method to determine if the unit is in active (according to systemd)
  
  ## Options
  
  The `unit` option define the SystemdUnit
   
  ## Return Values

  {false, unit.systemdActiveState, unit.systemdLoadState, unit.systemdSubState}

  active_state:  http://www.freedesktop.org/software/systemd/man/systemd.html
  load_state:  http://www.freedesktop.org/software/systemd/man/systemd.unit.html
  sub_state:  http://www.freedesktop.org/software/systemd/man/systemd.html  
  
  """
  @spec is_active?(SystemdUnit.t) :: true | {false, String.t(), String.t(), String.t()}
  def is_active?(unit) do
    case unit.systemdActiveState do
      "active" -> true
      _ -> {false, unit.systemdActiveState, unit.systemdLoadState, unit.systemdSubState}
    end
  end

  @doc """
  Method to spin up a new unit within a fleet cluster
  
  ## Options
  
  The `unit` option define the SystemdUnit.t
   
  The `etcd_token` provides the etcd token to connect to fleet

  ## Return Values

  boolean; true if unit was launched
  
  """
  @spec spinup_unit(SystemdUnit.t) :: true | false
  def spinup_unit(unit) do
    fleet_unit = %FleetApi.Unit{
      name: unit.name,
      options: unit.options,
      desiredState: unit.desiredState,
      currentState: unit.currentState,
      machineID: unit.machineID
    }

  	Logger.info ("Deploying unit #{unit.name}...")
    case FleetApi.Etcd.set_unit(get_fleet_api(unit.etcd_token), fleet_unit.name, fleet_unit) do
      :ok ->
        Logger.debug ("Successfully loaded unit #{unit.name}")
        true
      {:error, reason} ->
        Logger.error ("Failed to created unit #{unit.name}:  #{inspect reason}")
        false
    end
  end

  @doc """
  Method to tear down an existing unit within a fleet cluster
  
  ## Options
  
  The `unit` option define the SystemdUnit.t
   
  ## Return Values

  boolean; true if unit was destroyed
  """
  @spec teardown_unit(SystemdUnit.t) :: true | false
  def teardown_unit(unit) do
    Logger.info ("Tearing down unit #{unit.name}...")
    case FleetApi.Etcd.delete_unit(get_fleet_api(unit.etcd_token), unit.name) do
      :ok ->
        Logger.debug ("Successfully deleted unit #{unit.name}")        
        wait_for_unit_teardown(unit)
        true
      {:error, reason} ->
        Logger.error ("Failed to deleted unit #{unit.name}:  #{inspect reason}")
        false
    end
  end

  @doc false
  # Method to stall until a container has shut down
  #
  ## Options
  #
  # The `unit` option defines the Unit PID
  #
  @spec wait_for_unit_teardown(SystemdUnit.t) :: term
  defp wait_for_unit_teardown(unit) do
    Logger.info ("Verifying unit #{unit.name} has stopped...")

    refreshed_unit = get_unit(unit.name, unit.etcd_token)
    if refreshed_unit == nil || refreshed_unit.currentState == nil do
        Logger.info ("Unit #{unit.name} has stopped (#{inspect refreshed_unit.currentState}), checking active status...")
        case is_active?(refreshed_unit) do
          true -> 
            Logger.debug ("Unit #{unit.name} is still active...")
            :timer.sleep(10000)
            wait_for_unit_teardown(unit)
          {false, "activating", _, _} -> 
            Logger.debug ("Unit #{unit.name} is still starting up...")
            :timer.sleep(10000)
            wait_for_unit_teardown(unit)
          {false, _, _, _} -> 
            Logger.info ("Unit #{unit.name} is no longer active")
        end
    else
      Logger.debug ("Unit #{unit.name} is still stopping...")
      :timer.sleep(10000)
      wait_for_unit_teardown(unit)      
    end
  end

  @doc """
  Method to retrieve the journal logs associated with a Unit
  
  ## Options
  
  The `unit` option define the SystemdUnit.t
   
  ## Return Values

  tuple {:ok, stdout, stderr} | {:error, stdout, stderr}
  """
  @spec get_journal(SystemdUnit.t) :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}
  def get_journal(unit) do
    api = get_fleet_api(unit.etcd_token)

    requested_host = if (unit.machineID != nil) do
      Logger.debug("Resolving host using machineID #{unit.machineID}...")
      cluster_hosts = FleetApi.Etcd.list_machines(api)

      Enum.reduce(cluster_hosts, nil, fn(cluster_host, requested_host)->
        if ((requested_host == nil) && (requested_host != nil && requested_host.id != nil && String.contains?(requested_host.id, unit.machineID))) do
          requested_host = cluster_host
        end
        requested_host
      end)
    else
      nil
    end

    result = if requested_host != nil do
      Logger.debug("Retrieving logs from host #{inspect requested_host}...")
      execute_journal_request([requested_host], unit, true)
    else
      nil
    end

    case result do
      {:ok, stdout, stderr} -> {:ok, stdout, stderr}     
      _ -> 
        Logger.debug("Unable to retrieve logs using the unit's machineID (#{inspect requested_host}), defaulting to all hosts in cluster...")
        hosts = FleetApi.Etcd.list_machines(api)
        execute_journal_request(hosts, unit, true)
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

    Logger.debug ("Executing Fleet command:  #{resolved_cmd}")
    try do
      case System.cmd("/bin/bash", ["-c", resolved_cmd], []) do
        {stdout, 0} ->
          {:ok, read_output_file(stdout_file), read_output_file(stderr_file)}
        {stdout, return_status} ->
          Logger.debug("Host #{requested_host.primaryIP} returned an error (#{return_status}) when looking for unit #{unit.name}:\n#{read_output_file(stdout_file)}\n\n#{read_output_file(stderr_file)}")
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