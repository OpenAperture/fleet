defmodule OpenAperture.Fleet.ServiceFileParserTest do
  use ExUnit.Case

  alias OpenAperture.Fleet.ServiceFileParser, as: Parser
  @filename "test/test_service@.service"

  test "Extract sections" do
    result = Parser.parse(@filename)

    sections = 
      Enum.map(result, fn entry -> entry["section"] end)
      |> Enum.uniq

    assert sections == ["Unit", "Service", "X-Fleet"]
  end

  test "unit section" do
    result = Parser.parse(@filename)

    unit_entries = 
      Enum.filter(result, fn entry -> entry["section"] == "Unit" end)
      |> Enum.reduce(%{}, fn entry, acc -> Map.put(acc, entry["name"], entry["value"]) end)

      assert unit_entries["Description"] == "Test Service"
      assert unit_entries["After"] == "docker.service"
      assert unit_entries["Requires"] == "docker.service"
  end
end