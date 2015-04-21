require Logger

defmodule OpenAperture.Fleet.ServiceFileParser do

  @moduledoc """
  This module contains logic to parse Fleet service files into usable Fleet UnitOptions.
  """

  @doc """
  Method to parse a Fleet service file into usable Fleet Unit object.

  ## Options

  The `filepath` option is an absolute file location containing the service file.

  ## Return values

  List containing the UnitOptions
  """
  @spec parse(String.t()) :: List
  def parse(filepath) do
    Logger.info("Parsing service file #{filepath}...")
    if File.exists?(filepath) do
      input_file = File.open!(filepath, [:read, :utf8])
      process_file(input_file, "", [])
    else
      Logger.error("Unable to parse service file - file #{filepath} doesn't exist!")
      nil
    end
  end

  @doc false
  # Method to loop through the file and parse each line into a UnitOption
  #
  ## Options
  #
  # The `input_file` option is the contains of the File, line by line.
  #
  # The `current_section` option is the string representing the current section of the options.
  #
  # The `unit_options` option contains the List of currently known UnitOptions.
  #
  ## Return Values
  #
  # The List of all known UnitOptions
  #
  @spec process_file(term, String.t(), List) :: List
  defp process_file(input_file, current_section, unit_options) do
    line = IO.read(input_file, :line)
    if (line != :eof) do
      current_line = String.strip(line)
      if (String.starts_with? current_line, "[") do
        current_section = String.slice(current_line, 1, 100)
        current_section = String.slice(current_section, 0, String.length(current_section)-1)
        process_file(input_file, current_section, process_line(line, current_section, unit_options))
      else
        process_file(input_file, current_section, process_line(line, current_section, unit_options))
      end
    else
      unit_options
    end
  end

  @doc false
  # Method to parse an individual line in the service file.
  #
  ## Options
  #
  # The `line` option is the String of the current line.
  #
  # The `current_section` option is the string representing the current section of the options.
  #
  # The `unit_options` option contains the List of currently known UnitOptions.
  #
  ## Return Values
  #
  # The List of all known UnitOptions
  #
  @spec process_line(String.t(), String.t(), List) :: List
  defp process_line(line, current_section, unit_options) do
    current_line = String.strip(line)
    if (String.starts_with? current_line, "#") do
      unit_options
    else
      if (String.starts_with? current_line, "[") do
        unit_options
      else
        new_option = parse_unit_option(current_section, current_line)
        if (new_option != nil) do
          unit_options ++ [new_option]
        else
          unit_options
        end
      end
    end
  end

  @doc false
  # Method to parse a line into a UnitOption
  #
  ## Options
  #
  # The `current_section` option is the string representing the current section of the options.
  #
  # The `current_line` option is the String of the current line.  
  #
  ## Return Values
  #
  # The parsed UnitOption or nil (if the line isn't an option)
  #
  @spec parse_unit_option(String.t(), String.t()) :: term
  defp parse_unit_option(current_section, current_line) do
    {_, name_index} = Enum.reduce( String.codepoints(current_line), {0, -1}, fn(str, { i, first_occurrence })->
      if str == "=" && first_occurrence < 0do
        first_occurrence = i
      end
      { i + 1, first_occurrence }
    end)

    name = String.slice(current_line, 0..name_index-1)
    value = String.slice(current_line, name_index+1..-1)
    if (name == nil || String.length(name) == 0 || value == nil || String.length(value) == 0) do
      nil
    else
      %{"section" => current_section, "name"=>name, "value"=>value}
    end
  end
end