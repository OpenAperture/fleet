defmodule CloudOS.Fleet.Agents.EtcdCluster.Tests do
  use ExUnit.Case

  alias CloudOS.Fleet.Agents.EtcdCluster
  alias CloudOS.Fleet.Agents.SystemdUnit

  # =======================
  # get_hosts Tests

  setup do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.new(SystemdUnit, [:passthrough])
    
    on_exit fn ->
      :meck.unload
    end
    :ok  
  end

  test "get_hosts success" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> {:ok, []} end)

    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_hosts(cluster) == []
  end

  test "get_hosts fail" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> {:error, "bad news bears"} end)

    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_hosts(cluster) == []
  end

  # =======================
  # get_units Tests

  test "get_units success" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_units(cluster) == []
  end

  test "get_units fail" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:error, "bad news bears"} end)

    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_units(cluster) == nil
  end 
  
  # =======================
  # get_units Tests

  test "get_units_state success" do
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn token -> {:ok, []} end)

    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_units_state(cluster) == []
  end

  test "get_units_state fail" do
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn token -> {:error, "bad news bears"} end)

    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.get_units_state(cluster) == []
  end   

  # =======================
  # deploy_units

  test "deploy_units - no units" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)

    cluster = EtcdCluster.create!("123abc")
    new_units = []
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  end

  test "deploy_units - no units and specify ports" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)

    cluster = EtcdCluster.create!("123abc")
    new_units = []
    ports = [1, 2, 3, 4, 5]
    assert EtcdCluster.deploy_units(cluster, new_units, ports) == []
  end

  test "deploy_units - unit without .service suffix" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}")
    new_units = [unit1]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  end 

  test "deploy_units - units with create failing" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:error, "bad news bears"} end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  end   

  test "deploy_units - units with spinup failing" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    
    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> false end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  end  

  test "deploy_units - success" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == [%{}]
  end  

  test "deploy_units - success with provided ports" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    available_ports = [12345, 67890]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units, available_ports) == [%{}, %{}]
  end  

  test "deploy_units - success with template options" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, []} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit1 = Map.put(unit1, "options", [
      %{
        "value" => "<%= dst_port %>"
      }])

    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    available_ports = [12345, 67890]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units, available_ports) == [%{}, %{}]
  end    

  test "deploy_units - teardown previous units" do
    :meck.expect(FleetApi.Etcd, :list_units, fn token -> {:ok, [Map.put(%{}, "name", "test_unit")]} end)
    :meck.expect(FleetApi.Etcd, :list_machines, fn token -> {:ok, [%{}]} end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :teardown_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == [%{}]
  end
end