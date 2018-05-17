defmodule Aecore.Chain.Header do
  @moduledoc """
  Structure of Header
  """

  alias Aecore.Chain.Header
  alias Aeutil.Bits

  @type t :: %Header{
          height: non_neg_integer(),
          prev_hash: binary(),
          txs_hash: binary(),
          root_hash: binary(),
          time: non_neg_integer(),
          nonce: non_neg_integer(),
          version: non_neg_integer(),
          target: non_neg_integer()
        }

  defstruct [
    :height,
    :prev_hash,
    :txs_hash,
    :root_hash,
    :target,
    :nonce,
    :pow_evidence,
    :time,
    :version
  ]

  use ExConstructor

  @spec create(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: Header.t()

  def create(height, prev_hash, txs_hash, root_hash, target, nonce, version, time) do
    %Header{
      height: height,
      prev_hash: prev_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      time: time,
      nonce: nonce,
      version: version,
      target: target
    }
  end

  def base58c_encode(bin) do
    Bits.encode58c("bh", bin)
  end

  def base58c_decode(<<"bh$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  @spec header_to_binary(Header.t()) :: binary
  def header_to_binary(%Header{} = header) do
    pow_to_binary = pow_to_binary(header.pow_evidence)

    <<
      header.version::64,
      header.height::64,
      header.prev_hash::binary-size(32),
      header.txs_hash::binary-size(32),
      header.root_hash::binary-size(32),
      header.target::64,
      pow_to_binary::binary-size(168),
      header.nonce::64,
      header.time::64
    >>
  end

  def header_to_binary(_) do
    {:error, "Illegal structure serialization"}
  end

  @spec binary_to_header(binary()) :: Header.t() | {:error, String.t()}
  def binary_to_header(binary) when is_binary(binary) do
    <<version::64, height::64, prev_hash::binary-size(32), txs_hash::binary-size(32),
      root_hash::binary-size(32), target::64, pow_evidence_bin::binary-size(168), nonce::64,
      time::64>> = binary

    pow_evidence = binary_to_pow(pow_evidence_bin)

    %Header{
      height: height,
      nonce: nonce,
      pow_evidence: pow_evidence,
      prev_hash: prev_hash,
      root_hash: root_hash,
      target: target,
      time: time,
      txs_hash: txs_hash,
      version: version
    }
  end

  def binary_to_header(_) do
    {:error, "Illegal header binary serialization"}
  end

  @spec pow_to_binary(list()) :: binary() | list() | {:error, String.t()}
  def pow_to_binary(pow) when is_list(pow) do
    if Enum.count(pow) == 42 do
      list_of_pows =
        for evidence <- pow do
          <<evidence::32>>
        end

      serialize_pow(:binary.list_to_bin(list_of_pows), <<>>)
    else
      List.duplicate(0, 42)
    end
  end

  @spec serialize_pow(binary(), binary()) :: binary() | {:error, String.t()}
  defp serialize_pow(pow, acc) when pow != <<>> do
    <<elem::binary-size(4), rest::binary>> = pow
    acc = acc <> elem
    serialize_pow(rest, acc)
  end

  defp serialize_pow(<<>>, acc) do
    acc
  end

  @spec binary_to_pow(binary()) :: list() | {:error, atom()}
  def binary_to_pow(<<pow_bin_list::binary-size(168)>>) do
    deserialize_pow(pow_bin_list, [])
  end

  def binary_to_pow(_) do
    {:error, "Illegal PoW serialization"}
  end

  defp deserialize_pow(<<pow::32, rest::binary>>, acc) do
    acc = [pow | acc]
    deserialize_pow(rest, acc)
  end

  defp deserialize_pow(<<>>, acc) do
    if Enum.count(Enum.filter(acc, fn x -> is_integer(x) and x >= 0 end)) == 42 do
      Enum.reverse(acc)
    else
      {:error, "Illegal PoW serialization"}
    end
  end
end
