defmodule EpochElixir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_node,
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        paths: [
          "_build/test/lib/aecore/ebin",
          "_build/test/lib/aehttpclient/ebin",
          "_build/test/lib/aehttpserver/ebin",
          "_build/test/lib/aeutil/ebin"
        ],
        ignore_warnings: "dialyzer.ignore-warnings"
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      {:credo, "~> 0.8.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.2.0", only: :test},
      {:gb_merkle_trees, git: "https://github.com/aeternity/gb_merkle_trees.git", ref: "4db7aad"},
      {:enacl, [github: "jlouis/enacl", ref: "c8403ab", manager: :rebar]},
      {:sha3, [github: "szktty/erlang-sha3", ref: "dbdfd12", manager: :rebar]},
      {:idna, [github: "aeternity/erlang-idna", ref: "24bf647", manager: :rebar, override: true]},
      {:gen_state_machine, "~> 2.0.1"},
      {:logger_file_backend, "~> 0.0.10"},
      {:excoveralls, "~> 0.8.1", only: :test},
      {:ex_json_schema, "~> 0.5.4"},
      {:distillery, "~> 1.5.2", runtime: false},
      {:aewallet, github: "aeternity/elixir-wallet"},
      {:msgpax, "~> 2.1.1"},
      {:porcelain, "~> 2.0"},
      {:bip0173, "~> 0.1.2"},
      {:erl_base58, "~> 0.0.1"},
      {:temp, "~> 0.4"},
      {:ex_rlp, "~> 0.2.1"},
      {:temp, "~> 0.4"},
      {:merkle_patricia_tree, git: "https://github.com/aeternity/elixir-merkle-patricia-tree.git"}
    ]
  end
end
