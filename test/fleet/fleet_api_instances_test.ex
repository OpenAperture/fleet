defmodule OpenAperture.Fleet.FleetAPIInstances.Tests do
  use ExUnit.Case
  alias OpenAperture.Fleet.FleetAPIInstances

  test "caches pid" do
  	pid1 = FleetAPIInstances.get_instance("my_token")
  	pid2 = FleetAPIInstances.get_instance("my_token")
  	assert pid1 == pid2
  end
end