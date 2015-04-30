require Logger

defmodule OpenAperture.Fleet do
  use Supervisor

  def start(_type, _args) do
    Logger.info("Starting OpenAperture Fleet supervisor...")
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    import Supervisor.Spec

    children = [
      # Define workers and child supervisors to be supervised
      worker(OpenAperture.Fleet.FleetApiInstances, []),
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    supervise(children, opts)
  end

end
