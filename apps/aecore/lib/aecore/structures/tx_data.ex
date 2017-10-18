defmodule Aecore.Structures.TxData do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.TxData
  @type tx_data() :: %TxData{}

  @doc """
  Definition of Aecore TxData structure

  ## Parameters
     - nonce: A random integer generated on initialisation of a transaction.Must be unique
     - from_acc: From account is the public address of one account originating the transaction
     - to_acc: To account is the public address of the account receiving the transaction
     - value: The amount of a transaction
  """
  defstruct [:nonce, :from_acc, :to_acc, :value]
  use ExConstructor

  @spec create(binary(), binary(), integer()) :: {:ok, %TxData{}}
  def create(from_acc, to_acc, value) do
    nonce = Enum.random(0..1_000_000_000_000)
    {:ok, %TxData{from_acc: from_acc, to_acc: to_acc, value: value, nonce: nonce}}
  end
end
