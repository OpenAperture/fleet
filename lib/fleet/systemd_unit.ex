require Logger

defmodule OpenAperture.Fleet.SystemdUnit do
  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.FleetApiInstances
  alias OpenAperture.Fleet.SystemdUnit.Journal
  alias OpenAperture.Fleet.SystemdUnit.KillUnit

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
  def get_fleet_api(etcd_token) do
    Logger.debug("Retrieving FleetApi instance...")
    instance = FleetApiInstances.get_instance(etcd_token)
    Logger.debug("Found FleetApi instance...")
    instance
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
    try do
      Logger.debug("Retrieving units on cluster #{etcd_token}...")
      api = get_fleet_api(etcd_token)

      Logger.debug("Executing list-units call to #{etcd_token}...")
      units = case FleetApi.Etcd.list_units(api) do
        {:ok, nil} ->
          Logger.error("FleetApi returned invalid units for cluster #{etcd_token}")
          nil
        {:ok, units} -> units
        {:error, reason} ->
          Logger.error("Failed to retrieve units on cluster #{etcd_token}:  #{inspect reason}")
          nil
      end

      Logger.debug("Retrieving unit states on cluster #{etcd_token}...")
      unit_states_by_name = case FleetApi.Etcd.list_unit_states(api) do
        {:ok, nil} ->
          Logger.error("FleetApi returned invalid unit states for cluster #{etcd_token}")
          %{}
        {:ok, unit_states} ->
          Enum.reduce unit_states, %{}, fn(unit_state, unit_states_by_name) ->
            Map.put(unit_states_by_name, unit_state.name, unit_state)
          end
        {:error, reason} ->
          Logger.error("Failed to retrieve unit states on cluster #{etcd_token}:  #{inspect reason}")
          %{}
      end

      if units == nil do
        Logger.debug("There were no valid units found on cluster cluster #{etcd_token}, resolving SystemdUnit units via unit states...")
        Enum.reduce Map.values(unit_states_by_name), [], fn(unit_state, systemd_units) ->
          systemd_units ++ [build_unit(etcd_token, nil, unit_state)]
        end
      else
        Logger.debug("Resolving SystemdUnit units...")
        Enum.reduce units, [], fn(unit, systemd_units) ->
          systemd_units ++ [build_unit(etcd_token, unit, unit_states_by_name[unit.name])]
        end
      end
    catch
      :exit, code   ->
        Logger.error("[SystemdUnit] Failed to retrieve fleet api for cluster #{etcd_token}:  Exited with code #{inspect code}")
        nil
      :throw, value ->
        Logger.error("[SystemdUnit] Failed to retrieve fleet api for cluster #{etcd_token}:  Throw called with #{inspect value}")
        nil
      what, value   ->
        Logger.error("[SystemdUnit] Failed to retrieve fleet api for cluster #{etcd_token}:  Caught #{inspect what} with #{inspect value}")
        nil
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
    kill_unit(unit)
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

  @spec get_journal(SystemdUnit.t) :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}
  def get_journal(unit) do
    Journal.get_journal(unit)
  end

  @spec kill_unit(SystemdUnit.t) :: {:ok | :error, String.t, String.t}
  def kill_unit(unit) do
    KillUnit.kill_unit(unit)
  end
end