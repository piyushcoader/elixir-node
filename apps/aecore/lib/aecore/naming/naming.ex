defmodule Aecore.Naming.Naming do
  @moduledoc """
  Aecore naming module implementation.
  """

  alias Aecore.Chain.Chainstate
  alias Aecore.Naming.NameUtil
  alias Aecore.Keys.Wallet
  alias Aeutil.Hash
  alias Aeutil.Bits
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

  @pre_claim_ttl 300

  @revoke_expiration_ttl 2016

  @client_ttl_limit 86400

  @claim_expire_by_relative_limit 50000

  @name_salt_byte_size 32

  @type name_status() :: :claimed | :revoked

  @type claim :: %{
          hash: Identifier.t(),
          name: Identifier.t(),
          owner: Identifier.t(),
          expires: non_neg_integer(),
          status: name_status(),
          ttl: non_neg_integer(),
          pointers: list()
        }

  @type commitment :: %{
          hash: Identifier.t(),
          owner: Identifier.t(),
          created: non_neg_integer(),
          expires: non_neg_integer()
        }

  @type chain_state_name :: :naming

  @type salt :: binary()

  @type hash :: binary()

  @type t :: claim() | commitment()

  @type state() :: %{hash() => t()}

  @spec init_empty :: state()
  def init_empty, do: %{}

  @spec create_commitment(
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer()
        ) :: commitment()
  def create_commitment(hash, owner, created, expires) do
    # IO.inspect(owner, label: "Commitment owner from tx") #TODO check if it comes from one of naming TX's
    {:ok, identified_hash} = Identifier.create_identity(hash, :commitment)
    {:ok, identified_owner} = Identifier.create_identity(owner, :account)

    %{
      :hash => identified_hash,
      :owner => identified_owner,
      :created => created,
      :expires => expires
    }
  end

  @spec create_claim(
          Identifier.t(),
          binary(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          list()
        ) :: claim()
  def create_claim(hash, name, owner, expire_by, client_ttl, pointers) do
    # IO.inspect owner , label: "Claim owner from tx 1" #TODO check if it comes from one of naming TX's
    # {:ok, identified_hash} = Identifier.create_identity(hash ,:name)
    %{
      # identified_hash
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => expire_by,
      :status => :claimed,
      :ttl => client_ttl,
      :pointers => pointers
    }
  end

  @spec create_claim(Identifier.t(), binary(), Wallet.pubkey(), non_neg_integer()) :: claim()
  def create_claim(hash, name, owner, height) do
    # IO.inspect owner , label: "Claim owner from tx 2" #TODO check if it comes from one of naming TX's
    # {:ok, identified_hash} = Identifier.create_identity(hash, :name) 
    %{
      # identified_hash
      :hash => hash,
      :name => name,
      :owner => owner,
      :expires => height + @claim_expire_by_relative_limit,
      :status => :claimed,
      :ttl => @client_ttl_limit,
      :pointers => []
    }
  end

  @spec create_commitment_hash(String.t(), salt()) :: {:ok, Identifier.t()} | {:error, String.t()}
  def create_commitment_hash(name, name_salt) when is_binary(name_salt) do
    case NameUtil.normalized_namehash(name) do
      {:ok, hash} ->
        hashed_name = Hash.hash(hash <> name_salt)
        {:ok, identified_hashed_name} = Identifier.create_identity(hashed_name, :commitment)

      err ->
        err
    end
  end

  @spec get_claim_expire_by_relative_limit() :: non_neg_integer()
  def get_claim_expire_by_relative_limit, do: @claim_expire_by_relative_limit

  @spec get_client_ttl_limit() :: non_neg_integer()
  def get_client_ttl_limit, do: @client_ttl_limit

  @spec get_name_salt_byte_size() :: non_neg_integer()
  def get_name_salt_byte_size, do: @name_salt_byte_size

  @spec get_revoke_expiration_ttl() :: non_neg_integer()
  def get_revoke_expiration_ttl, do: @revoke_expiration_ttl

  @spec get_pre_claim_ttl() :: non_neg_integer()
  def get_pre_claim_ttl, do: @pre_claim_ttl

  @spec apply_block_height_on_state!(Chainstate.t(), integer()) :: Chainstate.t()
  def apply_block_height_on_state!(%{naming: naming_state} = chainstate, block_height) do
    updated_naming_state =
      naming_state
      |> Enum.filter(fn {_hash, name_state} -> name_state.expires > block_height end)
      |> Enum.into(%{})

    %{chainstate | naming: updated_naming_state}
  end

  def base58c_encode_hash(bin) do
    Bits.encode58c("nm", bin)
  end

  def base58c_decode_hash(<<"nm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_hash(_) do
    {:error, "Wrong data"}
  end

  def base58c_encode_commitment(bin) do
    Bits.encode58c("cm", bin)
  end

  def base58c_decode_commitment(<<"cm$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_commitment(_) do
    {:error, "Wrong data"}
  end

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), map(), :naming_state | :name_commitment) ::
          binary() | {:error, String.t()}
  def rlp_encode(tag, version, %{} = naming_state, :naming_state) do
    {:ok, encoded_hash} = Identifier.encode_data(naming_state.hash)
    IO.inspect(naming_state.owner, label: "RLP ENCODING NAMING STATE OWNER")

    list = [
      tag,
      version,
      encoded_hash,
      naming_state.owner,
      naming_state.expires,
      Atom.to_string(naming_state.status),
      naming_state.ttl,
      naming_state.pointers
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(tag, version, %{} = name_commitment, :name_commitment) do
    {:ok, encoded_commitment_hash} = Identifier.encode_data(name_commitment.hash)
    {:ok, encoded_commitment_owner} = Identifier.encode_data(name_commitment.owner)

    list = [
      tag,
      version,
      encoded_commitment_hash,
      encoded_commitment_owner,
      name_commitment.created,
      name_commitment.expires
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(term) do
    {:error, "Invalid Naming state / Name Commitment structure : #{inspect(term)}"}
  end

  @spec rlp_decode(list()) :: {:ok, map()} | {:error, String.t()}
  def rlp_decode([hash, owner, expires, status, ttl, pointers], :name) do
    {:ok, decoded_naming_hash} = Identifier.decode_data(hash)
    {:ok, identified_naming_hash} = Identifier.create_identity(decoded_naming_hash, :name)

    {:ok,
     %{
       hash: identified_naming_hash,
       owner: owner,
       expires: Serialization.transform_item(expires, :int),
       status: String.to_atom(status),
       ttl: Serialization.transform_item(ttl, :int),
       pointers: pointers
     }}
  end

  def rlp_decode([hash, owner, created, expires], :name_commitment) do
    {:ok, decoded_commitment_hash} = Identifier.decode_data(hash)
    {:ok, decoded_commitment_owner} = Identifier.decode_data(owner)

    {:ok, identified_commitment_hash} =
      Identifier.create_identity(decoded_commitment_hash, :commitment)

    {:ok, identified_commitment_owner} =
      Identifier.create_identity(decoded_commitment_owner, :commitment)

    {:ok,
     %{
       hash: identified_commitment_hash,
       owner: identified_commitment_owner,
       created: Serialization.transform_item(created, :int),
       expires: Serialization.transform_item(expires, :int)
     }}
  end

  def rlp_decode(_) do
    {:error, "#{__MODULE__} : Invalid Name state / Name Commitment serialization"}
  end
end
