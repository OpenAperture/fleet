require Logger

defmodule OpenAperture.Fleet.CommonSystemdUtils do

  @spec read_output_file(String.t) :: String.t
  def read_output_file(output_file) do
    if File.exists?(output_file) do
      case File.read(output_file) do
        {:ok, content} -> content
        {:error, reason} ->
          Logger.error("Unable to read file #{output_file}:  #{inspect reason}")
          ""
      end
    else
      Logger.error("Unable to read systemd output file #{output_file} - file does not exist!")
      ""
    end
  end
end