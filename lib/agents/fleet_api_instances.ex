defmodule CloudOS.Fleet.Agents.FleetAPIInstances do
    
    def start_link(_opts \\ []) do
        Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def get_instance(etcd_token) do
        Agent.get_and_update(__MODULE__, fn map ->
          case map[etcd_token] do
            nil -> 
                {:ok, pid} = FleetApi.Etcd.start_link(etcd_token)
                {pid, Map.put(map, etcd_token, pid)}
            pid ->
                {pid, map}
          end
        end)
    end
end