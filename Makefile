.PHONY: iex test e2e find enable ping

iex:
	@set -a && . ./.env && set +a && iex -S mix

test:
	@mix test

e2e:
	@set -a && . ./.env && set +a && mix test.e2e

find:
	@elixir .scripts/find_vestaboard.exs

enable:
	@set -a && . ./.env && set +a && elixir .scripts/enable_local_api.exs

ping:
	@set -a && . ./.env && set +a && elixir .scripts/test_connectivity.exs
