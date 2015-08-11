defmodule OpenAperture.Fleet.SystemdUnit.Journal.Tests do
  use ExUnit.Case

  alias OpenAperture.Fleet.SystemdUnit
  alias OpenAperture.Fleet.SystemdUnit.Journal

  setup do
    :meck.new(FleetApi.Etcd, [:passthrough])
    
    on_exit fn ->
      :meck.unload
    end
    :ok  
  end

  # =======================
  # get_journal Tests

  test "get_journal - no machineID and no hosts" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, []} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }

    {result, stdout, stderr} = SystemdUnit.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
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

    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%FleetApi.Machine{}]} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }
    {result, stdout, stderr} = Journal.get_journal(unit)
    assert result == :ok
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
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

    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%FleetApi.Machine{}]} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }
    {result, stdout, stderr} = Journal.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
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
    machine = %FleetApi.Machine{
      id: machine_id
    }
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [machine]} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: machine_id,
    }

    {result, stdout, stderr} = Journal.get_journal(unit)
    assert result == :ok
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
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
    machine = %FleetApi.Machine{
      id: machine_id
    }
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [machine]} end)

    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: machine_id,
    }
    {result, stdout, stderr} = Journal.get_journal(unit)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  after
    :meck.unload(File)
    :meck.unload(System)
    :meck.unload(EEx)
    :meck.unload(FleetApi.Etcd)
  end       

  test "execute_journal_request - handle nil" do
    unit = %SystemdUnit{
      name: "#{UUID.uuid1()}",
      desiredState: "launched",
      currentState: "deployed",        
      machineID: "#{UUID.uuid1()}",
    }
    {result, stdout, stderr} = Journal.execute_journal_request(nil, unit, true)
    assert result == :error
    assert stdout != nil
    assert stderr != nil
  end  

end