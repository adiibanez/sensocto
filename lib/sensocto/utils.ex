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
end
