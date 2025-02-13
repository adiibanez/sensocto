defmodule Sensocto.Utils do
  def string_keys_to_atom_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      new_key = String.to_atom(key)
      Map.put(acc, new_key, value)
    end)
  end

  def atom_keys_to_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      new_key = Atom.to_string(key)
      Map.put(acc, new_key, value)
    end)
  end

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
