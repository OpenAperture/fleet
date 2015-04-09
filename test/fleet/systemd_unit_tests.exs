defmodule OpenAperture.Fleet.SystemdUnit.Tests do
  use ExUnit.Case

  alias OpenAperture.Fleet.SystemdUnit

  # =======================
  # set_etcd_token Tests

  test "set_etcd_token success" do
    unit = SystemdUnit.create!(%{})
    SystemdUnit.set_etcd_token(unit, "123abc")
  end

  # =======================
  # set_assigned_port Tests

  test "set_assigned_port success" do
    unit = SystemdUnit.create!(%{})
    SystemdUnit.set_assigned_port(unit, 45000)
  end

  # =======================
  # get_assigned_port Tests

  test "get_assigned_port success" do
    unit = SystemdUnit.create!(%{})
    SystemdUnit.set_assigned_port(unit, 45000)
    assert SystemdUnit.get_assigned_port(unit) == 45000
  end

  # =======================
  # refresh Tests

  test "refresh success" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> Map.put(%{}, "name", unit_uuid) end)

    unit = SystemdUnit.create!(%{})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.get_unit_name(unit) == unit_uuid
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "refresh failed - invalid data" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> %{} end)

    unit = SystemdUnit.create!(%{"name" => unit_uuid})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.get_unit_name(unit) == unit_uuid
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "refresh failure" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> raise "bad news bears" end)

    unit = SystemdUnit.create!(%{})
    try do
      SystemdUnit.refresh(unit)
      assert true == false
    rescue e in _ ->
      assert e != nil
    end
  after
    :meck.unload(FleetApi.Etcd)   
  end 

  # =======================
  # get_unit_name Tests

  test "get_unit_name success" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> Map.put(%{"name" => "#{UUID.uuid1()}"}, "name", unit_uuid) end)

    unit = SystemdUnit.create!(%{})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.get_unit_name(unit) == unit_uuid
  after
    :meck.unload(FleetApi.Etcd)   
  end     

  # =======================
  # get_machine_id Tests

  test "get_machine_id success" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_uuid = "#{UUID.uuid1()}"
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> Map.put(%{"name" => "#{UUID.uuid1()}"}, "machineID", unit_uuid) end)

    unit = SystemdUnit.create!(%{})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.get_machine_id(unit) == unit_uuid
  after
    :meck.unload(FleetApi.Etcd)   
  end 
  
  # =======================
  # is_launched? Tests

  test "is_launched? - launched" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> Map.put(%{"name" => "#{UUID.uuid1()}"}, "currentState", "launched") end)

    unit = SystemdUnit.create!(%{})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.is_launched?(unit) == true
  after
    :meck.unload(FleetApi.Etcd)   
  end   

  test "is_launched? - not launched" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :get_unit, fn _token, _unit_name -> Map.put(%{"name" => "#{UUID.uuid1()}"}, "currentState", "deployed") end)

    unit = SystemdUnit.create!(%{})
    SystemdUnit.refresh(unit)
    assert SystemdUnit.is_launched?(unit) == {false, "deployed"}
  after
    :meck.unload(FleetApi.Etcd)   
  end

  # =======================
  # is_active? Tests

  test "is_active? - error" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> raise "bad news bears" end)

    unit = SystemdUnit.create!(%{})
    try do 
      assert SystemdUnit.is_active?(unit)
      assert true == false
    rescue e in _ ->
      assert e != nil
    end
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "is_active? - invalid response" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> nil end)

    unit = SystemdUnit.create!(%{})
    assert SystemdUnit.is_active?(unit) == {false, nil, nil, nil}
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "is_active? - unit state missing" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> [] end)

    unit = SystemdUnit.create!(%{})
    assert SystemdUnit.is_active?(unit) == {false, nil, nil, nil}
  after
    :meck.unload(FleetApi.Etcd)   
  end 

  test "is_active? - systemdActiveState inactive" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_name = "#{UUID.uuid1()}"
    state = %{}
    state = Map.put(state, "name", unit_name)
    state = Map.put(state, "systemdActiveState", "inactive")
    state = Map.put(state, "systemdLoadState", "loaded")
    state = Map.put(state, "systemdSubState", "failed")
    states = [state]
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> states end)

    unit = SystemdUnit.create!(Map.put(%{}, "name", unit_name))
    assert SystemdUnit.is_active?(unit) == {false, "inactive", "loaded", "failed"}
  after
    :meck.unload(FleetApi.Etcd)   
  end  

  test "is_active? - systemdActiveState active" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    unit_name = "#{UUID.uuid1()}"
    state = %{}
    state = Map.put(state, "name", unit_name)
    state = Map.put(state, "systemdActiveState", "active")
    state = Map.put(state, "systemdLoadState", "loaded")
    state = Map.put(state, "systemdSubState", "running")
    states = [state]
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> states end)

    unit = SystemdUnit.create!(Map.put(%{}, "name", unit_name))
    assert SystemdUnit.is_active?(unit) == true
  after
    :meck.unload(FleetApi.Etcd)   
  end   

  # =======================
  # spinup_unit Tests

  test "spinup_unit - error" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :set_unit, fn _pid, _name, _unit -> raise "bad news bears" end)

    unit = SystemdUnit.create!(%{})
    try do 
      assert SystemdUnit.spinup_unit(unit)
      assert true == false
    rescue e in _ ->
      assert e != nil
    end
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "spinup_unit - unknown response" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :set_unit, fn _pid, _name, _unit -> {:error, "bad news bears"} end)

    unit = SystemdUnit.create!(%{"name" => "#{UUID.uuid1()}", "options" => []})
    assert SystemdUnit.spinup_unit(unit) == false
  after
    :meck.unload(FleetApi.Etcd)   
  end  

  test "spinup_unit - success" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :set_unit, fn _unit, _token, _options -> :ok end)

    unit = SystemdUnit.create!(%{"name" => "#{UUID.uuid1()}", "options" => []})
    assert SystemdUnit.spinup_unit(unit) == true
  after
    :meck.unload(FleetApi.Etcd)   
  end

  # =======================
  # teardown_unit Tests

  test "teardown_unit - error" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :delete_unit, fn _unit, _token -> raise "bad news bears" end)

    unit = SystemdUnit.create!(%{})
    try do 
      assert SystemdUnit.teardown_unit(unit)
      assert true == false
    rescue e in _ ->
      assert e != nil
    end
  after
    :meck.unload(FleetApi.Etcd)   
  end

  test "teardown_unit - success" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :delete_unit, fn _unit, _token -> :ok end)
    :meck.expect(FleetApi.Etcd, :get_unit, fn _unit, _token -> {:error, %{code: 404}} end)
    unit_name = "#{UUID.uuid1()}"
    state = %{}
    state = Map.put(state, "name", unit_name)
    state = Map.put(state, "systemdActiveState", "somethingelse")
    state = Map.put(state, "systemdLoadState", "loaded")
    state = Map.put(state, "systemdSubState", "running")
    states = [state]
    :meck.expect(FleetApi.Etcd, :list_unit_states, fn _token -> states end)

    unit = SystemdUnit.create!(%{"name" => unit_name, "options" => []})
    assert SystemdUnit.teardown_unit(unit) == :ok
  after
    :meck.unload(FleetApi.Etcd)   
  end

  # =======================
  # resolve_etcd_token Tests

  test "get_journal - no machineID and no hosts" do
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [] end)

    unit = SystemdUnit.create!(%{})
    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(FleetApi.Etcd)
  end

  test "get_journal - no machineID and host success" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.expect(File, :exists?, fn _path -> false end)
    
    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 0} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn _path, _options -> "" end)
    
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [%{}] end)

    unit = SystemdUnit.create!(%{})
    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :ok
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
    :meck.unload(FleetApi.Etcd)
  end  

  test "get_journal - no machineID and host failure" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.expect(File, :exists?, fn _path -> false end)
    
    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 128} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn _path, _options -> "" end)
    
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [%{}] end)

    unit = SystemdUnit.create!(%{})
    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
    :meck.unload(FleetApi.Etcd)
  end   

  test "get_journal - machineID and host success" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.expect(File, :exists?, fn _path -> false end)
    
    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 0} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn _path, _options -> "" end)
    
    machine_id = "#{UUID.uuid1()}"
    machine = Map.put(%{}, "id", machine_id)
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [machine] end)

    unit = SystemdUnit.create!(Map.put(%{}, "machineID", machine_id))
    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :ok
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
    :meck.unload(FleetApi.Etcd)
  end  

  test "get_journal - machineID and host failure" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.expect(File, :exists?, fn _path -> false end)
    
    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 128} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn _path, _options -> "" end)
    
    machine_id = "#{UUID.uuid1()}"
    machine = Map.put(%{}, "id", machine_id)
    :meck.new(FleetApi.Etcd, [:passthrough])
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> [machine] end)

    unit = SystemdUnit.create!(Map.put(%{}, "machineID", machine_id))
    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
    :meck.unload(FleetApi.Etcd)
  end     
end