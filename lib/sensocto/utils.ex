defmodule Sensocto.Utils do
  @moduledoc """
  General utility functions.
  """

  def typeof(a) do
    cond do
      is_float(a) -> "float"
      is_number(a) -> "number"
      is_atom(a) -> "atom"
      is_boolean(a) -> "boolean"
      is_binary(a) -> "binary"
      is_function(a) -> "function"
      is_list(a) -> "list"
      is_tuple(a) -> "tuple"
      true -> "idunno"
    end
  end

  def binary_to_integer(binary) when is_binary(binary) do
    case Integer.parse(binary) do
      {integer, _} ->
        integer

      :error ->
        # Handle the case where the binary cannot be parsed as an integer
        # Or raise an error, log a message, etc.
        nil
    end
  end
end
