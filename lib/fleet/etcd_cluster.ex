require Logger

defmodule OpenAperture.Fleet.EtcdCluster do
  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.FleetApiInstances

  @moduledoc """
  This module contains logic to interact with EtcdClusters and SystemdUnit modules
  """

  @spec get_fleet_api(pid) :: pid
  defp get_fleet_api(etcd_token) do
    FleetApiInstances.get_instance(etcd_token)
  end

  @doc """
  Method to retrieve the current hosts (machines) in the cluster

  ## Options

  The `etcd_token` options defines the etcd token of the cluster

  ## Return Values

  List
  """
  @spec get_hosts(String.t) :: List
  def get_hosts(etcd_token) do
    case  etcd_token
          |> get_fleet_api
          |> FleetApi.Etcd.list_machines do
      {:ok, machines} -> machines
      {:error, reason} ->
        Logger.error("Unable to retrieve hosts for cluster #{etcd_token}: #{inspect reason}")
        []
    end
  end

  @doc """
  Method to retrieve the number current hosts (machines) in the cluster

  ## Options

  The `etcd_token` options defines the etcd token of the cluster

  ## Return Values

  Integer
  """
  @spec get_host_count(String.t) :: term
  def get_host_count(etcd_token) do

    #Find out how many machines are currently on the cluster
    hosts = get_hosts(etcd_token)
    if (hosts == nil) do
      0
    else
      length(hosts)
    end
  end

  @doc """
  Method to deploy new units to the cluster

  ## Options

  The `etcd_token` options defines the etcd token of the cluster

  The `new_units` options defines the List of new units

  The `available_ports` optional option defines a List of ports that will be used for deployment

  ## Return Values

  List of newly deployed Units
  """
  @spec deploy_units(String.t, List, List) :: List
  def deploy_units(etcd_token, new_units, map_available_ports \\ nil) do
    case SystemdUnit.get_units(etcd_token) do
      nil ->
        Logger.error("Unable to deploy units; failed to retrieve existing units!")
        nil
      existing_units ->
        cycle_units(etcd_token, new_units, existing_units, map_available_ports, [])
    end
  end

  @doc false
  # Method to execute a rolling cycle Units on the cluster.  Ends recursion
  #
  ## Options
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `existing_units` is a List of of units currently running on the cluster
  #
  # The `map_available_port` option defines a Map of ports that can be used for units during deployment
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec cycle_units(String.t, [], List, Map, List) :: List
  defp cycle_units(_etcd_token, [], _existing_units, _map_available_ports, newly_deployed_units) do
    newly_deployed_units
  end

  @doc false
  # Method to execute a rolling cycle Units on the cluster.
  #
  ## Options
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `existing_units` is a List of of units currently running on the cluster
  #
  # The `map_available_port` option defines a Map of ports that can be used for units during deployment
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec cycle_units(String.t, List, List, Map, List) :: List
  defp cycle_units(etcd_token, [unit|remaining_units], all_existing_units, map_available_ports, deployed_units) do
    orig_unit_name = List.first(Regex.split(~r/@(\d+)?.service/, unit.name))

    {max_instance_cnt, available_ports} = if map_available_ports != nil do
      available_ports = map_available_ports[unit.name]
      if available_ports != nil do
        {length(available_ports), available_ports}
      else
        Logger.warn("There are an invalid number of ports available for unit #{orig_unit_name}, defaulting to cluster host count")
        {get_host_count(etcd_token), nil}
      end
    else
      #legacy (i.e. no dynamic port mappings)
      {get_host_count(etcd_token), nil}
    end

    Logger.info("Cycling unit #{orig_unit_name} on cluster #{etcd_token}, new instance count will be #{max_instance_cnt}...")

    existing_units = if (all_existing_units == nil) do
      Logger.debug("There are currently no units running on cluster #{etcd_token}")
      []
    else
      Logger.debug("There are currently #{length(all_existing_units)} units running on cluster #{etcd_token}")
      Enum.reduce(all_existing_units, [], fn(unit, existing_units)->
        if String.contains?(unit.name, "#{orig_unit_name}@") do
          existing_units = existing_units ++ [unit]
        end
        existing_units
      end)
    end

    #if there are any instances left over (originally there were 4, now there are 3), tear them down
    Logger.info("There are currently #{length(existing_units)} instances of unit #{orig_unit_name} remaining on the cluster")
    {remaining_existing_units, newly_deployed_units} = cycle_unit(etcd_token, unit, 0, max_instance_cnt, available_ports, {existing_units, []})
    Logger.debug("Cycling unit #{orig_unit_name} has resulted in #{length(newly_deployed_units)} new units")
    teardown_units(etcd_token, remaining_existing_units)
    cycle_units(etcd_token, remaining_units, all_existing_units, map_available_ports, deployed_units ++ newly_deployed_units)
  end

  @doc false
  # Method to execute a rolling cycle of a Unit on the cluster
  #
  ## Options
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `cur_instance_id` options defines the unique instance identifier for this unit on the cluster
  #
  # The `max_instance_cnt` options defines the number of servers to which the Unit will be deployed
  #
  # The `available_ports` option defines a List of ports that will be used for deployment
  #
  # The `existing_units` is a List of of units currently running on the cluster
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # {List of existing units, List of newly deployed units}
  #
  @spec cycle_unit(String.t, FleetApi.Unit.t, term, term, Map, {List, List}) :: {List, List}
  defp cycle_unit(etcd_token, unit, cur_instance_id, max_instance_cnt, available_ports, {existing_units, newly_deployed_units}) do
    if (cur_instance_id >= max_instance_cnt) do
      #if we've maxed out our unit count, stop and return any existing units that need to be terminated
      {existing_units, newly_deployed_units}
    else
      orig_unit_name = List.first(Regex.split(~r/@(\d+)?.service/, unit.name))
      resolved_unit = %{ unit | name: "#{orig_unit_name}@#{cur_instance_id}.service"}
      resolved_unit = %{ resolved_unit | desiredState: "launched"}

      Logger.debug("Resolved unit name #{orig_unit_name} to unit instance name #{resolved_unit.name}")

      #check to see if a unit with the same name already is running
      existing_unit = Enum.reduce(existing_units, nil, fn(cur_unit, existing_unit)->
        if ((existing_unit == nil) && String.contains?(cur_unit.name, resolved_unit.name)) do
          existing_unit = cur_unit
        end
        existing_unit
      end)

      #if the same unit name is running, stop it and track the remaining units
      remaining_units = if (existing_unit != nil) do
        teardown_units(etcd_token, [existing_unit])
        List.delete(existing_units, existing_unit)
      else
        existing_units
      end

      #spin through and determine if we need to swap out the port
      {port, remaining_ports} = if available_ports != nil do
        {List.first(available_ports), List.delete_at(available_ports, 0)}
      else
        {0, nil}
      end

      resolved_unit = if resolved_unit.options != nil && length(resolved_unit.options) > 0 do
        new_options = Enum.reduce resolved_unit.options, [], fn (option, new_options) ->
          updated_option = if String.contains?(option.value, "<%=") do
            updated_option_value = EEx.eval_string(option.value, [dst_port: port])
            %{option | value: updated_option_value}
          else
            option
          end

          new_options ++ [updated_option]
        end
        %{ resolved_unit | options: new_options}
      else
        resolved_unit
      end

      #spin up the new unit
      systemd_unit = SystemdUnit.from_fleet_unit(etcd_token, resolved_unit)
      systemd_unit = %{systemd_unit | dst_port: port}

      Logger.info("Spinning up unit #{systemd_unit.name} on cluster #{etcd_token}...")
      newly_deployed_units = case SystemdUnit.spinup_unit(systemd_unit) do
        true ->
          Logger.info("Successfully spun up unit #{systemd_unit.name} on cluster #{etcd_token}")
          newly_deployed_units ++ [systemd_unit]
        false ->
          Logger.info("Failed to spin up unit #{systemd_unit.name} on cluster #{etcd_token}!")
          newly_deployed_units
      end

      #continue to spin up new units
      cycle_unit(etcd_token, unit, cur_instance_id+1, max_instance_cnt, remaining_ports, {remaining_units, newly_deployed_units})
    end
  end

  @doc false
  # Method to tear down an existing unit within a fleet cluster
  #
  ## Options
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The List option is the fleet Units to be deleted.  Ends recursion.
  #
  @spec teardown_units(String.t, []) :: term
  defp teardown_units(etcd_token, []) do
    Logger.info ("Finished tearing down all previous units in cluster #{etcd_token}")
  end

  @doc false
  # Method to tear down an existing unit within a fleet cluster
  #
  ## Options
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The List option is the fleet Units to be deleted.
  #
  @spec teardown_units(String.t, List) :: term
  defp teardown_units(etcd_token, [unit|remaining_units]) do
    Logger.info("Tearing down unit #{unit.name} on cluster #{etcd_token}")
    SystemdUnit.teardown_unit(unit)
    Logger.info("Successfully tore down unit #{unit.name} on cluster #{etcd_token}")
    teardown_units(etcd_token, remaining_units)
  end
end