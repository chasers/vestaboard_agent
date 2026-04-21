.PHONY: iex test find enable ping

iex:
	@set -a && . ./.env && set +a && iex -S mix

test:
	@mix test

find:
	@elixir .scripts/find_vestaboard.exs

enable:
	@set -a && . ./.env && set +a && elixir .scripts/enable_local_api.exs

ping:
	@set -a && . ./.env && set +a && elixir .scripts/test_connectivity.exs
