defmodule OpenAperture.Fleet.SystemdUnit.KillUnit.Tests do
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

  test "kill_unit no machines" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, []} end)
    :meck.new(KillUnit, [:passthrough])
    host_count_agent = SimpleAgent.start! 0
    :meck.expect(KillUnit, :kill_unit_on_host, fn _,_ -> SimpleAgent.increment! host_count_agent; :ok end)

    assert KillUnit.kill_unit(%SystemdUnit{}) == :ok
    assert SimpleAgent.get!(host_count_agent) == 0
  end

  test "kill_unit success" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%{}, %{}, %{}]} end)
    :meck.new(KillUnit, [:passthrough])
    host_count_agent = SimpleAgent.start! 0
    :meck.expect(KillUnit, :kill_unit_on_host, fn _,_ -> SimpleAgent.increment! host_count_agent; :ok end)

    assert KillUnit.kill_unit(%SystemdUnit{}) == :ok
    assert SimpleAgent.get!(host_count_agent) == 3
  end

  test "kill_unit failures" do
    :meck.expect(FleetApi.Etcd, :list_machines, fn _token -> {:ok, [%{}, %{}, %{}]} end)
    :meck.new(KillUnit, [:passthrough])
    host_count_agent = SimpleAgent.start! 0
    :meck.expect(KillUnit, :kill_unit_on_host, fn _,_ -> SimpleAgent.increment! host_count_agent; :error end)

    assert KillUnit.kill_unit(%SystemdUnit{}) == :error
    assert SimpleAgent.get!(host_count_agent) == 3
  end

  test "kill_unit_on_host success" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn path, options -> assert String.ends_with?(path, "/templates/fleetctl-kill.sh.eex"); [host_ip: "1.2.3.4", unit_name: "my_unit_name", verify_result: true] = options; "" end)

    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 0} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    assert KillUnit.kill_unit_on_host(%SystemdUnit{name: "my_unit_name"}, %FleetApi.Machine{primaryIP: "1.2.3.4"}) == :ok
  end

  test "kill_unit_on_host failure" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :mkdir_p, fn _path -> true end)
    :meck.expect(File, :write!, fn _path, _contents -> true end)
    :meck.expect(File, :rm_rf, fn _path -> true end)
    :meck.expect(File, :exists?, fn _path -> true end)
    :meck.expect(File, :read!, fn _path -> "" end)
    :meck.new(EEx, [:unstick])
    :meck.expect(EEx, :eval_file, fn path, options -> assert String.ends_with?(path, "/templates/fleetctl-kill.sh.eex"); [host_ip: "1.2.3.4", unit_name: "my_unit_name", verify_result: true] = options; "" end)

    :meck.new(System, [:unstick])
    :meck.expect(System, :cmd, fn _cmd, _opts, _opts2 -> {"", 128} end)
    :meck.expect(System, :cwd!, fn -> "" end)

    assert KillUnit.kill_unit_on_host(%SystemdUnit{name: "my_unit_name"}, %FleetApi.Machine{primaryIP: "1.2.3.4"}) == :error
  end

end