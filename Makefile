.PHONY: iex test e2e find enable ping clear-tools

iex:
	@set -a && . ./.env && set +a && iex -S mix

test:
	@MIX_ENV=test mix test

e2e:
	@set -a && . ./.env && set +a && mix test.e2e $(if $(T),$(T),)

find:
	@elixir .scripts/find_vestaboard.exs

enable:
	@set -a && . ./.env && set +a && elixir .scripts/enable_local_api.exs

ping:
	@set -a && . ./.env && set +a && elixir .scripts/test_connectivity.exs

clear-tools:
	@rm -f priv/lua_tools/*.lua && echo "Cleared priv/lua_tools/"
