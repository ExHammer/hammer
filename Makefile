# Hammer makefile

default: format test docs credo coveralls


format:
	mix format mix.exs "lib/**/*.{ex,exs}"


test: format
	mix test --no-start


docs:
	mix docs


coveralls:
	mix coveralls --no-start


coveralls-travis:
	mix coveralls.travis --no-start


.PHONY: format test docs credo coveralls coveralls-travis
