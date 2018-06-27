# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

import_config "dev.exs"

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :aecore, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:aecore, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#

config :aecore, :pow,
  params: {"./mean28s-generic", "-t 5", 28},
  max_target_change: 1,
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    root_hash: <<0::256>>,
    time: 1_507_275_094_308,
    nonce: 304,
    miner: <<0::256>>,
    pow_evidence: [
      383_737,
      616_161,
      623_333,
      653_164,
      663_632,
      31_303_565,
      31_333_936,
      31_336_163,
      31_366_633,
      31_386_437,
      31_613_832,
      31_633_235,
      32_326_637,
      32_333_235,
      32_336_337,
      32_383_039,
      32_633_234,
      33_303_136,
      33_363_732,
      33_373_436,
      33_396_366,
      34_316_464,
      34_376_137,
      34_393_162,
      34_653_465,
      34_663_031,
      35_303_132,
      35_306_366,
      35_346_664,
      36_343_336,
      36_393_136,
      36_396_538,
      36_613_461,
      36_623_066,
      36_633_134,
      36_633_766,
      36_663_432,
      36_666_664,
      37_363_561,
      37_393_762,
      37_633_162,
      37_643_561
    ],
    version: 1,
    target: 0x2100FFFF
  }

config :aecore, :miner, resumed_by_default: true
