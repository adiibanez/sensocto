defmodule Sensocto.Utils do
  @moduledoc """
  General utility functions.

  **DEPRECATION WARNING**: The `string_keys_to_atom_keys/1` function is deprecated
  due to atom exhaustion vulnerability. Use `Sensocto.Types.SafeKeys.safe_keys_to_atoms/1`
  instead, which only converts whitelisted keys to atoms.
  """

  @doc """
  Converts string keys to atom keys recursively.

  **DEPRECATED**: This function creates atoms from arbitrary strings which can lead
  to atom exhaustion attacks (DoS). The Erlang atom table is limited and atoms are
  never garbage collected.

  Use `Sensocto.Types.SafeKeys.safe_keys_to_atoms/1` instead.

  ## Security Risk

  If this function is called with untrusted input (e.g., WebSocket data, API requests),
  an attacker can exhaust the atom table by sending unique strings, crashing the VM.
  """
  @deprecated "Use Sensocto.Types.SafeKeys.safe_keys_to_atoms/1 instead - this function is vulnerable to atom exhaustion attacks"
  def string_keys_to_atom_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      new_key = String.to_atom(key)
      new_value = if is_map(value), do: string_keys_to_atom_keys(value), else: value
      Map.put(acc, new_key, new_value)
    end)
  end

  @doc """
  Converts atom keys to string keys recursively.
  This function is safe to use as it only converts atoms that already exist.
  """
  def atom_keys_to_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      new_key = Atom.to_string(key)
      new_value = if is_map(value), do: atom_keys_to_string_keys(value), else: value
      Map.put(acc, new_key, new_value)
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
