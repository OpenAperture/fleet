defmodule OpenAperture.Fleet.SystemdUnit.Tests do
  use ExUnit.Case

  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.SystemdUnit.KillUnit

  setup do
    :meck.new(FleetApi.Etcd, [:passthrough])
    
    on_exit fn ->
      :meck.unload
    end
    :ok  
  end

  # =======================
  # from_fleet_unit Tests

  test "from_fleet_unit success" do
    unit = SystemdUnit.from_fleet_unit("#{UUID.uuid1()}", %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    })
    assert unit != nil
  end

  # =======================
  # get_units Tests

  def compare_fleet_unit_fields(original_unit, returned_unit) do
    assert original_unit != nil

    assert returned_unit != nil
    assert returned_unit.name == original_unit.name
    assert returned_unit.desiredState == original_unit.desiredState
    assert returned_unit.currentState == original_unit.currentState
    assert returned_unit.machineID == original_unit.machineID    
    assert returned_unit.options == original_unit.options    
  end

  test "get_units success" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :list_units, fn _ -> {:ok, [unit1, unit2]} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:ok, []} end)

    returned_units = SystemdUnit.get_units("123abc")
    assert returned_units != nil
    assert length(returned_units) == 2

    compare_fleet_unit_fields(unit1, List.first(returned_units))
    compare_fleet_unit_fields(unit2, List.last(returned_units))
  after
    :meck.unload(FleetApi.Etcd)
  end

  test "get_units list_unit_states failed" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :list_units, fn _ -> {:ok, [unit1, unit2]} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:error, "bad news bears"} end)

    returned_units = SystemdUnit.get_units("123abc")
    assert returned_units != nil
    assert length(returned_units) == 2

    compare_fleet_unit_fields(unit1, List.first(returned_units))
    compare_fleet_unit_fields(unit2, List.last(returned_units))
  after
    :meck.unload(FleetApi.Etcd)
  end

  test "get_units list_units failed" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :list_units, fn _ -> {:error, "bad news bears"} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:ok, []} end)

    returned_units = SystemdUnit.get_units("123abc")
    assert returned_units == []
  after
    :meck.unload(FleetApi.Etcd)
  end

  # ================================
  # get_unit tests

  test "get_unit success" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _,_ -> {:ok, unit1} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:ok, [%FleetApi.UnitState{}]} end)

    returned_unit = SystemdUnit.get_unit("123abc", "name")
    assert returned_unit != nil
    compare_fleet_unit_fields(unit1, returned_unit)
  after
    :meck.unload(FleetApi.Etcd)
  end

  test "get_unit list_unit_states failed" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _,_ -> {:ok, unit1} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:error, "bad news bears"} end)

    returned_unit = SystemdUnit.get_unit("123abc", "name")
    assert returned_unit != nil
    compare_fleet_unit_fields(unit1, returned_unit)
  after
    :meck.unload(FleetApi.Etcd)
  end

  test "get_unit list_units failed" do
    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _,_ -> {:error, "bad news bears"} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:ok, []} end)

    returned_unit = SystemdUnit.get_unit("123abc", "name")
    assert returned_unit != nil
  after
    :meck.unload(FleetApi.Etcd)
  end

  # =======================
  # is_launched? Tests

  test "is_launched? - launched" do
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "launched",        
      machineID: "#{UUID.uuid1()}",
    }

    assert SystemdUnit.is_launched?(unit) == true  
  end   

  test "is_launched? - not launched" do
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }

    assert SystemdUnit.is_launched?(unit) == {false, "deployed"}
  end

  # =======================
  # is_active? Tests

  test "is_active? - error" do
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      systemdActiveState: "inactive"
    }

    assert SystemdUnit.is_active?(unit) == {false, "inactive", nil, nil}
  end

  test "is_active? - systemdActiveState active" do
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      systemdActiveState: "active"
    }

    assert SystemdUnit.is_active?(unit) == true
  end

  # =======================
  # spinup_unit Tests

  test "spinup_unit - error" do
    :meck.expect(FleetApi.Etcd, :set_unit, fn _pid, _name, _unit -> {:error, "bad news bears"} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }
    
    assert SystemdUnit.spinup_unit(unit) == false
  end

  test "spinup_unit - success" do
    :meck.expect(FleetApi.Etcd, :set_unit, fn _pid, _name, _unit -> :ok end)
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }

    assert SystemdUnit.spinup_unit(unit) == true
  end  

  # =======================
  # teardown_unit Tests

  test "teardown_unit - error" do
    :meck.expect(FleetApi.Etcd, :delete_unit, fn _unit, _token -> {:error, "bad news bears"} end)
    :meck.new(KillUnit)
    :meck.expect(KillUnit, :kill_unit, fn _ -> :ok end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }

    assert SystemdUnit.teardown_unit(unit) == false
  end

  test "teardown_unit - success" do
    refreshed_unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      systemdActiveState: "inactive"
    }

    :meck.expect(FleetApi.Etcd, :delete_unit, fn _unit, _token -> :ok end)
    :meck.expect(FleetApi.Etcd, :get_unit, fn _unit, _token -> {:ok, refreshed_unit} end)
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _ -> {:ok, [%FleetApi.UnitState{}]} end)
    :meck.new(KillUnit)
    :meck.expect(KillUnit, :kill_unit, fn _ -> :ok end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }

    assert SystemdUnit.teardown_unit(unit) == true
  end  
end