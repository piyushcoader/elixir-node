defmodule Aecore.Channel.Tx.ChannelCloseMutualTx do
  @moduledoc """
  Module defining the ChannelCloseMutual transaction
  """

  use Aecore.Tx.Transaction

  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Channel.{ChannelStateTree, ChannelStateOnChain}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Channel.Tx.{ChannelCloseMutualTx, ChannelCreateTx}
  alias Aecore.Tx.DataTx

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelCloseMutal Transaction"
  @type payload :: %{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelMutalClose Transaction type"
  @type t :: %ChannelCloseMutualTx{
          channel_id: binary(),
          initiator_amount: non_neg_integer(),
          responder_amount: non_neg_integer()
        }

  @doc """
  Definition of the ChannelCloseMutualTx structure

  # Parameters
  - channel_id: channel id
  - initiator_amount: the amount that the first sender commits
  - responder_amount: the amount that the second sender commits
  """
  defstruct [:channel_id, :initiator_amount, :responder_amount]

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  def chainstate_senders?(), do: true

  @doc """
  ChannelCloseMutualTx senders are not passed with tx, but are supposed to be retrieved from Chainstate. The senders have to be channel initiator and responder.
  """
  @spec senders_from_chainstate(ChannelCloseMutualTx.t(), Chainstate.t()) :: list(binary())
  def senders_from_chainstate(%ChannelCloseMutualTx{channel_id: channel_id}, chainstate) do
    case ChannelStateTree.get(chainstate.channels, channel_id) do
      %ChannelStateOnChain{} = channel ->
        [channel.initiator_pubkey, channel.responder_pubkey]

      :none ->
        []
    end
  end

  @spec init(payload()) :: ChannelCloseMutualTx.t()
  def init(%{
        channel_id: channel_id,
        initiator_amount: initiator_amount,
        responder_amount: responder_amount
      }) do
    %ChannelCloseMutualTx{
      channel_id: channel_id,
      initiator_amount: initiator_amount,
      responder_amount: responder_amount
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelCloseMutualTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ChannelCloseMutualTx{
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{senders: senders}
      ) do
    cond do
      !Identifier.valid?(senders, :account) ->
        {:error, "#{__MODULE__}: Invalid senders identifier: #{inspect(senders)}"}

      initiator_amount < 0 ->
        {:error, "#{__MODULE__}: initiator_amount can't be negative"}

      responder_amount < 0 ->
        {:error, "#{__MODULE__}: responder_amount can't be negative"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and closes channel (drops channel object from chainstate)
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseMutualTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCloseMutualTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{},
        _context
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    new_accounts =
      accounts
      |> AccountStateTree.update(channel.initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, initiator_amount)
      end)
      |> AccountStateTree.update(channel.responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, responder_amount)
      end)

    new_channels = ChannelStateTree.delete(channels, channel_id)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelCloseMutualTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        _accounts,
        channels,
        _block_height,
        %ChannelCloseMutualTx{
          channel_id: channel_id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        %DataTx{fee: fee},
        _context
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      initiator_amount < 0 ->
        {:error, "#{__MODULE__}: Negative initiator balance"}

      responder_amount < 0 ->
        {:error, "#{__MODULE__}: Negative responder balance"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel doesn't exist (already closed?)"}

      channel.total_amount != initiator_amount + responder_amount + fee ->
        {:error,
         "#{__MODULE__}: Wrong total balance, expected #{
           channel.initiator_amount + channel.responder_amount
         }, got #{initiator_amount + responder_amount + fee}"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, _block_height, _tx, _data_tx, _fee) do
    # Fee is deducted from channel
    accounts
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelCloseMutualTx.t(), DataTx.t()) :: list()
  def encode_to_list(%ChannelCloseMutualTx{} = tx, %DataTx{} = datatx) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(tx.channel_id, :channel),
      :binary.encode_unsigned(tx.initiator_amount),
      :binary.encode_unsigned(tx.responder_amount),
      :binary.encode_unsigned(datatx.ttl),
      :binary.encode_unsigned(datatx.fee),
      :binary.encode_unsigned(datatx.nonce)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_channel_id,
        initiator_amount,
        responder_amount,
        ttl,
        fee,
        nonce
      ]) do
    case Identifier.decode_from_binary_to_value(encoded_channel_id, :channel) do
      {:ok, channel_id} ->
        payload = %{
          channel_id: channel_id,
          initiator_amount: :binary.decode_unsigned(initiator_amount),
          responder_amount: :binary.decode_unsigned(responder_amount)
        }

        DataTx.init_binary(
          ChannelCloseMutualTx,
          payload,
          [],
          :binary.decode_unsigned(fee),
          :binary.decode_unsigned(nonce),
          :binary.decode_unsigned(ttl)
        )

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
