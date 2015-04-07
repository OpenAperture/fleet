#
# == etcd_cluster.ex
#
# This module contains the logic for managing an etcd cluster
#
# == Contact
#
# Author::    Trantor (trantordevonly@perceptivesoftware.com)
# Copyright:: 2014 Lexmark International Technology S.A.  All rights reserved.
# License::   n/a
#
require Logger

defmodule CloudOS.Fleet.Agents.EtcdCluster do
  alias CloudOS.Fleet.Agents.SystemdUnit
  alias CloudOS.Fleet.Agents.FleetAPIInstances

  @doc """
  Creates a `GenServer` representing an etcd cluster.

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
  @spec create(String.t()) :: {:ok, pid} | {:error, String.t()}	
  def create(etcd_token) do
    if etcd_token == nil || String.length(etcd_token) == 0 do
      {:error, "Unable to create an EtcdCluster - an invalid etcd token was provided!"}
    else
      case Agent.start_link(fn -> %{etcd_token: etcd_token} end) do
        {:ok, cluster} -> {:ok, cluster}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Method to generate a new EtcdCluster agent

  ## Options
  
  The `etcd_token` option defines the associated etcd token.

  ## Return Values

  pid
  """
  @spec create!(String.t()) :: pid
  def create!(etcd_token) do
    case create(etcd_token) do
      {:ok, cluster} -> cluster
      {:error, reason} -> raise "Failed to create CloudOS.Fleet.Agents.EtcdCluster:  #{reason}"
    end
  end

  @doc """
  Method to retrieve the token associated with the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  ## Return Values

  String
  """ 
  @spec get_token(pid) :: List
  def get_token(cluster) do
    cluster_options = Agent.get(cluster, fn options -> options end)
    cluster_options[:etcd_token]
  end

  @doc """
  Method to retrieve the current hosts (machines) in the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  ## Return Values

  List
  """ 
  @spec get_hosts(pid) :: List
  def get_hosts(cluster) do
    case cluster
            |> fleetapi_pid_from_cluster
            |> FleetApi.Etcd.list_machines do
      {:ok, machines} ->
        machines
      {:error, reason} ->
        Logger.error("Unable to retrieve hosts for cluster #{cluster |> token_from_cluster}: #{inspect reason}")
        []
    end      
  end

  @spec fleetapi_pid_from_cluster(pid) :: pid
  defp fleetapi_pid_from_cluster(cluster) do
    cluster
      |> token_from_cluster
      |> FleetAPIInstances.get_instance
  end

  @doc """
  Method to retrieve the current units in the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  ## Return Values

  List
  """ 
  @spec get_units(pid) :: List
  def get_units(cluster) do
    case cluster
          |> fleetapi_pid_from_cluster
          |> FleetApi.Etcd.list_units do
      {:ok, units} ->
        units
      {:error, reason} -> 
        Logger.error("Unable to retrieve hosts for cluster #{cluster |> token_from_cluster}: #{inspect reason}")
        nil
    end       
  end

  @doc """
  Method to retrieve the current units in the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  ## Return Values

  List
  """ 
  @spec get_units_state(pid) :: List
  def get_units_state(cluster) do
    case cluster
          |> fleetapi_pid_from_cluster
          |> FleetApi.Etcd.list_unit_states do
      {:ok, states} ->
        states
      {:error, reason} ->
        Logger.error("Unable to retrieve any unit state in cluster #{cluster |> token_from_cluster}: #{inspect reason}")
        []
    end       
  end  

  @doc """
  Method to retrieve the number current hosts (machines) in the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  ## Return Values

  Integer
  """ 
  @spec get_host_count(pid) :: term
  def get_host_count(cluster) do

    #Find out how many machines are currently on the cluster
    hosts = get_hosts(cluster)
    if (hosts == nil) do
      0
    else
      length(hosts)
    end
  end

  @doc """
  Method to deploy new units to the cluster

  ## Options
  
  The `cluster` options defines the etcd cluster PID

  The `new_units` options defines the List of new units

  The `available_ports` optional option defines a List of ports that will be used for deployment

  ## Return Values

  List of newly deployed Units
  """ 
  @spec deploy_units(pid, List, List) :: List
  def deploy_units(cluster, new_units, available_ports \\ nil) do
    {:ok, existing_units} = cluster
                              |> fleetapi_pid_from_cluster
                              |> FleetApi.Etcd.list_units
    
    if available_ports != nil do
      instance_cnt = length(available_ports)
    else
      #legacy
      instance_cnt = get_host_count(cluster)
    end

    cycle_units(new_units, instance_cnt, cluster |> token_from_cluster, available_ports, existing_units, [])
  end

  @spec token_from_cluster(pid) :: String.t
  defp token_from_cluster(cluster) do
    Agent.get(cluster, fn options -> options end)[:etcd_token]
  end

  @doc false
  # Method to execute a rolling cycle Units on the cluster
  #
  ## Options
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `max_instance_cnt` options defines the number of servers to which the Unit will be deployed
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `available_ports` optional option defines a List of ports that will be used for deployment
  #
  # The `all_existing_units` is a List of of units currently running on the cluster
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec cycle_units(List, term, String.t(), List, List, List) :: term
  defp cycle_units([unit|remaining_units], max_instance_cnt, etcd_token, available_ports, all_existing_units, newly_deployed_units) do
    unless(unit == nil || unit["name"] == nil) do
      orig_unit_name = hd(String.split(unit["name"], ".service"))

      if (all_existing_units == nil) do
        existing_units = []
      else
        existing_units = Enum.reduce(all_existing_units, [], fn(unit, existing_units)->
          if String.contains?(unit["name"], orig_unit_name) do
            existing_units = existing_units ++ [unit]
          end
          existing_units
        end)
      end

      #if there are any instances left over (originally there were 4, now there are 3), tear them down
      {remaining_units, newly_deployed_units, remaining_ports} = cycle_unit(unit, 0, max_instance_cnt, available_ports, etcd_token, {existing_units, [], []})
      teardown_units(remaining_units, etcd_token)
    else
      remaining_ports = available_ports
    end

    cycle_units(remaining_units, max_instance_cnt, etcd_token, remaining_ports, all_existing_units, newly_deployed_units)
  end

  @doc false
  # Method to execute a rolling cycle Units on the cluster.  Ends recursion
  #
  ## Options
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `max_instance_cnt` options defines the number of servers to which the Unit will be deployed
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `available_ports` optional option defines a List of ports that will be used for deployment
  #
  # The `all_existing_units` is a List of of units currently running on the cluster
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec cycle_units(List, term, String.t(), List, List, List) :: term
  defp cycle_units([], _, _, _, _, newly_deployed_units) do
    newly_deployed_units
  end

  @doc false
  # Method to execute a rolling cycle of a Unit on the cluster
  #
  ## Options
  #
  # The `[unit|remaining_units]` options defines the list of Units
  #
  # The `cur_instance_id` options defines the unique instance identifier for this unit on the cluster
  #
  # The `max_instance_cnt` options defines the number of servers to which the Unit will be deployed
  #
  # The `etcd_token` is the string containing the etcd token
  #
  # The `available_ports` optional option defines a List of ports that will be used for deployment
  #
  # The `all_existing_units` is a List of of units currently running on the cluster
  #
  # The `newly_deployed_units` is a List of of units that were spun up during this cycle
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec cycle_unit(term, term, term, List, String.t(), term) :: term
  defp cycle_unit(unit, cur_instance_id, max_instance_cnt, available_ports, etcd_token, {existing_units, newly_deployed_units, remaining_ports}) do
    if (cur_instance_id >= max_instance_cnt) do
      #if we've maxed out our unit count, stop and return any existing units that need to be terminated
      {existing_units, newly_deployed_units, remaining_ports}
    else
      resolved_unit = Map.put(unit, "desiredState", "launched")

      #fleet_api requires that name be an atom, so ensure that it's present
      if (resolved_unit[:name] == nil && resolved_unit["name"] != nil) do
        orig_unit_name = hd(String.split(resolved_unit["name"], ".service"))
        unit_instance_name = "#{orig_unit_name}#{cur_instance_id}.service"
        resolved_unit = Map.put(resolved_unit, :name, unit_instance_name)
        resolved_unit = Map.put(resolved_unit, "name", unit_instance_name)
      end

      #check to see if a unit with the same name already is running
      existing_unit = Enum.reduce(existing_units, nil, fn(cur_unit, existing_unit)->
        if ((existing_unit == nil) && String.contains?(cur_unit["name"], resolved_unit["name"])) do
          existing_unit = cur_unit
        end
        existing_unit
      end)

      #if the same unit name is running, stop it and track the remaining units
      if (existing_unit != nil) do
        teardown_units([existing_unit], etcd_token)
        remaining_units = List.delete(existing_units, existing_unit)
      else
        remaining_units = existing_units
      end

      #spin through and determine if we need to swap out the port
      if available_ports != nil do
        port = List.first(available_ports)
        available_ports = List.delete_at(available_ports, 0)
      else
        port = 0
      end
            
      if resolved_unit["options"] != nil && length(resolved_unit["options"]) > 0 do
        new_options= Enum.reduce resolved_unit["options"], [], fn (option, new_options) ->
          if String.contains?(option["value"], "<%=") do
            updated_option_value = EEx.eval_string(option["value"], [dst_port: port])
            updated_option = Map.put(option, "value", updated_option_value)
          else
            updated_option = option
          end

          new_options ++ [updated_option]
        end
        resolved_unit = Map.put(resolved_unit, "options", new_options)
      end
      
      #spin up the new unit
      case SystemdUnit.create(resolved_unit) do
        {:ok, deployed_unit} ->
          case SystemdUnit.spinup_unit(deployed_unit, etcd_token) do
            true ->
              SystemdUnit.set_etcd_token(deployed_unit, etcd_token)
              SystemdUnit.set_assigned_port(deployed_unit, port)
              newly_deployed_units = newly_deployed_units ++ [deployed_unit]
            false ->
              Logger.error("Unable to monitor instance #{resolved_unit["name"]}")
          end
        {:error, reason} -> Logger.error("Failed to create systemd unit for #{resolved_unit["name"]}:  #{reason}")
      end

      #continue to spin up new units
      cycle_unit(unit, cur_instance_id+1, max_instance_cnt, available_ports, etcd_token, {remaining_units, newly_deployed_units, available_ports})
    end
  end

  @doc false
  # Method to tear down an existing unit within a fleet cluster
  #
  ## Options
  #
  # The `unit` and `remaining_units` options are the fleet Units to be deleted.
  #
  @spec teardown_units(List, String.t()) :: term
  defp teardown_units([unit|remaining_units], etcd_token) do
    case SystemdUnit.create(unit) do
      {:ok, deployed_unit} -> 
        SystemdUnit.set_etcd_token(deployed_unit, etcd_token)
        SystemdUnit.teardown_unit(deployed_unit, etcd_token)
      {:error, reason} -> Logger.error("Unable to teardown unit #{unit["name"]}:  #{reason}")
    end
    
    teardown_units(remaining_units, etcd_token)
  end

  @doc false
  # Method to tear down an existing unit within a fleet cluster
  #
  ## Options
  #
  # The List option are the fleet Units to be deleted.  Ends recursion.
  #
  @spec teardown_units(List, String.t()) :: term
  defp teardown_units([], etcd_token) do
    Logger.info ("Finished tearing down all previous units in cluster #{etcd_token}")
  end  
end