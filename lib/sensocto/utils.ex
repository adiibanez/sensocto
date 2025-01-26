defmodule Sensocto.Utils do
  def string_keys_to_atom_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      new_key = String.to_atom(key)
      Map.put(acc, new_key, value)
    end)
  end

  def atom_keys_to_string_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      new_key = Atom.to_string(key)
      Map.put(acc, new_key, value)
    end)
  end

  # def string_keys_to_atom_keys(map) when is_map(map) do
  #   map
  #   |> Enum.reduce(%{}, fn {key, value}, acc ->
  #     new_key = String.to_existing_atom(key)
  #     Map.put(acc, new_key, value)
  #   end)
  # end

  # def atom_keys_to_string_keys(map) when is_map(map) do
  #   map
  #   |> Enum.reduce(%{}, fn {key, value}, acc ->
  #     new_key = Atom.to_string(key)
  #     Map.put(acc, new_key, value)
  #   end)
  # end
end
