defmodule OpenAperture.Fleet.EtcdCluster.Tests do
  use ExUnit.Case

  alias OpenAperture.Fleet.EtcdCluster
  alias OpenAperture.Fleet.SystemdUnit

  setup do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.new(SystemdUnit, [:passthrough])
    
    on_exit fn ->
      :meck.unload
    end
    :ok  
  end

  # =======================
  # get_hosts Tests
  
  test "get_hosts success" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, []} end)
    assert EtcdCluster.get_hosts("123abc") == []
  end

  test "get_hosts fail" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:error, "bad news bears"} end)
    assert EtcdCluster.get_hosts("123abc") == []
  end

  # =======================
  # deploy_units

  test "deploy_units - no units" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _fleet_pid -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _fleet_pid -> {:ok, []} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)

    assert EtcdCluster.deploy_units("123abc", []) == []
  end  

  test "deploy_units - no units and specify ports" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _fleet_pid -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _fleet_pid -> {:ok, []} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)

    new_units = []
    ports = [1, 2, 3, 4, 5]
    assert EtcdCluster.deploy_units("123abc", new_units, ports) == []
  end  

  test "deploy_units - unit without .service suffix" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _fleet_pid -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _fleet_pid -> {:ok, []} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)

    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}@.service"
    }
    new_units = [unit1]
    assert EtcdCluster.deploy_units("123abc", new_units) == []
  end 

  test "deploy_units - units with spinup failing" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, []} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)    
    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> false end)

    unit1 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}@.service"
    }
    unit2 = %FleetApi.Unit{
      name: "#{UUID.uuid1()}@.service"
    }

    new_units = [unit1, unit2]
    assert EtcdCluster.deploy_units("123abc", new_units) == []
  end  
   
  test "deploy_units - success" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%{}]} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> true end)

    unit1_id = "#{UUID.uuid1()}"
    unit1 = %FleetApi.Unit{
      name: "#{unit1_id}@.service"
    }
    unit2_id = "#{UUID.uuid1()}"
    unit2 = %FleetApi.Unit{
      name: "#{unit2_id}@.service"
    }
    new_units = [unit1, unit2]
    deployed_units = EtcdCluster.deploy_units("123abc", new_units)
    assert deployed_units != nil
    assert length(deployed_units) == 2

    deployed_unit = List.first(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)

    deployed_unit = List.last(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)
  end   

  test "deploy_units - success with invalid ports" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%{}]} end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> true end)

    unit1_id = "#{UUID.uuid1()}"
    unit1 = %FleetApi.Unit{
      name: "#{unit1_id}@.service"
    }
    unit2_id = "#{UUID.uuid1()}"
    unit2 = %FleetApi.Unit{
      name: "#{unit2_id}@.service"
    }
    new_units = [unit1, unit2]

    available_ports = %{}
    available_ports = Map.put(available_ports, unit1.name, nil)
    available_ports = Map.put(available_ports, unit2.name, [2345, 56789])

    deployed_units = EtcdCluster.deploy_units("123abc", new_units, available_ports)
    assert deployed_units != nil
    assert length(deployed_units) == 3

    deployed_unit = List.first(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)

    deployed_unit = List.last(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)
  end

  test "deploy_units - success with provided ports" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [%{}] end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> true end)

    unit1_id = "#{UUID.uuid1()}"
    unit1 = %FleetApi.Unit{
      name: "#{unit1_id}@.service"
    }
    unit2_id = "#{UUID.uuid1()}"
    unit2 = %FleetApi.Unit{
      name: "#{unit2_id}@.service"
    }
    new_units = [unit1, unit2]
    available_ports = %{}
    available_ports = Map.put(available_ports, unit1.name, [12345, 67890])
    available_ports = Map.put(available_ports, unit2.name, [2345, 56789])

    deployed_units = EtcdCluster.deploy_units("123abc", new_units, available_ports)
    assert deployed_units != nil
    assert length(deployed_units) == 4

    Enum.reduce deployed_units, nil, fn (deployed_unit, _errors) ->
      assert deployed_unit != nil
      assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)      
    end
  end

  test "deploy_units - success with template options" do
    :meck.expect(FleetApi.Etcd, :list_units, fn _token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [%{}] end)

    :meck.expect(SystemdUnit, :get_units, fn _ -> {:ok, []} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> true end)

    unit1_id = "#{UUID.uuid1()}"
    unit1 = %FleetApi.Unit{
      name: "#{unit1_id}@.service",
      options: [
        %FleetApi.UnitOption{
          value: "<%= dst_port %>"
        }
      ]
    }
    unit2_id = "#{UUID.uuid1()}"
    unit2 = %FleetApi.Unit{
      name: "#{unit2_id}@.service"
    }
    new_units = [unit1, unit2]
    available_ports = %{}
    available_ports = Map.put(available_ports, unit1.name, [12345, 67890])
    available_ports = Map.put(available_ports, unit2.name, [2345, 56789])

    deployed_units = EtcdCluster.deploy_units("123abc", new_units, available_ports)
    assert deployed_units != nil
    assert length(deployed_units) == 4

    Enum.reduce deployed_units, nil, fn (deployed_unit, _errors) ->
      assert deployed_unit != nil
      assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)      
    end
  end    

  test "deploy_units - teardown previous units" do
    unit1_id = "#{UUID.uuid1()}"
    unit1 = %FleetApi.Unit{
      name: "#{unit1_id}@.service"
    }
    unit2_id = "#{UUID.uuid1()}"
    unit2 = %FleetApi.Unit{
      name: "#{unit2_id}@.service"
    }

    :meck.expect(SystemdUnit, :get_units, fn _token -> {:ok, [
      %SystemdUnit{
        name: "#{unit1_id}@.service"
      },
      %SystemdUnit{
        name: "#{unit2_id}@.service"
      }
    ]} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%{}]} end)

    :meck.expect(SystemdUnit, :spinup_unit, fn _ -> true end)
    :meck.expect(SystemdUnit, :teardown_unit, fn _ -> true end)


    new_units = [unit1, unit2]

    deployed_units = EtcdCluster.deploy_units("123abc", new_units)
    assert deployed_units != nil
    assert length(deployed_units) == 2

    deployed_unit = List.first(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)

    deployed_unit = List.last(deployed_units)
    assert deployed_unit != nil
    assert String.contains?(deployed_unit.name, unit1_id) || String.contains?(deployed_unit.name, unit2_id)
  end  
end